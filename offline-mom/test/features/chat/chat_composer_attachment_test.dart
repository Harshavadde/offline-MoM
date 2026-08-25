import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/chat/general_chat_use_case.dart';
import 'package:offline_mom/features/chat/presentation/screens/chat_screen.dart';
import 'package:offline_mom/features/chat/workspace_chat_use_case.dart';
import 'package:offline_mom/features/documents/process_new_document_use_case.dart';
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
import 'package:offline_mom/services/ai/speech_to_text_engine.dart';
import 'package:offline_mom/services/audio/recorder_service.dart';
import 'package:offline_mom/services/documents/document_import_service.dart';
import 'package:offline_mom/services/retrieval/hybrid_retrieval_pipeline.dart';
import 'package:offline_mom/services/retrieval/keyword_search_service.dart';
import 'package:offline_mom/services/retrieval/vector_store.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/fake_ai_engines.dart';
import '../../test_helpers/test_database.dart';

// See chat_screen_test.dart's identical helper for why real-time pumping is
// used instead of `pumpAndSettle()` throughout this file.
Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Stands in for the system file picker - returns a fixed, already-on-disk
/// path (or null, simulating "user cancelled") instead of touching the
/// `file_picker` platform channel, which doesn't exist under `flutter test`.
class _FakeDocumentImportService implements DocumentImportService {
  _FakeDocumentImportService({this.pathToReturn, this.throwOnPrepare});

  final String? pathToReturn;
  final DocumentImportException? throwOnPrepare;

  @override
  Future<String?> pickFile() async => pathToReturn;

  @override
  Future<PreparedDocumentFile> prepareDocumentFile(String pickedFilePath) async {
    if (throwOnPrepare != null) throw throwOnPrepare!;
    return PreparedDocumentFile(
      filePath: pickedFilePath,
      originalFilename: 'job-notes.txt',
      sourceType: DocumentSourceType.txt,
      fileSizeBytes: 42,
    );
  }
}

/// Stands in for the real extract-summarize-index pipeline
/// ([ProcessNewDocumentUseCase]'s real implementation is already covered by
/// its own dedicated tests elsewhere in this suite) - this only needs to
/// prove the chat composer correctly waits for processing and reacts to its
/// outcome, not re-verify the pipeline itself.
class _FakeProcessNewDocumentUseCase implements ProcessNewDocumentUseCase {
  _FakeProcessNewDocumentUseCase(this._documentRepository, {this.succeed = true});

  final DocumentRepository _documentRepository;
  final bool succeed;

  @override
  Future<void> call(int documentId) async {
    final doc = await _documentRepository.getById(documentId);
    if (doc == null) return;
    await _documentRepository.update(
      doc.copyWith(
        status: succeed ? DocumentStatus.ready : DocumentStatus.error,
        extractedText: succeed ? 'Fake extracted text about the job.' : null,
      ),
    );
  }
}

class _FakeRecorderService implements RecorderService {
  _FakeRecorderService({this.hasPermission = true, this.stopReturnsNull = false});

  final bool hasPermission;
  final bool stopReturnsNull;
  String? startedPath;

  @override
  Future<bool> hasMicrophonePermission() async => hasPermission;

  @override
  Future<void> start(String filePath) async => startedPath = filePath;

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<String?> stop() async => stopReturnsNull ? null : startedPath;

  @override
  Stream<RecordingSessionState> get stateStream => const Stream.empty();

  @override
  Stream<RecordingAmplitude> get amplitudeStream => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._docsPath);
  final String _docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => _docsPath;
}

