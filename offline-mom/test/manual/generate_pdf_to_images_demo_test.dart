// Manual verification script (Toolkit productization pass, P0-6, PDF ->
// Images) - NOT part of the regular regression suite. Drives
// PdfToImagesController against a real 5-page mixed-content PDF, exports
// all pages and then a selected subset, and writes the resulting JPEG
// images to disk for visual inspection.
//
// Run with: flutter test test/manual/generate_pdf_to_images_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/core/utils/toolkit_paths.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_to_images_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
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

/// A 5-page, visually mixed-content fake source PDF - text-labeled pages
/// alternating with colored "image" blocks (mirrors the same fake pattern
/// P0-5's own manual demo used).
class _MixedContentPdfPageRenderingService implements PdfPageRenderingService {
  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    bool cropToContent = false,
  }) async* {
    const width = 500, height = 650;
    final indices = pageIndices ?? List.generate(5, (i) => i);
    for (final index in indices) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(250, 250, 250));
      img.drawString(image, 'PAGE ${index + 1}', font: img.arial48, x: 40, y: 40, color: img.ColorRgb8(20, 20, 20));
      if (index.isEven) {
        img.fillRect(image, x1: 60, y1: 200, x2: width - 60, y2: 400, color: img.ColorRgb8(60, 130, 220));
      } else {
        img.drawString(image, 'Body text for page ${index + 1}.', font: img.arial14, x: 40, y: 200, color: img.ColorRgb8(60, 60, 60));
      }
      final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
      final tempPath = await newToolkitTempFilePath('jpg');
      await File(tempPath).writeAsBytes(jpegBytes);
      yield RasterizedPdfPage(tempFilePath: tempPath, width: width, height: height, pageIndex: index);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports all pages then a selected subset of a real 5-page mixed-content PDF as real JPEG files', () async {
    final db = await openTestDatabase();
    final docsDir = await Directory.systemTemp.createTemp('pdf_to_images_demo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      await db.close();
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final pickerService = FakeToolkitFilePickerService()
      ..pdfResult = PickedToolkitFile(fileName: 'demo-source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(_MixedContentPdfPageRenderingService()),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(pdfToImagesControllerProvider.notifier);
    await controller.pickPdf();
    expect(container.read(pdfToImagesControllerProvider).pageCount, 5);

    // Export ALL pages (default selection).
    await controller.exportSelected();
    final allResults = container.read(pdfToImagesControllerProvider).results;
    expect(allResults, hasLength(5));

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    for (final result in allResults) {
      final file = File('${outDir.path}/pdf_to_images_demo_all_page${result.pageIndex + 1}.jpg');
      await file.writeAsBytes(result.jpegBytes);
      // ignore: avoid_print
      print('OK   wrote ${file.path} (${result.jpegBytes.length} bytes, ${result.width}x${result.height})');
    }

    // Export just pages 2 and 4 (selected subset).
    controller.selectNone();
    controller.toggleSelect(1);
    controller.toggleSelect(3);
    await controller.exportSelected();
    final selectedResults = container.read(pdfToImagesControllerProvider).results;
    expect(selectedResults.map((r) => r.pageIndex), [1, 3]);

    for (final result in selectedResults) {
      final file = File('${outDir.path}/pdf_to_images_demo_selected_page${result.pageIndex + 1}.jpg');
      await file.writeAsBytes(result.jpegBytes);
      // ignore: avoid_print
      print('OK   wrote ${file.path} (${result.jpegBytes.length} bytes)');
    }
  });
}
