import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../core/utils/audio_paths.dart';
import '../../../../models/chat_message.dart';
import '../../../../models/chat_session.dart';
import '../../../../models/chat_source_ref.dart';
import '../../../../models/document.dart';
import '../../../../providers/app_providers.dart';
import '../../../../services/ai/model_lifecycle_manager.dart' show ModelKind;
import '../../../../services/documents/document_import_service.dart' show DocumentImportException;
import '../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/inline_error_text.dart';
import '../../../../shared/widgets/markdown_body.dart';
import '../../../ai_models/presentation/providers/installed_models_providers.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../meetings/presentation/providers/meeting_providers.dart';
import '../providers/chat_export_service.dart';
import '../providers/chat_providers.dart';

enum _ExportFormat { txt, markdown, pdf, copy }

/// Local (non-persisted) composer state for the mic button - speaking a
/// question is a short, on-screen interaction, unlike a meeting recording,
/// so it's plain [State] rather than a Riverpod-tracked, resumable session.
enum _VoiceInputState { idle, recording, transcribing }

/// The single chat experience (ADR-013, docs/v2/implementation/03-decisions.md):
/// one screen, a scope selector inside it (Workspace/Meeting/Document/
/// General - M2.1/FR-31) rather than three separate screens or routes.
/// Switching scope never navigates anywhere - it only changes what
/// [ChatController.sendMessage] retrieves against ([ChatScope.general]
/// retrieves nothing at all, per [GeneralChatUseCase]).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.launchArgs});

  final ChatLaunchArgs? launchArgs;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  /// Set while the user is editing an earlier message (Phase 8B.1,
  /// Priority 2) - non-null between tapping "Edit" and either sending the
  /// edited text or cancelling. Pressing Send while this is set calls
  /// [ChatController.editAndResend] instead of the normal
  /// [ChatController.sendMessage] path.
  ChatMessage? _editingMessage;

  /// A file the user picked from the composer's attachment button, already
  /// imported and fully processed (extracted + summarized + indexed)
  /// through the same pipeline the Documents feature itself uses - see
  /// `_attachFile`. Non-null only once it's actually ready to ground a
  /// question; deliberately reuses [ChatScope.document] (set via
  /// [ChatController.setScope]) rather than adding any new attachment
  /// field to [ChatMessage]/a second retrieval path, per R-7's explicit
  /// "do not build a second RAG system" instruction - an attached file
  /// *is* just this conversation's document scope, populated from the
  /// composer instead of the pre-session [_DocumentPicker] dropdown.
  Document? _attachment;
  bool _isAttaching = false;
  String? _attachmentError;

  _VoiceInputState _voiceState = _VoiceInputState.idle;
  String? _voiceError;

  @override
  void initState() {
    super.initState();
    final args = widget.launchArgs;
    // Deferred a frame: mutating chatControllerProvider's state during the
    // very first build (which reading it synchronously here would risk)
    // isn't safe in Riverpod - this mirrors the same "act once mounted,
    // not while building" discipline used elsewhere in this app for
    // one-time post-navigation setup.
    Future.microtask(() {
      if (!mounted) return;
      final controller = ref.read(chatControllerProvider.notifier);
      if (args?.sessionId != null) {
        controller.openSession(args!.sessionId!);
      } else if (args?.scope != null) {
        controller.startNewConversation(
          scope: args!.scope!,
          meetingId: args.meetingId,
          documentId: args.documentId,
        );
      }
    });
  }

  @override
  void dispose() {
    // Best-effort only - `recorderServiceProvider` is a single shared
    // instance for the app's whole lifetime (also used by meeting
    // recording), so this stops *this* in-progress capture without
    // disposing the service itself.
    if (_voiceState == _VoiceInputState.recording) {
      unawaited(ref.read(recorderServiceProvider).stop());
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _canAttach => !ref.read(chatControllerProvider).hasActiveSession;

  Future<void> _attachFile() async {
    if (!_canAttach) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start a new chat to attach a different file.')),
      );
      return;
    }
    setState(() {
      _isAttaching = true;
      _attachmentError = null;
    });
    try {
      final documentId = await ref.read(documentImportUseCaseProvider)();
      if (documentId == null) {
        // User cancelled the file picker.
        if (mounted) setState(() => _isAttaching = false);
        return;
      }
      await ref.read(processNewDocumentUseCaseProvider)(documentId);
      final document = await ref.read(documentRepositoryProvider).getById(documentId);
      ref.invalidate(documentListProvider);
      ref.invalidate(chatEligibleDocumentsProvider);
      if (!mounted) return;
      if (document == null || document.status != DocumentStatus.ready) {
        setState(() {
          _isAttaching = false;
          _attachmentError = "Couldn't read that file - it may not contain any "
              'readable text, or the on-device model needed to process it '
              "isn't installed yet.";
        });
        return;
      }
      setState(() {
        _isAttaching = false;
        _attachment = document;
      });
      ref.read(chatControllerProvider.notifier).setScope(ChatScope.document, documentId: document.id);
    } on DocumentImportException catch (e) {
      if (!mounted) return;
      setState(() {
        _isAttaching = false;
        _attachmentError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAttaching = false;
        _attachmentError = "Couldn't attach that file. Please try again.";
      });
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachment = null;
      _attachmentError = null;
    });
    // Only resets the *composer's* pending scope choice, not the imported
    // file itself - it stays wherever a normal document import always
    // lands (visible in Documents/Recent Documents), same as removing a
    // meeting/document pick from `_ScopeSelector` never deletes anything.
    if (!ref.read(chatControllerProvider).hasActiveSession) {
      ref.read(chatControllerProvider.notifier).setScope(ChatScope.workspace);
    }
  }

  Future<void> _toggleRecording() async {
    if (_voiceState == _VoiceInputState.recording) {
      await _stopRecordingAndTranscribe();
      return;
    }
    if (_voiceState != _VoiceInputState.idle) return;

    final recorder = ref.read(recorderServiceProvider);
    final hasPermission = await recorder.hasMicrophonePermission();
    if (!mounted) return;
    if (!hasPermission) {
      setState(() {
        _voiceError = 'OfflineMoMAI needs microphone access to record your question. '
            'Check the microphone permission for this app in your device settings.';
      });
      return;
    }

    final filePath = await newAudioFilePath();
    try {
      await recorder.start(filePath);
    } catch (_) {
      if (!mounted) return;
      setState(() => _voiceError = 'Could not start recording. Please try again.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _voiceState = _VoiceInputState.recording;
      _voiceError = null;
    });
  }

  Future<void> _stopRecordingAndTranscribe() async {
    final recorder = ref.read(recorderServiceProvider);
    // Deliberately no fallback to `_recordingFilePath` here - `stop()`
    // returning null specifically means the recorder captured nothing
    // (RecorderService's own contract), so falling back to the
    // pre-recording path would try to transcribe a file that may not even
    // have any audio in it.
    final path = await recorder.stop();
    if (!mounted) return;
    setState(() => _voiceState = _VoiceInputState.transcribing);

    if (path == null) {
      setState(() {
        _voiceState = _VoiceInputState.idle;
        _voiceError = 'No audio was captured. Please try again.';
      });
      return;
    }

    try {
      final result = await ref.read(speechToTextEngineProvider).transcribe(
            path,
            onPreparingModel: () {
              if (mounted) setState(() {}); // transcribing state already shown; no extra label needed
            },
          );
      if (!mounted) return;
      final transcribed = result.fullText.trim();
      setState(() {
        _voiceState = _VoiceInputState.idle;
        if (transcribed.isNotEmpty) {
          final existing = _inputController.text;
          _inputController.text = existing.isEmpty ? transcribed : '$existing $transcribed';
          _inputController.selection = TextSelection.collapsed(offset: _inputController.text.length);
        } else {
          _voiceError = "Didn't catch that - please try again or type your question.";
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceState = _VoiceInputState.idle;
        _voiceError = 'Could not transcribe that recording. Please try again or type your question.';
      });
    } finally {
      unawaited(_deleteQuietly(path));
    }
  }

  Future<void> _cancelRecording() async {
    final recorder = ref.read(recorderServiceProvider);
    final path = await recorder.stop();
    if (path != null) unawaited(_deleteQuietly(path));
    if (!mounted) return;
    setState(() => _voiceState = _VoiceInputState.idle);
  }

  /// The recording behind a transcribed (or abandoned) voice question is
  /// scratch input, unlike a meeting's audio file - nothing else in the app
  /// ever needs it again once transcription is done, so it's deleted
  /// immediately rather than left in `recordings/` indefinitely.
  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Already gone, or never existed - nothing to clean up.
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _send() {
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    final editing = _editingMessage;
    if (editing != null) {
      setState(() => _editingMessage = null);
      ref.read(chatControllerProvider.notifier).editAndResend(editing, text);
    } else {
      ref.read(chatControllerProvider.notifier).sendMessage(text);
    }
    _inputController.clear();
  }

  void _beginEdit(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _inputController.text = message.content;
      _inputController.selection = TextSelection.collapsed(offset: message.content.length);
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _inputController.clear();
    });
  }

  Future<void> _copyMessage(ChatMessage message) async {
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard.'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete this message?',
      message: 'This removes only this message. This can\'t be undone.',
    );
    if (!confirmed) return;
    if (_editingMessage?.id == message.id) _cancelEdit();
    await ref.read(chatControllerProvider.notifier).deleteMessage(message);
  }

  /// Quick-action chip tapped (Phase 2B "Workspace Chat improvements",
  /// docs/v2/implementation/03-decisions.md ADR-028) - sends [question]
  /// immediately rather than just prefilling the input, same one-tap
  /// convention as a suggested-reply chip in any other chat UI. No new AI
  /// capability: this is `ChatController.sendMessage` with a canned
  /// question instead of typed text.
  void _sendQuickAction(String question) {
    ref.read(chatControllerProvider.notifier).sendMessage(question);
  }

  static const _exportService = ChatExportService();

  Future<void> _exportChat(ChatState state, _ExportFormat format) async {
    if (state.messages.isEmpty) return;
    final title = state.session?.title ?? 'OfflineMoMAI chat';
    switch (format) {
      case _ExportFormat.txt:
        await SharePlus.instance.share(
          ShareParams(
            text: _exportService.buildPlainText(state.session, state.messages),
            subject: title,
          ),
        );
      case _ExportFormat.markdown:
        await SharePlus.instance.share(
          ShareParams(
            text: _exportService.buildMarkdown(state.session, state.messages),
            subject: title,
          ),
        );
      case _ExportFormat.pdf:
        final bytes = await _exportService.buildPdf(state.session, state.messages);
        await Printing.sharePdf(bytes: bytes, filename: '$title.pdf');
      case _ExportFormat.copy:
        await Clipboard.setData(
          ClipboardData(text: _exportService.buildPlainText(state.session, state.messages)),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation copied to clipboard.')),
        );
    }
  }

  /// Whether this scope/session currently has enough context to send
  /// *anything* - independent of what (if anything) is typed in the input,
  /// so it can also gate the empty-state quick-action chips
  /// ([_sendQuickAction]), which bypass the input field entirely.
  bool _canStartTurn(ChatState state) {
    if (state.isSending) return false;
    if (state.hasActiveSession) return true;
    return switch (state.scope) {
      ChatScope.meeting => state.meetingId != null,
      ChatScope.document => state.documentId != null,
      ChatScope.workspace || ChatScope.general => true,
    };
  }


  @override
  Widget build(BuildContext context) {
    // A side effect only (Phase 3B) - `ref.listen` doesn't itself rebuild
    // this widget, unlike the `ref.watch(chatControllerProvider)` this
    // replaced, which previously made every part of this screen (AppBar,
    // scope selector, input bar) rebuild once per streamed token just to
    // run this comparison. Only `_ConversationBody`'s own `Consumer` below
    // now watches the full state - the one place that legitimately needs
    // to redraw every token.
    ref.listen<ChatState>(chatControllerProvider, (previous, next) {
      final messageCount = next.messages.length;
      if (messageCount != _lastMessageCount || (next.isSending && next.streamingText != null)) {
        _lastMessageCount = messageCount;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    });

    final scheme = Theme.of(context).colorScheme;

    // V2.2 Production Hardening, Priority 1 (real-device QA request):
    // detected once, up front, before any of the normal chat UI (scope
    // selector, input bar, "Ask anything" empty state) ever renders -
    // previously, opening Chat with no Chat LLM installed would only fail
    // once a message was actually sent, surfacing whatever raw error the
    // engine happened to throw. Reuses `installedModelsControllerProvider`
    // (the same provider the AI Model Manager already reads) rather than
    // adding a new one. While it's still loading (a single, fast local DB
    // query - effectively instant in practice), `hasLlm` stays `true` so
    // this doesn't flash the empty state for a normal user on every open;
    // only a *confirmed* empty result shows it.
    final installedModelsAsync = ref.watch(installedModelsControllerProvider);
    final hasLlm = installedModelsAsync.maybeWhen(
      data: (installed) => installed.any((m) => m.kind == ModelKind.llm),
      orElse: () => true,
    );
    if (!hasLlm) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const EmptyState(
                    icon: Icons.smart_toy_outlined,
                    title: 'No AI model is installed yet',
                    message: 'Download a recommended model to start chatting.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.push(RoutePaths.aiModelSetup),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Get Recommended Models'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Consumer(
          builder: (context, ref, _) {
            final title = ref.watch(chatControllerProvider.select((s) => s.session?.title));
            return Text(title ?? 'New chat', overflow: TextOverflow.ellipsis);
          },
        ),
        // Phase 8B.3, Priority 5: always visible, independent of the
        // scope-picker above the conversation (which disappears once a
        // session starts) - the AppBar's own title is the conversation's
        // auto-generated title (from its first question), never the
        // document/meeting name, so without this a user resuming an old
        // document-scoped chat had no way to tell which document the AI
        // was actually using as context.
        bottom: const _ScopeIndicatorBar(),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final hasActiveSession =
                  ref.watch(chatControllerProvider.select((s) => s.hasActiveSession));
              return IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: 'New chat',
                onPressed: hasActiveSession
                    ? () => ref.read(chatControllerProvider.notifier).startNewConversation()
                    : null,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Chat history',
            onPressed: () => context.push(RoutePaths.chatHistory),
          ),
          Consumer(
            builder: (context, ref, _) {
              final state = ref.watch(chatControllerProvider);
              final enabled = state.messages.isNotEmpty && !state.isSending;
              return PopupMenuButton<_ExportFormat>(
                icon: const Icon(Icons.ios_share_outlined),
                tooltip: 'Export chat',
                enabled: enabled,
                onSelected: (format) => _exportChat(state, format),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _ExportFormat.pdf, child: Text('Export as PDF')),
                  PopupMenuItem(value: _ExportFormat.markdown, child: Text('Export as Markdown')),
                  PopupMenuItem(value: _ExportFormat.txt, child: Text('Export as text')),
                  PopupMenuItem(value: _ExportFormat.copy, child: Text('Copy conversation')),
                ],
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Only reads the full state while it's actually visible
            // (before a session exists) - once a conversation is active,
            // this rebuilds solely on the `hasActiveSession` flip back to
            // hidden, not on every token (there's nothing to stream before
            // a session exists in the first place, so this costs nothing
            // extra while a message is generating).
            Consumer(
              builder: (context, ref, _) {
                final hasActiveSession =
                    ref.watch(chatControllerProvider.select((s) => s.hasActiveSession));
                if (hasActiveSession) return const SizedBox.shrink();
                return _ScopeSelector(state: ref.watch(chatControllerProvider));
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final state = ref.watch(chatControllerProvider);
                  return _ConversationBody(
                    state: state,
                    scrollController: _scrollController,
                    onQuickAction: _canStartTurn(state) ? _sendQuickAction : null,
                    onEdit: _beginEdit,
                    onRegenerate: (message) =>
                        ref.read(chatControllerProvider.notifier).regenerateMessage(message),
                    onCopy: _copyMessage,
                    onDelete: _deleteMessage,
                  );
                },
              ),
            ),
            Consumer(
              builder: (context, ref, _) {
                final error = ref.watch(chatControllerProvider.select((s) => s.error));
                if (error == null) return const SizedBox.shrink();
                return _ErrorBanner(
                  message: error,
                  onRetry: () => ref.read(chatControllerProvider.notifier).retry(),
                );
              },
            ),
            if (_editingMessage != null) _EditingBanner(onCancel: _cancelEdit),
            Consumer(
              builder: (context, ref, _) {
                final fields = ref.watch(
                  chatControllerProvider.select(
                    (s) => (
                      isSending: s.isSending,
                      canStartTurn: _canStartTurn(s),
                      hasActiveSession: s.hasActiveSession,
                    ),
                  ),
                );
                return _InputBar(
                  controller: _inputController,
                  // `_canStartTurn` already folds in `!isSending`; kept as
                  // one boolean here (mirrors the original `_canSend`'s
                  // exact condition) rather than re-checking it a second
                  // time.
                  canSend: fields.canStartTurn && _inputController.text.trim().isNotEmpty,
                  isSending: fields.isSending,
                  onChanged: () => setState(() {}),
                  onSend: _send,
                  onCancel: () => ref.read(chatControllerProvider.notifier).cancel(),
                  scheme: scheme,
                  attachment: _attachment,
                  isAttaching: _isAttaching,
                  attachmentError: _attachmentError,
                  canAttach: !fields.hasActiveSession,
                  onAttach: _attachFile,
                  onRemoveAttachment: _removeAttachment,
                  voiceState: _voiceState,
                  voiceError: _voiceError,
                  onMicTap: _toggleRecording,
                  onCancelRecording: _cancelRecording,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A slim, always-visible bar naming exactly what this conversation is
/// grounded in (Phase 8B.3, Priority 5) - "Workspace," a meeting's title,
/// or a document's title, resolved live from [ChatState.meetingId]/
/// [documentId] rather than baked into the (unrelated) auto-generated
/// session title.
///
/// Only shown once a session is active - before that, [_ScopeSelector]'s own
/// segmented control already states the scope clearly (and, for Workspace,
/// in the same literal word this bar would otherwise repeat directly below
/// it - a duplicate label, not a helpful one). The reserved height stays
/// constant either way (a blank strip pre-session, not a collapsed one) so
/// the AppBar never visibly resizes as a conversation starts.
class _ScopeIndicatorBar extends StatelessWidget implements PreferredSizeWidget {
  const _ScopeIndicatorBar();

  @override
  Size get preferredSize => const Size.fromHeight(32);

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final hasActiveSession =
            ref.watch(chatControllerProvider.select((s) => s.hasActiveSession));
        if (!hasActiveSession) return const SizedBox(height: 32);

        final scope = ref.watch(chatControllerProvider.select((s) => s.scope));
        final meetingId = ref.watch(chatControllerProvider.select((s) => s.meetingId));
        final documentId = ref.watch(chatControllerProvider.select((s) => s.documentId));

        return switch (scope) {
          ChatScope.meeting when meetingId != null => Consumer(
              builder: (context, ref, _) {
                final meeting = ref.watch(meetingByIdProvider(meetingId)).valueOrNull;
                return _ScopeChip(
                  icon: Icons.mic_none_rounded,
                  label: meeting?.title ?? 'Meeting',
                  onTap: () => context.push(RoutePaths.meetingDetailsPath(meetingId)),
                );
              },
            ),
          ChatScope.document when documentId != null => Consumer(
              builder: (context, ref, _) {
                final document = ref.watch(documentByIdProvider(documentId)).valueOrNull;
                return _ScopeChip(
                  icon: Icons.description_outlined,
                  label: document?.title ?? 'Document',
                  onTap: () => context.push(RoutePaths.documentDetailsPath(documentId)),
                );
              },
            ),
          ChatScope.general =>
            const _ScopeChip(icon: Icons.public, label: 'General'),
          ChatScope.workspace ||
          ChatScope.meeting ||
          ChatScope.document =>
            const _ScopeChip(icon: Icons.workspaces_outline, label: 'Workspace'),
        };
      },
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;

  /// Set only for a meeting/document scope (never Workspace, which has no
  /// single destination to jump to) - navigates straight to that meeting's
  /// or document's own details screen, so this bar doubles as a shortcut
  /// back to the thing the conversation is grounded in.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 14, color: scheme.onSurfaceVariant),
        ],
      ],
    );

    final chip = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: content,
    );

    if (onTap == null) return chip;

    return Semantics(
      button: true,
      child: InkWell(onTap: onTap, child: chip),
    );
  }
}