void main() {
  // Mirrors `chat_screen_test.dart`'s exact override set (see that file's
  // own doc comment for why each piece is here) plus the new
  // document-import/recording/speech-to-text pieces R-7 adds.
  Future<List<Override>> buildOverrides(
    Database db, {
    DocumentImportService? documentImportService,
    ProcessNewDocumentUseCase? processNewDocumentUseCase,
    RecorderService? recorderService,
    SpeechToTextEngine? speechToTextEngine,
  }) async {
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
      if (documentImportService != null)
        documentImportServiceProvider.overrideWithValue(documentImportService),
      if (processNewDocumentUseCase != null)
        processNewDocumentUseCaseProvider.overrideWithValue(processNewDocumentUseCase),
      if (recorderService != null) recorderServiceProvider.overrideWithValue(recorderService),
      if (speechToTextEngine != null)
        speechToTextEngineProvider.overrideWithValue(speechToTextEngine),
    ];
  }

  testWidgets('attaching a file shows it as a chip once processed, ready to ask about',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final documentRepository = SqfliteDocumentRepository(db);

      final tempFile = await File(
        '${Directory.systemTemp.path}/chat_attach_test_${DateTime.now().microsecondsSinceEpoch}.txt',
      ).create();
      await tempFile.writeAsString('Some job notes.');
      addTearDown(() => tempFile.delete());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            documentImportService: _FakeDocumentImportService(pathToReturn: tempFile.path),
            processNewDocumentUseCase: _FakeProcessNewDocumentUseCase(documentRepository),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatAttachButton')));
      await settle(tester);

      // Shows up both as the composer's attachment chip and as the
      // now-selected item in `_DocumentPicker`'s dropdown (attaching a
      // ready document switches scope to Document, per `_attachFile`'s doc
      // comment) - both are legitimate, expected occurrences.
      expect(find.text('job notes'), findsWidgets);
      expect(find.byKey(const Key('chatRemoveAttachmentButton')), findsOneWidget);
      // Attaching a ready document switches the (pre-session) scope to
      // Document scope - the same mechanism `_DocumentPicker` already uses,
      // reused rather than duplicated (see chat_screen.dart's `_attachFile`
      // doc comment).
      expect(find.text('Document'), findsWidgets);
    });
  });

  testWidgets('removing an attachment before sending clears it', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final documentRepository = SqfliteDocumentRepository(db);

      final tempFile = await File(
        '${Directory.systemTemp.path}/chat_attach_test_${DateTime.now().microsecondsSinceEpoch}.txt',
      ).create();
      await tempFile.writeAsString('Some job notes.');
      addTearDown(() => tempFile.delete());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            documentImportService: _FakeDocumentImportService(pathToReturn: tempFile.path),
            processNewDocumentUseCase: _FakeProcessNewDocumentUseCase(documentRepository),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatAttachButton')));
      await settle(tester);
      // Shows up both as the composer's attachment chip and as the
      // now-selected item in `_DocumentPicker`'s dropdown (attaching a
      // ready document switches scope to Document, per `_attachFile`'s doc
      // comment) - both are legitimate, expected occurrences.
      expect(find.text('job notes'), findsWidgets);

      await tester.tap(find.byKey(const Key('chatRemoveAttachmentButton')));
      await settle(tester);

      expect(find.text('job notes'), findsNothing);
      expect(find.byKey(const Key('chatRemoveAttachmentButton')), findsNothing);
    });
  });

  testWidgets('an unsupported/unreadable picked file shows the picker\'s own error message',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            documentImportService: _FakeDocumentImportService(
              pathToReturn: '/tmp/whatever.xyz',
              throwOnPrepare: DocumentImportException('Unsupported file type: .xyz'),
            ),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatAttachButton')));
      await settle(tester);

      expect(find.text('Unsupported file type: .xyz'), findsOneWidget);
      expect(find.byKey(const Key('chatRemoveAttachmentButton')), findsNothing);
    });
  });

  testWidgets('a file the pipeline could not process shows a clear, retryable error',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final documentRepository = SqfliteDocumentRepository(db);

      final tempFile = await File(
        '${Directory.systemTemp.path}/chat_attach_test_${DateTime.now().microsecondsSinceEpoch}.txt',
      ).create();
      await tempFile.writeAsString('Some job notes.');
      addTearDown(() => tempFile.delete());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            documentImportService: _FakeDocumentImportService(pathToReturn: tempFile.path),
            processNewDocumentUseCase: _FakeProcessNewDocumentUseCase(documentRepository, succeed: false),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatAttachButton')));
      await settle(tester);

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const Key('chatRemoveAttachmentButton')), findsNothing);
    });
  });

  testWidgets('cancelling the file picker leaves the composer unchanged', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            documentImportService: _FakeDocumentImportService(pathToReturn: null),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatAttachButton')));
      await settle(tester);

      expect(find.text('Processing your file…'), findsNothing);
      expect(find.byKey(const Key('chatRemoveAttachmentButton')), findsNothing);
    });
  });

  testWidgets('tapping the mic starts recording, then transcribes into the text field',
      (tester) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('chat_voice_test_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            recorderService: _FakeRecorderService(),
            speechToTextEngine: FakeSpeechToTextEngine(
              result: const TranscriptionResult(
                language: 'en',
                fullText: 'What does this job pay?',
                segments: [],
              ),
            ),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatMicButton')));
      await settle(tester);
      expect(find.text('Recording your question…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chatStopRecordingButton')));
      await settle(tester);

      expect(find.text('Recording your question…'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'What does this job pay?');
    });
  });

  testWidgets('no audio captured (recorder returns nothing) shows a clear message, no crash',
      (tester) async {
    await tester.runAsync(() async {
      final tempDir = await Directory.systemTemp.createTemp('chat_voice_test_');
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);

      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            recorderService: _FakeRecorderService(stopReturnsNull: true),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatMicButton')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('chatStopRecordingButton')));
      await settle(tester);

      expect(find.textContaining('No audio was captured'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('denied microphone permission shows a clear message, no crash', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(
        ProviderScope(
          overrides: await buildOverrides(
            db,
            recorderService: _FakeRecorderService(hasPermission: false),
          ),
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await settle(tester);

      await tester.tap(find.byKey(const Key('chatMicButton')));
      await settle(tester);

      expect(find.textContaining('microphone access'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
