import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../models/chat_session.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/confirm_dialog.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../../../../shared/widgets/tinted_icon.dart';
import '../providers/chat_providers.dart';

/// Past conversations - reopen ([_resume]), rename, or delete. Mirrors
/// `history_screen.dart`'s list pattern
/// (lib/features/meetings/presentation/screens/history_screen.dart).
class ChatHistoryScreen extends ConsumerWidget {
  const ChatHistoryScreen({super.key});

  IconData _scopeIcon(ChatScope scope) => switch (scope) {
        ChatScope.workspace => Icons.workspaces_outline,
        ChatScope.meeting => Icons.mic_none_rounded,
        ChatScope.document => Icons.description_outlined,
        ChatScope.general => Icons.chat_bubble_outline,
      };

  String _scopeLabel(ChatScope scope) => switch (scope) {
        ChatScope.workspace => 'Workspace',
        ChatScope.meeting => 'Meeting',
        ChatScope.document => 'Document',
        ChatScope.general => 'General',
      };

  Future<void> _rename(BuildContext context, WidgetRef ref, ChatSession session) async {
    final newTitle = await showTextInputDialog(
      context,
      title: 'Rename conversation',
      labelText: 'Title',
      initialValue: session.title,
    );

    if (newTitle == null || newTitle.isEmpty || newTitle == session.title) return;

    await ref.read(chatSessionRepositoryProvider).update(
          session.copyWith(title: newTitle, updatedAt: DateTime.now()),
        );
    ref.invalidate(chatSessionListProvider);
  }

  Future<void> _togglePin(WidgetRef ref, ChatSession session) async {
    await ref.read(chatSessionRepositoryProvider).update(
          session.copyWith(isPinned: !session.isPinned),
        );
    ref.invalidate(chatSessionListProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ChatSession session) async {
    final confirmed = await showDestructiveConfirmDialog(
      context,
      title: 'Delete conversation?',
      message: 'This permanently deletes "${session.title}". This can\'t be undone.',
    );
    if (!confirmed) return;

    await ref.read(deleteChatSessionUseCaseProvider)(session.id!);
    ref.invalidate(chatSessionListProvider);
  }

  void _resume(BuildContext context, ChatSession session) {
    context.push(RoutePaths.chat, extra: ChatLaunchArgs(sessionId: session.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(chatSessionListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat History')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorState(title: 'Couldn\'t load your conversations', error: err),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const EmptyState(
              icon: Icons.history_rounded,
              title: 'No conversations yet',
              message: 'Conversations you start from Chat will show up '
                  'here so you can pick up where you left off.',
            );
          }
          final pinned = sessions.where((s) => s.isPinned).toList();
          final recent = sessions.where((s) => !s.isPinned).toList();

          // Flattened into one row list (header rows interleaved with
          // session rows) and built via ListView.builder rather than a
          // plain ListView(children: [...for loops...]) (Phase 3B) - the
          // previous version constructed every conversation's Card/
          // ListTile/PopupMenuButton up front regardless of scroll
          // position, which doesn't scale as history grows toward NFR-16's
          // "hundreds to low thousands" corpus scale. ListView.builder only
          // builds rows actually scrolled into view.
          final rows = <_Row>[
            if (pinned.isNotEmpty) ...[
              const _HeaderRow('Pinned'),
              for (final session in pinned) _SessionRow(session),
              if (recent.isNotEmpty) const _HeaderRow('Recent'),
            ],
            for (final session in recent) _SessionRow(session),
          ];

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              return switch (row) {
                _HeaderRow(:final label) => Padding(
                    padding: EdgeInsets.fromLTRB(0, index == 0 ? 0 : 16, 0, 8),
                    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
                  ),
                _SessionRow(:final session) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SessionTile(
                      session: session,
                      scopeIcon: _scopeIcon(session.scope),
                      scopeLabel: _scopeLabel(session.scope),
                      onTap: () => _resume(context, session),
                      onTogglePin: () => _togglePin(ref, session),
                      onRename: () => _rename(context, ref, session),
                      onDelete: () => _delete(context, ref, session),
                    ),
                  ),
              };
            },
          );
        },
      ),
    );
  }
}

/// One row in the flattened, lazily-built list `ChatHistoryScreen` renders
/// (Phase 3B) - either a section header or a conversation.
sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.label);
  final String label;
}

class _SessionRow extends _Row {
  const _SessionRow(this.session);
  final ChatSession session;
}

/// One conversation row - extracted so the pinned/recent sections above
/// don't duplicate the card/menu markup (QUALITY: "No duplicate widgets").
class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.scopeIcon,
    required this.scopeLabel,
    required this.onTap,
    required this.onTogglePin,
    required this.onRename,
    required this.onDelete,
  });

  final ChatSession session;
  final IconData scopeIcon;
  final String scopeLabel;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: TintedIcon(scopeIcon),
        title: Text(session.title, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '$scopeLabel · ${DateFormat.yMMMd().add_jm().format(session.updatedAt)}',
        ),
        onTap: onTap,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (session.isPinned)
              Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
            PopupMenuButton<String>(
              onSelected: (action) {
                switch (action) {
                  case 'pin':
                    onTogglePin();
                  case 'rename':
                    onRename();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pin',
                  child: Text(session.isPinned ? 'Unpin' : 'Pin'),
                ),
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