class _ScopeSelector extends ConsumerWidget {
  const _ScopeSelector({required this.state});

  final ChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(chatControllerProvider.notifier);
    final currentScope = state.scope;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ChatScope>(
            segments: const [
              ButtonSegment(
                value: ChatScope.workspace,
                label: Text('Workspace'),
                icon: Icon(Icons.workspaces_outline),
              ),
              ButtonSegment(
                value: ChatScope.meeting,
                label: Text('Meeting'),
                icon: Icon(Icons.mic_none_rounded),
              ),
              ButtonSegment(
                value: ChatScope.document,
                label: Text('Document'),
                icon: Icon(Icons.description_outlined),
              ),
              // M2.1/FR-31: a general, unscoped conversation - no retrieval,
              // answered from the model's own knowledge (GeneralChatUseCase).
              ButtonSegment(
                value: ChatScope.general,
                label: Text('General'),
                icon: Icon(Icons.public),
              ),
            ],
            selected: {currentScope},
            onSelectionChanged: (selection) => controller.setScope(selection.first),
          ),
          if (currentScope == ChatScope.meeting) ...[
            const SizedBox(height: 10),
            _MeetingPicker(
              selectedId: state.meetingId,
              onSelected: (id) => controller.setScope(ChatScope.meeting, meetingId: id),
            ),
          ],
          if (currentScope == ChatScope.document) ...[
            const SizedBox(height: 10),
            _DocumentPicker(
              selectedId: state.documentId,
              onSelected: (id) => controller.setScope(ChatScope.document, documentId: id),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeetingPicker extends ConsumerWidget {
  const _MeetingPicker({required this.selectedId, required this.onSelected});

  final int? selectedId;
  final void Function(int id) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingsAsync = ref.watch(chatEligibleMeetingsProvider);
    return meetingsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => InlineErrorText(err),
      data: (meetings) {
        if (meetings.isEmpty) {
          return Text(
            'No fully-processed meetings yet.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return DropdownButtonFormField<int>(
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Which meeting?',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final meeting in meetings)
              DropdownMenuItem(
                value: meeting.id,
                child: Text(meeting.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) onSelected(id);
          },
        );
      },
    );
  }
}

class _DocumentPicker extends ConsumerWidget {
  const _DocumentPicker({required this.selectedId, required this.onSelected});

  final int? selectedId;
  final void Function(int id) onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documentsAsync = ref.watch(chatEligibleDocumentsProvider);
    return documentsAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (err, _) => InlineErrorText(err),
      data: (documents) {
        if (documents.isEmpty) {
          return Text(
            'No fully-processed documents yet.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return DropdownButtonFormField<int>(
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Which document?',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final document in documents)
              DropdownMenuItem(
                value: document.id,
                child: Text(document.title, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) {
            if (id != null) onSelected(id);
          },
        );
      },
    );
  }
}

class _ConversationBody extends StatelessWidget {
  const _ConversationBody({
    required this.state,
    required this.scrollController,
    required this.onQuickAction,
    required this.onEdit,
    required this.onRegenerate,
    required this.onCopy,
    required this.onDelete,
  });

  final ChatState state;
  final ScrollController scrollController;

  /// Null when this scope/session doesn't yet have enough context to send
  /// anything (e.g. meeting-scoped with no meeting picked yet) - hides the
  /// quick-action chips rather than showing chips that would just fail.
  final void Function(String question)? onQuickAction;
  final void Function(ChatMessage message) onEdit;
  final void Function(ChatMessage assistantMessage) onRegenerate;
  final void Function(ChatMessage message) onCopy;
  final void Function(ChatMessage message) onDelete;

  String _scopeDescription(ChatScope scope) => switch (scope) {
        ChatScope.workspace => 'your meetings and documents',
        ChatScope.meeting => 'the selected meeting',
        ChatScope.document => 'the selected document',
        ChatScope.general => 'anything',
      };

  /// Quick actions (Phase 2B "Workspace Chat improvements") - no new AI
  /// capability, just a one-tap shortcut for the questions users ask most.
  List<String> _quickActions(ChatScope scope) => switch (scope) {
        ChatScope.meeting => const [
            'Summarize this meeting',
            'What were the action items?',
            'What decisions were made?',
          ],
        ChatScope.document => const [
            'Summarize this document',
            'What are the key points?',
          ],
        ChatScope.workspace => const [
            "What's new across my meetings?",
            'Any open action items?',
            'Any recent decisions?',
          ],
        // General has no content to ask about (GeneralChatUseCase never
        // retrieves anything) - Workspace's questions would just fail
        // silently against an empty context, so this gets its own,
        // content-free set instead of reusing them.
        ChatScope.general => const [
            'Help me think through a problem',
            'Explain a concept to me',
            'Give me writing feedback',
          ],
      };

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }

    final showStreaming = state.isSending;
    if (state.messages.isEmpty && !showStreaming) {
      final onQuickAction = this.onQuickAction;
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyState(
                icon: Icons.forum_outlined,
                title: 'Ask anything',
                message: state.scope == ChatScope.general
                    ? 'Think something through with the on-device assistant - '
                        'this conversation isn\'t scoped to any meeting or '
                        'document, so answers come from the AI model\'s own '
                        'general knowledge, not your content.'
                    : 'Ask a question about ${_scopeDescription(state.scope)} - '
                        'answers are grounded in what\'s actually been recorded or '
                        'imported, with sources shown for every answer.',
              ),
              if (onQuickAction != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final question in _quickActions(state.scope))
                      ActionChip(
                        label: Text(question),
                        onPressed: () => onQuickAction(question),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: state.messages.length + (showStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= state.messages.length) {
          return _StreamingBubble(
            text: state.streamingText ?? '',
            isPreparingModel: state.isPreparingModel,
            modelPrepProgress: state.modelPrepProgress,
          );
        }
        final message = state.messages[index];
        final previousUserPrompt = message.role == ChatMessageRole.assistant && index > 0
            ? state.messages[index - 1]
            : null;
        return _MessageBubble(
          message: message,
          onEdit: message.role == ChatMessageRole.user ? () => onEdit(message) : null,
          onRegenerate: message.role == ChatMessageRole.assistant &&
                  previousUserPrompt?.role == ChatMessageRole.user
              ? () => onRegenerate(message)
              : null,
          onCopy: () => onCopy(message),
          onDelete: () => onDelete(message),
        );
      },
    );
  }
}

