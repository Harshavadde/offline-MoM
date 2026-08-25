// Tests ScannerController through a ProviderContainer with only the leaf
// providers it reads overridden, mirroring image_compress_controller_test.dart's
// established pattern for this module.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/scanner_providers.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/toolkit_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/scan_image_processing_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _syntheticPhotoBytes({int width = 300, int height = 400}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, (x ^ y) % 256);
    }
  }
  return img.encodeJpg(image, quality: 100);
}

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitImagePickerService pickerService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('scanner_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitImagePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitImagePickerServiceProvider.overrideWithValue(pickerService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  PickedToolkitImage picked({String fileName = 'page.jpg'}) =>
      PickedToolkitImage(fileName: fileName, bytes: _syntheticPhotoBytes());

  test('capturing pages builds up the session in order', () async {
    pickerService.cameraResult = picked();
    final controller = container.read(scannerControllerProvider.notifier);

    await controller.captureFromCamera();
    await controller.captureFromCamera();

    expect(container.read(scannerControllerProvider).pages, hasLength(2));
  });

  test('multi-select gallery import appends every picked image', () async {
    pickerService.multiGalleryResult = [
      picked(fileName: 'a.jpg'),
      picked(fileName: 'b.jpg'),
      picked(fileName: 'c.jpg'),
    ];
    final controller = container.read(scannerControllerProvider.notifier);

    await controller.importMultipleFromGallery();

    expect(container.read(scannerControllerProvider).pages, hasLength(3));
  });

  test('deletePage removes it and undoDeletePage restores it at the same '
      'position', () async {
    pickerService.multiGalleryResult = [picked(fileName: 'a.jpg'), picked(fileName: 'b.jpg')];
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.importMultipleFromGallery();
    final secondPageId = container.read(scannerControllerProvider).pages[1].id;

    controller.deletePage(secondPageId);
    expect(container.read(scannerControllerProvider).pages, hasLength(1));
    expect(container.read(scannerControllerProvider).canUndoDelete, isTrue);

    controller.undoDeletePage();
    final restored = container.read(scannerControllerProvider);
    expect(restored.pages, hasLength(2));
    expect(restored.pages[1].id, secondPageId);
    expect(restored.canUndoDelete, isFalse);
  });

  test('reorderPage moves a page to its new position', () async {
    pickerService.multiGalleryResult = [
      picked(fileName: 'a.jpg'),
      picked(fileName: 'b.jpg'),
      picked(fileName: 'c.jpg'),
    ];
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.importMultipleFromGallery();
    final ids = container.read(scannerControllerProvider).pages.map((p) => p.id).toList();

    controller.reorderPage(0, 2);

    final reordered = container.read(scannerControllerProvider).pages.map((p) => p.id).toList();
    expect(reordered, [ids[1], ids[2], ids[0]]);
  });

  test('rotatePage swaps width/height for a 90-degree rotation', () async {
    pickerService.cameraResult = picked();
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.captureFromCamera();
    final page = container.read(scannerControllerProvider).pages.single;

    await controller.rotatePage(page.id, ScanRotation.clockwise90);

    final rotated = container.read(scannerControllerProvider).pages.single;
    expect(rotated.width, page.height);
    expect(rotated.height, page.width);
  });

  test('generatePdf then save() writes a real PDF file and inserts a '
      'Recent Files row with the correct page count', () async {
    pickerService.multiGalleryResult = [picked(fileName: 'a.jpg'), picked(fileName: 'b.jpg')];
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.importMultipleFromGallery();

    await controller.generatePdf();
    expect(container.read(scannerControllerProvider).generatedPdfBytes, isNotNull);

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.pageCount, 2);
    expect(await File(saved.outputPath).exists(), isTrue);
    final onDisk = await File(saved.outputPath).readAsBytes();
    expect(String.fromCharCodes(onDisk.take(5)), '%PDF-');

    final rows = await container.read(toolkitFileListProvider.future);
    expect(rows, hasLength(1));
  });

  test('any page mutation after generating a PDF invalidates the '
      'generated bytes, so a stale PDF is never saved', () async {
    pickerService.multiGalleryResult = [picked(fileName: 'a.jpg'), picked(fileName: 'b.jpg')];
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.importMultipleFromGallery();
    await controller.generatePdf();
    expect(container.read(scannerControllerProvider).generatedPdfBytes, isNotNull);

    final firstPageId = container.read(scannerControllerProvider).pages.first.id;
    controller.deletePage(firstPageId);

    expect(container.read(scannerControllerProvider).generatedPdfBytes, isNull);
  });

  test('generatePdf() with no pages sets a friendly error, not a crash', () async {
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.generatePdf();

    expect(container.read(scannerControllerProvider).error, isNotNull);
    expect(container.read(scannerControllerProvider).generatedPdfBytes, isNull);
  });

  test('reset() clears the session back to empty', () async {
    pickerService.cameraResult = picked();
    final controller = container.read(scannerControllerProvider.notifier);
    await controller.captureFromCamera();

    controller.reset();

    expect(container.read(scannerControllerProvider).pages, isEmpty);
  });
}
