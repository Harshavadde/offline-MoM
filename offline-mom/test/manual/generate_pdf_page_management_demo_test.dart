// Manual verification script (Toolkit productization pass, P0-5, Page
// Management/ADR-043) - NOT part of the regular regression suite. Drives
// PdfOrganizeController through a realistic combined sequence (rotate,
// delete, duplicate, insert an image, replace a page, reorder, then Apply
// Changes) against a synthetic multi-page document with genuinely
// distinguishable per-page content (page-number labels + alternating
// colored blocks standing in for images/mixed content), and writes both
// the BEFORE (unmodified) and AFTER (all operations applied) documents as
// real, independently-openable PDFs for visual comparison. Also produces a
// separate Extract output.
//
// Run with: flutter test test/manual/generate_pdf_page_management_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/core/utils/toolkit_paths.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_organize_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
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

/// A fake [PdfPageRenderingService] producing a genuinely multi-page,
/// mixed-content-looking document - each page has a large "PAGE N" label
/// (so reordering/deletion/duplication are visually obvious in the output)
/// plus, on every other page, a colored block standing in for an embedded
/// image (mixed content). Distinct from `TextImagePdfPageRenderingService`
/// (test_helpers/, P0-4's single fixed page) since this demo specifically
/// needs *multiple*, visually distinguishable pages.
class _LabeledMultiPagePdfPageRenderingService implements PdfPageRenderingService {
  _LabeledMultiPagePdfPageRenderingService({required this.pageCount});
  final int pageCount;
  final int pageWidth = 500;
  final int pageHeight = 650;

  @override
  Stream<RasterizedPdfPage> rasterizePages(
    Uint8List pdfBytes, {
    List<int>? pageIndices,
    double dpi = kPdfOutputDpi,
    int jpegQuality = 90,
    bool cropToContent = false,
  }) async* {
    final indices = pageIndices ?? List.generate(pageCount, (i) => i);
    for (final index in indices) {
      final image = img.Image(width: pageWidth, height: pageHeight);
      img.fill(image, color: img.ColorRgb8(250, 250, 250));
      img.drawString(image, 'PAGE ${index + 1}', font: img.arial48, x: 40, y: 40, color: img.ColorRgb8(20, 20, 20));
      if (index.isEven) {
        img.fillRect(image, x1: 60, y1: 200, x2: pageWidth - 60, y2: 400, color: img.ColorRgb8(60, 130, 220));
        img.drawString(image, 'embedded image', font: img.arial24, x: 90, y: 280, color: img.ColorRgb8(255, 255, 255));
      } else {
        img.drawString(
          image,
          'Lorem ipsum body text for page ${index + 1}.',
          font: img.arial14,
          x: 40,
          y: 200,
          color: img.ColorRgb8(60, 60, 60),
        );
      }
      final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
      final tempPath = await newToolkitTempFilePath('jpg');
      await File(tempPath).writeAsBytes(jpegBytes);
      yield RasterizedPdfPage(tempFilePath: tempPath, width: pageWidth, height: pageHeight, pageIndex: index);
    }
  }
}

Uint8List _labeledImageBytes(String label, {int r = 200, int g = 40, int b = 40}) {
  final image = img.Image(width: 140, height: 90);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  img.drawString(image, label, font: img.arial14, x: 10, y: 35, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drives PdfOrganizeController through rotate/delete/duplicate/insert/replace/reorder '
      'and writes real before/after/extract PDFs for visual inspection', () async {
    final db = await openTestDatabase();
    final docsDir = await Directory.systemTemp.createTemp('pdf_page_management_demo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      await db.close();
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final pickerService = FakeToolkitFilePickerService()
      ..pdfResult = PickedToolkitFile(fileName: 'demo-source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final imagePickerService = FakeToolkitImagePickerService();
    final renderingService = _LabeledMultiPagePdfPageRenderingService(pageCount: 6);
    final container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        toolkitImagePickerServiceProvider.overrideWithValue(imagePickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(renderingService),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(pdfOrganizeControllerProvider.notifier);
    await controller.pickPdf();
    var state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots, hasLength(6));

    // BEFORE - the original 6 pages, untouched, for visual comparison.
    await controller.applyChanges();
    final before = container.read(pdfOrganizeControllerProvider).resultBytes!;
    controller.discardResult();

    // 1. Rotate page 2 (index 1) 90 degrees.
    controller.rotateSelected(1, ids: [state.slots[1].id]);

    // 2. Delete page 6 (index 5, the last original page).
    state = container.read(pdfOrganizeControllerProvider);
    controller.deleteSelected(ids: [state.slots.last.id]);

    // 3. Duplicate page 1 (index 0) - copy should land right after it.
    state = container.read(pdfOrganizeControllerProvider);
    controller.duplicateSelected(ids: [state.slots[0].id]);

    // 4. Insert an image at the end.
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'insert.png', bytes: _labeledImageBytes('INSERTED', r: 200, g: 40, b: 40));
    final insertOk = await controller.insertImage(position: InsertPosition.atEnd);
    expect(insertOk, isTrue);

    // 5. Replace page 4's original content (now shifted by the duplicate
    // inserted at index 1-2) - select it explicitly by its current label
    // rather than a hardcoded index, since duplication/insert already
    // shifted positions.
    state = container.read(pdfOrganizeControllerProvider);
    final page4Slot = state.slots.firstWhere((s) => s.originalPageNumber == 4);
    controller.clearSelection();
    controller.toggleSelect(page4Slot.id);
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'replacement.png', bytes: _labeledImageBytes('REPLACED', r: 40, g: 160, b: 60));
    final replaceOk = await controller.replaceSelectedWithImage();
    expect(replaceOk, isTrue);

    // 6. Reorder - move the first slot to the end.
    state = container.read(pdfOrganizeControllerProvider);
    controller.reorderSlot(0, state.slots.length - 1);

    // Apply everything.
    await controller.applyChanges();
    final after = container.read(pdfOrganizeControllerProvider);
    expect(after.resultBytes, isNotNull);
    expect(String.fromCharCodes(after.resultBytes!.take(5)), '%PDF-');
    // Started at 6, -1 delete, +1 duplicate, +1 insert = 7.
    expect(after.resultPageCount, 7);

    // EXTRACT - select two pages from the current working order and
    // produce a separate output containing only those, demonstrating
    // Extract is non-destructive to the working session.
    controller.clearSelection();
    final workingSlots = container.read(pdfOrganizeControllerProvider).slots;
    controller.toggleSelect(workingSlots[0].id);
    controller.toggleSelect(workingSlots[2].id);
    await controller.extractSelected();
    final extracted = container.read(pdfOrganizeControllerProvider).resultBytes!;

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final beforeFile = File('${outDir.path}/pdf_page_management_demo_before.pdf');
    final afterFile = File('${outDir.path}/pdf_page_management_demo_after.pdf');
    final extractFile = File('${outDir.path}/pdf_page_management_demo_extract.pdf');
    await beforeFile.writeAsBytes(before);
    await afterFile.writeAsBytes(after.resultBytes!);
    await extractFile.writeAsBytes(extracted);
    // ignore: avoid_print
    print('OK   wrote ${beforeFile.path} (${before.length} bytes)');
    // ignore: avoid_print
    print('OK   wrote ${afterFile.path} (${after.resultBytes!.length} bytes)');
    // ignore: avoid_print
    print('OK   wrote ${extractFile.path} (${extracted.length} bytes)');
  });
}