/// Actions offered from a message bubble's overflow menu (V2.2 Batch 2,
/// Premium Chat Experience) - Copy stays a directly-visible icon since it's
/// the single most common action; Edit/Regenerate/Delete moved here to
/// replace what used to be up to four always-visible icons crowding every
/// bubble.
enum _MessageAction { edit, regenerate, delete }

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onEdit,
    this.onRegenerate,
    required this.onCopy,
    required this.onDelete,
  });

  final ChatMessage message;
  final VoidCallback? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return _EntranceFade(child: _buildBubble(context));
  }

  Widget _buildBubble(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final sources = ChatSourceRef.decodeList(message.sourcesJson);
    final isGeneralKnowledge = message.answerProvenance == AnswerProvenance.generalKnowledge;
    // Priority 6 (Phase 8B.1): a *positive* "grounded in your content"
    // label, symmetric with the general-knowledge one below, so provenance
    // is never just implied by chip-presence - every assistant answer that
    // cites something says so in the same visual language as the answers
    // that don't.
    final isGrounded = message.answerProvenance == AnswerProvenance.local && sources.isNotEmpty;

    // Who said this is conveyed visually only by bubble alignment/color -
    // invisible to TalkBack, which reads widgets in tree order with no
    // sense of "this one is right-aligned" (Phase 4A). One `Semantics`
    // label carries speaker + content + source names as a single
    // announcement; `ExcludeSemantics` on the visual subtree stops the
    // `SelectableText`/`Chip`s underneath from being announced a second
    // time (redundantly, and out of this order) on top of it.
    final speaker = isUser ? 'You' : 'Assistant';
    final sourcesLabel =
        sources.isEmpty ? '' : '. Sources: ${sources.map((s) => s.label).join(', ')}';
    // Phase 6B (Hybrid Retrieval Engine, ADR-037): the approved product
    // decision to clearly distinguish a general-knowledge answer from one
    // grounded in the user's own content - announced right after the
    // answer text, before any (necessarily absent, for this case) sources.
    final provenanceLabel = isGeneralKnowledge
        ? '. This answer comes from the AI model\'s general knowledge, not your documents'
        : '';
    return Semantics(
      label: '$speaker said: ${message.content}$provenanceLabel$sourcesLabel',
      child: ExcludeSemantics(
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? scheme.primaryContainer : scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isGeneralKnowledge) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public, size: 14, color: scheme.tertiary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          "From the AI's general knowledge — not your documents",
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.tertiary,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ] else if (isGrounded) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fact_check_outlined, size: 14, color: scheme.primary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Grounded in your meetings and documents',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: scheme.primary,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                isUser
                    ? SelectableText(
                        message.content,
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      )
                    : MarkdownBody(
                        data: message.content,
                        baseStyle: TextStyle(color: scheme.onSurface),
                      ),
                if (!isUser) ...[
                  const SizedBox(height: 4),
                  // V2.2 Production Hardening, Priority 1 (real-device QA
                  // request): a subtle, always-visible disclaimer on every
                  // assistant answer - deliberately separate from the
                  // "Grounded in..."/"From the AI's general knowledge"
                  // badges above (which state *where* an answer came from);
                  // this states something true of *every* answer
                  // regardless of provenance, so it's unconditional rather
                  // than folded into either badge. Small and muted by
                  // design ("subtle but always visible... do not clutter
                  // the interface") - a caption, not another badge.
                  const AiDisclaimer(),
                ],
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: onCopy,
                      tooltip: 'Copy',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_outlined, size: 16),
                    ),
                    PopupMenuButton<_MessageAction>(
                      tooltip: 'More',
                      icon: const Icon(Icons.more_horiz_rounded, size: 16),
                      onSelected: (action) {
                        switch (action) {
                          case _MessageAction.edit:
                            onEdit?.call();
                          case _MessageAction.regenerate:
                            onRegenerate?.call();
                          case _MessageAction.delete:
                            onDelete();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: _MessageAction.edit,
                            child: _MenuRow(icon: Icons.edit_outlined, label: 'Edit'),
                          ),
                        if (onRegenerate != null)
                          const PopupMenuItem(
                            value: _MessageAction.regenerate,
                            child: _MenuRow(icon: Icons.refresh_rounded, label: 'Regenerate'),
                          ),
                        const PopupMenuItem(
                          value: _MessageAction.delete,
                          child: _MenuRow(icon: Icons.delete_outline_rounded, label: 'Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
                if (sources.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sources',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final source in sources) _SourceChip(source: source),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.text,
    this.isPreparingModel = false,
    this.modelPrepProgress,
  });

  final String text;

  /// True while the on-device model is still loading (first use since app
  /// start, or a reload after being idle-unloaded) rather than actually
  /// generating - see `ChatController._prepareModel`'s doc comment. Shown
  /// as a distinct row from the plain typing indicator so a genuinely slow
  /// model load never looks identical to a frozen app.
  final bool isPreparingModel;

  /// 0.0-1.0 during a real model download; null for a from-disk load (no
  /// byte count to report) or whenever [isPreparingModel] is false.
  final double? modelPrepProgress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = isPreparingModel
        ? 'Preparing the on-device AI model'
        : (text.isEmpty ? 'Assistant is thinking' : 'Assistant: $text');
    // `liveRegion: true` (Phase 4A) - TalkBack only announces a node when
    // it first appears or when explicitly told content changed; without
    // this, a token-by-token streaming answer updates silently on screen
    // with no announcement at all until generation finishes. The label is
    // set once per rebuild (not once per token) since Flutter's semantics
    // system already re-announces a live region's label on every value
    // change - true `Semantics` update coalescing, not JS-style debouncing
    // we'd have to build ourselves.
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: _EntranceFade(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
              margin: const EdgeInsets.symmetric(vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: isPreparingModel
                  ? _ModelPreparingRow(progress: modelPrepProgress)
                  : (text.isEmpty
                      ? const _TypingDots()
                      : Text(text, style: TextStyle(color: scheme.onSurface))),
            ),
          ),
        ),
      ),
    );
  }
}

