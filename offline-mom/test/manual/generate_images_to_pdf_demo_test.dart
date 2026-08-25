// Manual verification script (Toolkit productization pass, P0-6, Images ->
// PDF) - NOT part of the regular regression suite. Drives
// ImagesToPdfController through a real sequence (3 portrait images, 2
// landscape images, mixed order, one rotated) and writes a real PDF for
// visual inspection - the P0-6 spec's own "generate real files and inspect
// them" requirement for Images -> PDF.
//
// Run with: flutter test test/manual/generate_images_to_pdf_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/images_to_pdf_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../test_helpers/test_database.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _photo(String label, {required int width, required int height, required int r, required int g, required int b}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  img.drawString(image, label, font: img.arial24, x: 20, y: 20, color: img.ColorRgb8(255, 255, 255));
  img.drawString(image, '${width}x$height', font: img.arial14, x: 20, y: height - 40, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('combines 3 portrait + 2 landscape photos (mixed order, one rotated) into a real PDF', () async {
    final db = await openTestDatabase();
    final docsDir = await Directory.systemTemp.createTemp('images_to_pdf_demo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      await db.close();
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final imagePickerService = FakeToolkitImagePickerService();
    final container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitImagePickerServiceProvider.overrideWithValue(imagePickerService),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(imagesToPdfControllerProvider.notifier);

    // Mixed order on purpose: landscape, portrait, portrait, landscape, portrait.
    imagePickerService.multiGalleryResult = [
      PickedToolkitImage(fileName: 'landscape1.jpg', bytes: _photo('LANDSCAPE 1', width: 800, height: 500, r: 60, g: 130, b: 220)),
      PickedToolkitImage(fileName: 'portrait1.jpg', bytes: _photo('PORTRAIT 1', width: 500, height: 800, r: 220, g: 90, b: 60)),
      PickedToolkitImage(fileName: 'portrait2.jpg', bytes: _photo('PORTRAIT 2', width: 500, height: 800, r: 90, g: 200, b: 90)),
      PickedToolkitImage(fileName: 'landscape2.jpg', bytes: _photo('LANDSCAPE 2', width: 800, height: 500, r: 200, g: 180, b: 40)),
      PickedToolkitImage(fileName: 'portrait3.jpg', bytes: _photo('PORTRAIT 3', width: 500, height: 800, r: 160, g: 60, b: 200)),
    ];
    await controller.addImages();
    expect(container.read(imagesToPdfControllerProvider).slots, hasLength(5));

    // Rotate the second image (portrait1) 90 degrees.
    final targetId = container.read(imagesToPdfControllerProvider).slots[1].id;
    controller.rotateSlot(targetId, 1);

    await controller.generatePdf();
    final bytes = container.read(imagesToPdfControllerProvider).resultBytes!;
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/images_to_pdf_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes)');
  });
}
