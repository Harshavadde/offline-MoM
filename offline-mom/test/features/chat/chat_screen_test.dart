import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/chat/general_chat_use_case.dart';
import 'package:offline_mom/features/chat/presentation/providers/chat_providers.dart';
import 'package:offline_mom/features/chat/presentation/screens/chat_screen.dart';
import 'package:offline_mom/features/chat/workspace_chat_use_case.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/chat_message_repository.dart';
import 'package:offline_mom/repositories/chat_session_repository.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/repositories/knowledge_chunk_repository.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart' show ModelKind;
import 'package:offline_mom/services/retrieval/hybrid_retrieval_pipeline.dart';
import 'package:offline_mom/services/retrieval/keyword_search_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:offline_mom/shared/widgets/ai_disclaimer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

// See chat_history_screen_test.dart's identical doc comment for why every
// real-I/O step here runs inside `tester.runAsync()` and `pumpAndSettle()`
// is avoided in favor of a bounded real-time pump loop - both mirror
// test/widget_test.dart's own established `settle()` pattern exactly.
Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // V2.2 Production Hardening, Priority 1: `ChatScreen` now checks
  // `installedModelsControllerProvider` before rendering its normal UI at
  // all (see chat_screen.dart's own doc comment on that check) - every
  // test in this file exercises the normal chat UI, i.e. simulates a
  // device that already has a Chat LLM installed, so this seeds exactly
  // one installed `ModelKind.llm` row via the same real, in-memory-DB
  // -backed repository pattern every other override in this file already
  // uses (not a fake), and overrides `installedModelRepositoryProvider`
  // with it - without this, the provider would fall through to its
  // production default (a real on-device database path unavailable under
  // `flutter test`).
  Future<List<Override>> buildOverrides(Database db) async {
    final meetingRepository = SqfliteMeetingRepository(db);
    final documentRepository = SqfliteDocumentRepository(db);
    final chatSessionRepository = SqfliteChatSessionRepository(db);
    final chatMessageRepository = SqfliteChatMessageRepository(db);
    final knowledgeChunkRepository = SqfliteKnowledgeChunkRepository(db);
    final installedModelRepository = SqfliteInstalledModelRepository(db);
    final embeddingEngine = FakeEmbeddingEngine();
    final vectorStore = BruteForceVectorStore(knowledgeChunkRepository: knowledgeChunkRepository);
    final hybridRetrievalPipeline = HybridRetrievalPipeline(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
      keywordSearchService: SqfliteKeywordSearchService(db),
    );
    final queue = DefaultLlmRequestQueue();
    final llmEngine = FakeLlmEngine(answer: 'A generated answer.');

    await installedModelRepository.insert(
      InstalledModel(
        modelId: 'llm-qwen2.5-1.5b-instruct-q4km',
        kind: ModelKind.llm,
        localPath: '/fake/qwen.gguf',
        sizeBytes: 1100 * 1024 * 1024,
        downloadedAt: DateTime(2026, 1, 1),
        isActive: true,
      ),
    );

    return [
      meetingRepositoryProvider.overrideWithValue(meetingRepository),
      documentRepositoryProvider.overrideWithValue(documentRepository),
      chatSessionRepositoryProvider.overrideWithValue(chatSessionRepository),
      chatMessageRepositoryProvider.overrideWithValue(chatMessageRepository),
      installedModelRepositoryProvider.overrideWithValue(installedModelRepository),
      llmRequestQueueProvider.overrideWithValue(queue),
      // `ChatController._prepareModel()` reads this directly before every
      // send - must be overridden or the widget test would construct a
      // real `LlamaDartLlmEngine` and attempt genuine native model loading.
      llmEngineProvider.overrideWithValue(llmEngine),
      workspaceChatUseCaseProvider.overrideWithValue(
        WorkspaceChatUseCase(
          chatSessionRepository: chatSessionRepository,
          chatMessageRepository: chatMessageRepository,
          hybridRetrievalPipeline: hybridRetrievalPipeline,
          meetingRepository: meetingRepository,
          documentRepository: documentRepository,
          llmEngine: llmEngine,
          llmRequestQueue: queue,
        ),
      ),
      generalChatUseCaseProvider.overrideWithValue(
        GeneralChatUseCase(
          chatSessionRepository: chatSessionRepository,
          chatMessageRepository: chatMessageRepository,
          llmEngine: llmEngine,
          llmRequestQueue: queue,
        ),
      ),
    ];
  }

  testWidgets('shows the empty state for a fresh workspace-scoped chat',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      expect(find.text('Ask anything'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
    });
  });

  testWidgets('sending a question with nothing indexed answers from general '
      'knowledge, labeled distinctly (Phase 6B, ADR-037)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'anything at all');
      // A rebuild is needed here: the TextField's onChanged callback is
      // what flips the send button's onPressed from null to non-null
      // (`_canSend` reads the controller's live text at build time) -
      // tapping immediately after enterText without an intervening pump
      // would hit a still-disabled (stale) button.
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await settle(tester);

      // find.text() alone would also match the AppBar title - the
      // conversation's auto-generated title is derived from this same
      // first message text (ChatController._titleFrom) - so this looks
      // specifically for the message bubble's SelectableText instead.
      expect(find.widgetWithText(SelectableText, 'anything at all'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'A generated answer.'), findsOneWidget);
      expect(find.textContaining("general knowledge"), findsOneWidget);
      // R-7 §5/§9: every assistant answer carries the shared AiDisclaimer
      // widget (previously inlined text, now the same reusable widget the
      // resume-suggestion review screen uses).
      expect(find.byType(AiDisclaimer), findsOneWidget);
    });
  });

  testWidgets(
      'message bubbles expose a speaker label for TalkBack, since role is '
      'otherwise conveyed only by bubble alignment/color (Phase 4A)',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'anything at all');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await settle(tester);

      expect(find.bySemanticsLabel('You said: anything at all'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'^Assistant said:.*general knowledge')),
        findsOneWidget,
      );
    });

    semantics.dispose();
  });

  testWidgets(
      'once a document-scoped conversation is active, the document\'s '
      'title stays visible in the AppBar (Phase 8B.3, Priority 5: never '
      'leave the user wondering which document they\'re chatting with) - '
      'the scope-picker itself disappears once a session starts, so this '
      'is the only remaining indicator', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final documentRepository = SqfliteDocumentRepository(db);
      final now = DateTime(2026, 1, 1);
      final documentId = await documentRepository.insert(
        Document(
          id: null,
          title: 'Quarterly Report',
          originalFilename: 'Quarterly Report.pdf',
          sourceType: DocumentSourceType.pdf,
          mimeType: 'application/pdf',
          fileSizeBytes: 4096,
          filePath: '/tmp/doc.pdf',
          status: DocumentStatus.ready,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: MaterialApp(
            home: ChatScreen(
              launchArgs: ChatLaunchArgs(scope: ChatScope.document, documentId: documentId),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'summarize this');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await settle(tester);

      expect(find.text('Quarterly Report'), findsOneWidget);
    });
  });

  testWidgets('send button is disabled while the input is empty', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      final button = tester.widget<IconButton>(find.byKey(const Key('chatSendButton')));
      expect(button.onPressed, isNull);
    });
  });

  testWidgets(
      'shows a friendly "no AI model installed" state instead of the normal '
      'chat UI when no Chat LLM is installed (V2.2 Production Hardening, '
      'Priority 1) - and never shows it once one is installed (every other '
      'test in this file)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      // Deliberately does NOT call the shared buildOverrides() (which
      // seeds an installed LLM) - overrides only what's needed to reach
      // ChatScreen.build() without the real on-device database path.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
          ],
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      expect(find.text('No AI model is installed yet'), findsOneWidget);
      expect(find.text('Get Recommended Models'), findsOneWidget);
      // The normal chat UI (scope selector, input bar) must not appear
      // alongside it.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Ask anything'), findsNothing);
    });
  });

  testWidgets(
      'deleting a message uses the shared destructive-confirm dialog and '
      'only deletes after the user actually confirms (V2.2 Batch 2, Premium '
      'Chat Experience: replaced a bespoke AlertDialog with '
      'showDestructiveConfirmDialog, and the four always-visible action '
      'icons with Copy + an overflow menu)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'anything at all');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await settle(tester);

      expect(find.widgetWithText(SelectableText, 'anything at all'), findsOneWidget);

      // Open the user message's overflow menu and choose Delete.
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // The shared destructive-confirm dialog appears; Cancel leaves the
      // message untouched.
      expect(find.text('Delete this message?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, 'anything at all'), findsOneWidget);

      // Confirming actually deletes it.
      await tester.tap(find.byIcon(Icons.more_horiz_rounded).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this message?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.widgetWithText(SelectableText, 'anything at all'), findsNothing);
    });
  });

  testWidgets('General scope is selectable, shows scope-appropriate copy, and answers with no citations',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(db),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      expect(find.text('General'), findsOneWidget);
      await tester.tap(find.text('General'));
      await settle(tester);

      // Scope-appropriate empty-state copy - never claims answers are
      // "grounded" in recorded/imported content, since General never
      // retrieves anything.
      expect(find.textContaining('general knowledge, not your content'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Explain something to me');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatSendButton')));
      await settle(tester);

      expect(find.widgetWithText(SelectableText, 'Explain something to me'), findsOneWidget);
      expect(find.widgetWithText(SelectableText, 'A generated answer.'), findsOneWidget);
      // No "Sources" chips - a general-knowledge answer never cites.
      expect(find.text('Sources'), findsNothing);
    });
  });
}