/// The honest "the model is loading, not generating" state - a small spinner
/// (indeterminate, or a real percentage once a download is actually
/// reporting bytes) plus explanatory text, so a genuinely slow first load
/// never reads as an unexplained frozen app. On-device inference itself can
/// still be slow once generation starts (no GPU acceleration, a real
/// hardware characteristic this row makes no claim about) - this row's only
/// job is to not let a model *load* be mistaken for that.
class _ModelPreparingRow extends StatelessWidget {
  const _ModelPreparingRow({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, value: progress),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            progress != null
                ? 'Preparing the on-device model… ${(progress! * 100).round()}%'
                : 'Preparing the on-device model…',
            style: TextStyle(color: scheme.onSurface),
          ),
        ),
      ],
    );
  }
}

/// One icon+label row, shared by every [PopupMenuItem] in a message
/// bubble's overflow menu so Edit/Regenerate/Delete render identically.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// One citation chip under an assistant bubble. Tappable straight to the
/// meeting/document it was drawn from when [ChatSourceRef.meetingId]/
/// [documentId] identifies one (an [ActionChip]); a plain, non-interactive
/// [Chip] for the rare citation with neither (decoded from an old
/// `sources_json` row predating one of those fields).
class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});

  final ChatSourceRef source;

  // V2.2 Production Hardening, Priority 3 (real-device QA finding: "Meeting
  // Transcript: 50% / Transcript: 36%" read as if it were measuring
  // transcript completeness). Traced to source: `ChatSourceRef.confidence`
  // is a per-chunk retrieval-relevance score (how well *this excerpt*
  // matched *this question* - WorkspaceChatUseCase._buildSources, Phase
  // 6B), never a completeness/progress percentage - the underlying number
  // was always correct, but a bare "· 36%" right next to a label that
  // already includes the content type ("... — Transcript") reads exactly
  // like one. Fixed by naming what the number actually is, not by changing
  // it.
  String get _label => source.confidence == null
      ? source.label
      : '${source.label} · ${(source.confidence! * 100).clamp(0, 100).round()}% match';

  @override
  Widget build(BuildContext context) {
    final label = Text(_label, style: Theme.of(context).textTheme.labelSmall);
    const avatar = Icon(Icons.link_rounded, size: 14);
    final meetingId = source.meetingId;
    final documentId = source.documentId;
    if (meetingId != null) {
      return ActionChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: avatar,
        label: label,
        onPressed: () => context.push(RoutePaths.meetingDetailsPath(meetingId)),
      );
    }
    if (documentId != null) {
      return ActionChip(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        avatar: avatar,
        label: label,
        onPressed: () => context.push(RoutePaths.documentDetailsPath(documentId)),
      );
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: avatar,
      label: label,
    );
  }
}

