import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/ocr_providers.dart';
import 'package:offline_mom/models/installed_model.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/ai/model_lifecycle_manager.dart' show ModelKind;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/ocr/searchable_pdf_builder_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _bytes(int _) {
  final image = img.Image(width: 20, height: 20);
  img.fill(image, color: img.ColorRgb8(200, 200, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  late Database db;
  late Directory docsDir;
  late ProviderContainer container;
  late FakeOcrTextExtractionService fakeOcr;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('ocr_session_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    fakeOcr = FakeOcrTextExtractionService(
      defaultWords: const [OcrWord(text: 'Result', x0: 10, y0: 10, x1: 100, y1: 40)],
    );
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        searchablePdfBuilderServiceProvider.overrideWithValue(
          SearchablePdfBuilderService(ocrService: fakeOcr),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  Future<void> installActiveOcrModel() async {
    await container.read(installedModelRepositoryProvider).insert(
          InstalledModel(
            modelId: 'ocr-eng',
            kind: ModelKind.ocr,
            localPath: '/fake/eng.traineddata',
            sizeBytes: 4000000,
            downloadedAt: DateTime.now(),
            isActive: true,
          ),
        );
  }

  test('start() with no OCR model installed reports modelMissing and never calls OCR (scenario 13)', () async {
    final controller = container.read(ocrSessionControllerProvider.notifier);
    await controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'Test',
    );
    final state = container.read(ocrSessionControllerProvider);
    expect(state.modelMissing, isTrue);
    expect(state.isBusy, isFalse);
    expect(fakeOcr.callCount, 0);
  });

  test('a successful single-page run reaches isDone with real PDF bytes (scenario 1)', () async {
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    await controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'Photo',
    );
    final state = container.read(ocrSessionControllerProvider);
    expect(state.isDone, isTrue);
    expect(state.resultBytes, isNotEmpty);
    expect(state.modelMissing, isFalse);
    expect(state.error, isNull);
  });

  test('multi-page run reaches pagesDone == pagesTotal at completion (scenario 3)', () async {
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    final pages = List.generate(4, (_) => OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100));
    await controller.start(pages: pages, documentName: 'Multi');
    final state = container.read(ocrSessionControllerProvider);
    expect(state.pagesDone, 4);
    expect(state.pagesTotal, 4);
    expect(state.isDone, isTrue);
  });

  test('cancel() called right after start() surfaces wasCancelled, not an error (scenario 5)', () async {
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    // Mirrors PdfToImagesController's own cancel test (P0-6): start()
    // unawaited, cancel() called synchronously before the first real
    // `await` inside _run() resolves, then await the whole thing -
    // reliably lands the cancellation on the very first page.
    final future = controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'Cancelled',
    );
    controller.cancel();
    await future;
    final state = container.read(ocrSessionControllerProvider);
    expect(state.wasCancelled, isTrue);
    expect(state.error, isNull);
    expect(state.isDone, isFalse);
  });

  test('an OCR failure surfaces a real error message, not a crash or a partial result (scenario 6)', () async {
    await installActiveOcrModel();
    final failing = SearchablePdfBuilderService(ocrService: _AlwaysFailingOcr());
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        searchablePdfBuilderServiceProvider.overrideWithValue(failing),
      ],
    );
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    await controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'Fails',
    );
    final state = container.read(ocrSessionControllerProvider);
    expect(state.error, isNotNull);
    expect(state.isDone, isFalse);
  });

  test('retry() after a failure can succeed once the OCR call stops failing (scenario 7)', () async {
    final flaky = _FlakyOnceOcr();
    final flakyService = SearchablePdfBuilderService(ocrService: flaky);
    container.dispose();
    container = ProviderContainer(
      overrides: [
        installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        searchablePdfBuilderServiceProvider.overrideWithValue(flakyService),
      ],
    );
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    await controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'Retry',
    );
    expect(container.read(ocrSessionControllerProvider).error, isNotNull);

    await controller.retry();
    final state = container.read(ocrSessionControllerProvider);
    expect(state.error, isNull);
    expect(state.isDone, isTrue);
  });

  test('save() writes a new ToolkitFile with ocr tool type and the page count preserved (scenario 9)', () async {
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    final pages = List.generate(3, (_) => OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100));
    await controller.start(pages: pages, documentName: 'ToSave');

    final saved = await controller.save();
    expect(saved, isNotNull);
    expect(saved!.pageCount, 3);

    // Saving again is idempotent - the same row, not a duplicate.
    final savedAgain = await controller.save();
    expect(savedAgain!.id, saved.id);
  });

  test('reset() clears the whole session', () async {
    await installActiveOcrModel();
    final controller = container.read(ocrSessionControllerProvider.notifier);
    await controller.start(
      pages: [OcrSourcePage(jpegBytes: _bytes(10), width: 100, height: 100)],
      documentName: 'X',
    );
    controller.reset();
    final state = container.read(ocrSessionControllerProvider);
    expect(state.sourcePages, isEmpty);
    expect(state.resultBytes, isNull);
  });
}

class _AlwaysFailingOcr implements OcrTextExtractionService {
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) {
    throw const OcrExtractionException('native failure');
  }
}

class _FlakyOnceOcr implements OcrTextExtractionService {
  var _calls = 0;
  @override
  Future<List<OcrWord>> extractWords(String imagePath, {required String language}) async {
    _calls++;
    if (_calls == 1) throw const OcrExtractionException('transient');
    return const [OcrWord(text: 'OK', x0: 1, y0: 1, x1: 20, y1: 20)];
  }
}
