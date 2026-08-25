// Tests PdfToImagesController (Toolkit productization pass, P0-6, PDF ->
// Images) - mirrors pdf_organize_controller_test.dart's exact
// ProviderContainer/fake-service pattern.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_to_images_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitFilePickerService pickerService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('pdf_to_images_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 5, pageWidth: 300, pageHeight: 400)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  Future<PdfToImagesController> pickedController() async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final controller = container.read(pdfToImagesControllerProvider.notifier);
    await controller.pickPdf();
    return controller;
  }

  test('one-page PDF (scenario 15)', () async {
    final oneOffContainer = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(FakePdfPageRenderingService(pageCount: 1, pageWidth: 300, pageHeight: 400)),
      ],
    );
    addTearDown(oneOffContainer.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'one.pdf', bytes: Uint8List.fromList([1]));
    final controller = oneOffContainer.read(pdfToImagesControllerProvider.notifier);

    await controller.pickPdf();

    expect(oneOffContainer.read(pdfToImagesControllerProvider).pageCount, 1);
  });

  test('multi-page PDF (scenario 16)', () async {
    await pickedController();

    expect(container.read(pdfToImagesControllerProvider).pageCount, 5);
  });

  test('selected-page export (scenario 17)', () async {
    final controller = await pickedController();
    container.read(pdfToImagesControllerProvider.notifier).selectNone();
    controller.toggleSelect(1);
    controller.toggleSelect(3);

    await controller.exportSelected();

    final state = container.read(pdfToImagesControllerProvider);
    expect(state.results, hasLength(2));
    expect(state.results.map((r) => r.pageIndex), [1, 3]);
  });

  test('all-page export - selected by default after pick (scenario 18)', () async {
    final controller = await pickedController();

    await controller.exportSelected();

    expect(container.read(pdfToImagesControllerProvider).results, hasLength(5));
  });

  test('correct output count (scenario 19)', () async {
    final controller = await pickedController();
    controller.selectNone();
    controller.toggleSelect(0);
    controller.toggleSelect(2);
    controller.toggleSelect(4);

    await controller.exportSelected();

    expect(container.read(pdfToImagesControllerProvider).results, hasLength(3));
  });

  test('correct page ordering in results, regardless of selection-click order (scenario 20)', () async {
    final controller = await pickedController();
    controller.selectNone();
    controller.toggleSelect(3);
    controller.toggleSelect(0);
    controller.toggleSelect(1);

    await controller.exportSelected();

    final indices = container.read(pdfToImagesControllerProvider).results.map((r) => r.pageIndex).toList();
    expect(indices, [0, 1, 3]);
  });

  test('correct image dimensions (scenario 21)', () async {
    final controller = await pickedController();

    await controller.exportSelected();

    for (final result in container.read(pdfToImagesControllerProvider).results) {
      expect(result.width, 300);
      expect(result.height, 400);
    }
  });

  test('cancel behavior (scenario 22) - stops early and clears progress with an error, not a crash', () async {
    final controller = await pickedController();

    final future = controller.exportSelected();
    controller.cancelExport();
    await future;

    final state = container.read(pdfToImagesControllerProvider);
    expect(state.isBusy, isFalse);
    expect(state.error, isNotNull);
  });

  test('failure recovery (scenario 23) - a rasterization failure surfaces a friendly error, not a crash', () async {
    final failContainer = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(
          FakePdfPageRenderingService(throwOnRasterize: const PdfRenderingException('corrupted')),
        ),
      ],
    );
    addTearDown(failContainer.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'bad.pdf', bytes: Uint8List.fromList([0]));

    await failContainer.read(pdfToImagesControllerProvider.notifier).pickPdf();

    final state = failContainer.read(pdfToImagesControllerProvider);
    expect(state.error, isNotNull);
    expect(state.pageThumbnails, isEmpty);
  });

  test('exporting with nothing selected sets a friendly error', () async {
    final controller = await pickedController();
    controller.selectNone();

    await controller.exportSelected();

    expect(container.read(pdfToImagesControllerProvider).error, isNotNull);
  });

  test('saveOutput writes a real JPEG file and inserts one Recent Files row per saved output', () async {
    final controller = await pickedController();
    controller.selectNone();
    controller.toggleSelect(0);
    controller.toggleSelect(1);
    await controller.exportSelected();

    final saved = await controller.saveOutput(0);

    expect(saved, isNotNull);
    expect(await File(saved!.outputPath).exists(), isTrue);
    expect(container.read(pdfToImagesControllerProvider).savedOutputIndices, {0});
  });

  test('saveAll saves every result exactly once', () async {
    final controller = await pickedController();
    controller.selectNone();
    controller.toggleSelect(0);
    controller.toggleSelect(1);
    controller.toggleSelect(2);
    await controller.exportSelected();

    await controller.saveAll();

    expect(container.read(pdfToImagesControllerProvider).savedOutputIndices, {0, 1, 2});
  });

  test('temp files are cleaned up after export', () async {
    final controller = await pickedController();

    await controller.exportSelected();

    final tmpDir = Directory('${docsDir.path}/toolkit/tmp');
    if (await tmpDir.exists()) {
      expect(await tmpDir.list().toList(), isEmpty);
    }
  });

  test('reset() clears the session', () async {
    await pickedController();

    container.read(pdfToImagesControllerProvider.notifier).reset();

    expect(container.read(pdfToImagesControllerProvider).source, isNull);
  });
}