/// A brief fade+rise entrance, applied once per bubble as it first appears
/// (V2.2 Batch 2, Premium Chat Experience) - deliberately short (180ms) so
/// it reads as polish, not a delay: this plays once on insertion, never on
/// rebuild, since each [_MessageBubble]/[_StreamingBubble] is a fresh
/// widget instance per list item.
class _EntranceFade extends StatefulWidget {
  const _EntranceFade({required this.child});

  final Widget child;

  @override
  State<_EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<_EntranceFade> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.04),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// Three softly bouncing dots, replacing the generic spinner+"Thinking…"
/// row while the assistant hasn't streamed its first token yet (V2.2 Batch
/// 2) - the same "someone is typing" language used across chat apps,
/// built from primitives already used elsewhere in this app
/// ([AnimationController] + [SingleTickerProviderStateMixin]) rather than a
/// new package.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One dot's vertical offset at animation progress [t], staggered by
  /// [phaseOffset] (0, 1/3, 2/3 across the three dots) so they bounce in a
  /// travelling wave rather than in lockstep.
  double _bounce(double t, double phaseOffset) {
    final phase = (t + phaseOffset) % 1.0;
    return -6 * math.sin(phase * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Transform.translate(
                offset: Offset(0, _bounce(_controller.value, i / 3)),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: scheme.onErrorContainer, fontSize: 13)),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Shown above the input bar while [ChatController.editAndResend] hasn't
/// been triggered yet (Phase 8B.1, Priority 2) - makes it explicit that
/// pressing Send will replace an earlier message rather than add a new
/// one, and gives an escape hatch (nothing is deleted until Send is
/// actually pressed - see [_ChatScreenState.editAndResend]'s call site).
class _EditingBanner extends StatelessWidget {
  const _EditingBanner({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_outlined, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Editing message',
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: 'Cancel edit',
            visualDensity: VisualDensity.compact,
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.canSend,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
    required this.onCancel,
    required this.scheme,
    required this.attachment,
    required this.isAttaching,
    required this.attachmentError,
    required this.canAttach,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.voiceState,
    required this.voiceError,
    required this.onMicTap,
    required this.onCancelRecording,
  });

  final TextEditingController controller;
  final bool canSend;
  final bool isSending;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final ColorScheme scheme;

  final Document? attachment;
  final bool isAttaching;
  final String? attachmentError;
  final bool canAttach;
  final VoidCallback onAttach;
  final VoidCallback onRemoveAttachment;

  final _VoiceInputState voiceState;
  final String? voiceError;
  final VoidCallback onMicTap;
  final VoidCallback onCancelRecording;

  @override
  Widget build(BuildContext context) {
    final isRecording = voiceState == _VoiceInputState.recording;
    final isTranscribing = voiceState == _VoiceInputState.transcribing;
    final busy = isSending || isRecording || isTranscribing;

    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (attachment != null || isAttaching || attachmentError != null) ...[
            _AttachmentChip(
              attachment: attachment,
              isAttaching: isAttaching,
              error: attachmentError,
              onRemove: onRemoveAttachment,
              onRetry: onAttach,
            ),
            const SizedBox(height: 8),
          ],
          if (voiceError != null) ...[
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: scheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    voiceError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (isRecording || isTranscribing)
            _RecordingRow(
              isTranscribing: isTranscribing,
              onStop: onMicTap,
              onCancel: onCancelRecording,
            )
          else
            Row(
              children: [
                IconButton(
                  key: const Key('chatAttachButton'),
                  icon: const Icon(Icons.attach_file_rounded),
                  tooltip: canAttach
                      ? 'Attach a file to ask about'
                      : 'Start a new chat to attach a different file',
                  visualDensity: VisualDensity.compact,
                  onPressed: !busy && canAttach ? onAttach : null,
                ),
                IconButton(
                  key: const Key('chatMicButton'),
                  icon: const Icon(Icons.mic_none_rounded),
                  tooltip: 'Speak your question',
                  visualDensity: VisualDensity.compact,
                  onPressed: !isSending ? onMicTap : null,
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    enabled: !isSending,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Ask a question…',
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (isSending)
                  IconButton.filledTonal(
                    key: const Key('chatCancelButton'),
                    icon: const Icon(Icons.stop_rounded),
                    tooltip: 'Cancel',
                    onPressed: onCancel,
                  )
                else
                  IconButton.filled(
                    key: const Key('chatSendButton'),
                    icon: const Icon(Icons.arrow_upward_rounded),
                    tooltip: 'Send',
                    onPressed: canSend ? onSend : null,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Shows exactly what's attached (or being attached) before the user sends
/// anything - R-7 §1's "show attached files clearly ... before sending" /
/// "allow removing an attachment before sending".
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.isAttaching,
    required this.error,
    required this.onRemove,
    required this.onRetry,
  });

  final Document? attachment;
  final bool isAttaching;
  final String? error;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (isAttaching) {
      return _chipContainer(
        scheme,
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Processing your file…', style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return _chipContainer(
        scheme,
        color: scheme.errorContainer,
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              visualDensity: VisualDensity.compact,
              tooltip: 'Dismiss',
              onPressed: onRemove,
            ),
          ],
        ),
      );
    }

    final document = attachment;
    if (document == null) return const SizedBox.shrink();
    return _chipContainer(
      scheme,
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              document.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            key: const Key('chatRemoveAttachmentButton'),
            icon: const Icon(Icons.close_rounded, size: 16),
            visualDensity: VisualDensity.compact,
            tooltip: 'Remove attachment',
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }

  Widget _chipContainer(ColorScheme scheme, {required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Replaces the composer's text field while capturing/transcribing a voice
/// question - compact by design (a full waveform belongs to the dedicated
/// meeting `RecordingScreen`, not a chat composer row).
class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.isTranscribing,
    required this.onStop,
    required this.onCancel,
  });

  final bool isTranscribing;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (isTranscribing)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(Icons.fiber_manual_record, size: 18, color: scheme.error),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            isTranscribing ? 'Transcribing…' : 'Recording your question…',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (!isTranscribing) ...[
          TextButton(
            key: const Key('chatCancelRecordingButton'),
            onPressed: onCancel,
            child: const Text('Cancel'),
          ),
          IconButton.filled(
            key: const Key('chatStopRecordingButton'),
            icon: const Icon(Icons.stop_rounded),
            tooltip: 'Stop and use this',
            onPressed: onStop,
          ),
        ],
      ],
    );
  }
}
