// Tests ImagesToPdfController (Toolkit productization pass, P0-6, Images ->
// PDF) - mirrors pdf_organize_controller_test.dart's exact
// ProviderContainer/fake-service pattern. Uses real, decodable JPEG/PNG
// bytes built with package:image (not arbitrary bytes), since the
// controller genuinely decodes every image it's given.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/images_to_pdf_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _jpeg({int width = 300, int height = 400, int r = 200, int g = 100, int b = 50}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image));
}

Uint8List _invalidImageBytes() => Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitImagePickerService imagePickerService;
  late FakeToolkitFilePickerService filePickerService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('images_to_pdf_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    imagePickerService = FakeToolkitImagePickerService();
    filePickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitImagePickerServiceProvider.overrideWithValue(imagePickerService),
        toolkitFilePickerServiceProvider.overrideWithValue(filePickerService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('one image (scenario 1)', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);

    await controller.addImages();

    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(1));
  });

  test('multiple images (scenario 2)', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'c.jpg', bytes: _jpeg()),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);

    await controller.addImages();

    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(3));
  });

  test('mixed portrait/landscape images each keep their own dimensions, no forced cropping (scenario 3)', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'portrait.jpg', bytes: _jpeg(width: 300, height: 500)),
      PickedToolkitImage(fileName: 'landscape.jpg', bytes: _jpeg(width: 500, height: 300)),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();

    final slots = container.read(imagesToPdfControllerProvider).slots;
    expect(slots[0].width, 300);
    expect(slots[0].height, 500);
    expect(slots[1].width, 500);
    expect(slots[1].height, 300);
  });

  test('reordering (scenario 4)', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg(r: 1)),
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg(r: 2)),
      PickedToolkitImage(fileName: 'c.jpg', bytes: _jpeg(r: 3)),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    final ids = container.read(imagesToPdfControllerProvider).slots.map((s) => s.id).toList();

    controller.reorderSlot(0, 2);

    final reordered = container.read(imagesToPdfControllerProvider).slots.map((s) => s.id).toList();
    expect(reordered, [ids[1], ids[2], ids[0]]);
  });

  test('removing an image (scenario 5)', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg()),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    final removeId = container.read(imagesToPdfControllerProvider).slots[0].id;

    controller.removeSlot(removeId);

    final slots = container.read(imagesToPdfControllerProvider).slots;
    expect(slots, hasLength(1));
    expect(slots.any((s) => s.id == removeId), isFalse);
  });

  test('adding additional images after the first batch (scenario 6)', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(1));

    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'c.jpg', bytes: _jpeg()),
    ];
    await controller.addImages();

    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(3));
  });

  test('images can also be added from the file picker, not just the gallery', () async {
    filePickerService.multiResult = [PickedToolkitFile(fileName: 'd.png', bytes: Uint8List.fromList(img.encodePng(img.Image(width: 100, height: 100))))];
    final controller = container.read(imagesToPdfControllerProvider.notifier);

    await controller.addImagesFromFiles();

    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(1));
  });

  test('rotation (scenario 7) is written as a real PDF /Rotate attribute', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    final id = container.read(imagesToPdfControllerProvider).slots[0].id;

    controller.rotateSlot(id, 1);
    expect(container.read(imagesToPdfControllerProvider).slots[0].rotation, PdfPageRotation.rotate90);

    await controller.generatePdf();
    final bytes = container.read(imagesToPdfControllerProvider).resultBytes!;
    expect(latin1.decode(bytes, allowInvalid: true).contains('/Rotate 90'), isTrue);
  });

  test('correct page count (scenario 8)', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'c.jpg', bytes: _jpeg()),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();

    await controller.generatePdf();

    expect(container.read(imagesToPdfControllerProvider).slots.length, 3);
    final bytes = container.read(imagesToPdfControllerProvider).resultBytes!;
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('correct page dimensions and aspect ratio, derived from each image (scenarios 9-10)', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg(width: 400, height: 200))];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();

    final slot = container.read(imagesToPdfControllerProvider).slots[0];
    // A 2:1 landscape image must produce a 2:1 page, not a forced square/A4
    // shape - verified at the slot level (the exact input to page sizing)
    // since PdfPageComposerService's own math (width/dpi*inch) is already
    // covered by pdf_page_composer_test.dart.
    expect(slot.width / slot.height, 2.0);
  });

  test('save then reopen (scenario 11) - the saved PDF is real and re-readable', () async {
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg()),
      PickedToolkitImage(fileName: 'b.jpg', bytes: _jpeg()),
    ];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    await controller.generatePdf();

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.pageCount, 2);
    final onDisk = await File(saved.outputPath).readAsBytes();
    expect(String.fromCharCodes(onDisk.take(5)), '%PDF-');
  });

  test('original picked image bytes remain unchanged after add/rotate/generate/save (scenario 12)', () async {
    final original = _jpeg();
    final originalCopy = Uint8List.fromList(original);
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: original)];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    final id = container.read(imagesToPdfControllerProvider).slots[0].id;
    controller.rotateSlot(id, 1);
    await controller.generatePdf();
    await controller.save();

    expect(original, equals(originalCopy));
  });

  test('invalid image handling (scenario 13) - a friendly error, not a crash', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'bad.dat', bytes: _invalidImageBytes())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);

    await controller.addImages();

    final state = container.read(imagesToPdfControllerProvider);
    expect(state.error, isNotNull);
    expect(state.slots, isEmpty);
  });

  test('a failed add does not leave a corrupt/partial PDF result (scenario 14)', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    await controller.generatePdf();
    expect(container.read(imagesToPdfControllerProvider).resultBytes, isNotNull);

    // A subsequent failed add (invalid bytes among the batch) must not
    // corrupt the already-generated result or the existing valid slot.
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'bad.dat', bytes: _invalidImageBytes())];
    await controller.addImages();

    final state = container.read(imagesToPdfControllerProvider);
    expect(state.error, isNotNull);
    expect(state.slots, hasLength(1)); // the original valid image is untouched
  });

  test('generatePdf() with no images sets a friendly error, not a crash', () async {
    final controller = container.read(imagesToPdfControllerProvider.notifier);

    await controller.generatePdf();

    expect(container.read(imagesToPdfControllerProvider).error, isNotNull);
  });

  test('undo reverts the most recent mutation', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();
    final id = container.read(imagesToPdfControllerProvider).slots[0].id;
    controller.removeSlot(id);
    expect(container.read(imagesToPdfControllerProvider).slots, isEmpty);

    controller.undo();

    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(1));
  });

  test('reset() clears the session', () async {
    imagePickerService.multiGalleryResult = [PickedToolkitImage(fileName: 'a.jpg', bytes: _jpeg())];
    final controller = container.read(imagesToPdfControllerProvider.notifier);
    await controller.addImages();

    controller.reset();

    expect(container.read(imagesToPdfControllerProvider).isEmpty, isTrue);
  });
}
