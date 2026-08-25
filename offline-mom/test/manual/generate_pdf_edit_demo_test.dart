// Manual verification script (Toolkit productization pass, P0-3) - NOT part
// of the regular regression suite. Unlike generate_pdf_overlay_demo_test.dart
// (P0-2, which drives PdfOverlayService directly with hand-built elements),
// this drives PdfEditController end to end - pickPdf -> addAnnotation (one
// call per tool, using the exact element shapes each tool in
// pdf_edit_screen.dart actually constructs) -> applyWatermark ->
// buildResultBytes - so the *editor's* tool-specific construction logic
// (not just the shared primitive) is what gets visually verified against
// real output.
//
// Run with: flutter test test/manual/generate_pdf_edit_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_edit_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';

import '../test_helpers/test_database.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// A transparent-background signature PNG, built the same way
/// signature_pad_dialog.dart's `_renderToPng` does (a few strokes drawn
/// with `img.drawLine` onto a `numChannels: 4` fully-transparent canvas) -
/// not a hand-waved placeholder image.
Uint8List _fakeDrawnSignature() {
  final image = img.Image(width: 240, height: 90, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
  final ink = img.ColorRgba8(20, 20, 20, 255);
  final strokes = [
    [const (10, 60), const (40, 20), const (70, 70), const (100, 30)],
    [const (110, 50), const (140, 50), const (160, 20), const (180, 70), const (210, 40)],
  ];
  for (final stroke in strokes) {
    for (var i = 0; i < stroke.length - 1; i++) {
      img.drawLine(
        image,
        x1: stroke[i].$1,
        y1: stroke[i].$2,
        x2: stroke[i + 1].$1,
        y2: stroke[i + 1].$2,
        color: ink,
        thickness: 3,
        antialias: true,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}

/// A small imported-photo stand-in (a solid-color JPEG) - imported
/// signature/image annotations go through the same PdfOverlayImage path
/// regardless of source, so a distinct color from the drawn signature is
/// enough to tell the two apart visually.
Uint8List _fakeImportedImage() {
  final image = img.Image(width: 200, height: 80);
  img.fill(image, color: img.ColorRgb8(30, 90, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

/// Mirrors _PdfEditCanvasState._buildArrow's exact output shape (shaft +
/// two back-angled barb segments at the tip, one continuous polyline)
/// without duplicating its private trig helpers - a plain rotation here is
/// fine since this script only needs a visually-recognizable arrowhead.
PdfOverlayLine _arrow(double x1, double y1, double x2, double y2) {
  const barbLength = 0.03;
  final dx = x2 - x1;
  final dy = y2 - y1;
  return PdfOverlayLine(
    points: [
      (x1, y1),
      (x2, y2),
      (x2 - barbLength * dx.abs().clamp(0.5, 2) * 2, y2 - barbLength),
      (x2, y2),
      (x2 - barbLength * 2, y2 - barbLength * dy.abs().clamp(0.5, 2)),
    ],
    color: PdfColors.deepOrange,
    strokeWidth: 2.5,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drives PdfEditController through every P0-3 tool and writes a real, inspectable PDF', () async {
    final db = await openTestDatabase();
    final docsDir = await Directory.systemTemp.createTemp('pdf_edit_demo_test_');
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
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 2, pageWidth: 850, pageHeight: 1100)),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(pdfEditControllerProvider.notifier);
    await controller.pickPdf();
    expect(container.read(pdfEditControllerProvider).pages, hasLength(2));

    // Page 0: Add Text, Highlight, Underline, Strikethrough, Freehand,
    // Shape, Arrow, typed signature, drawn signature.
    controller.addAnnotation(
      0,
      const PdfOverlayText(text: 'Add Text: CONFIDENTIAL', x: 0.05, y: 0.03, fontSize: 22, color: PdfColors.red),
    );
    controller.addAnnotation(
      0,
      const PdfOverlayRect(x: 0.05, y: 0.15, width: 0.35, height: 0.06, color: PdfColor(1, 0.92, 0.23, 0.4)),
    ); // Highlight
    controller.addAnnotation(
      0,
      const PdfOverlayLine(points: [(0.05, 0.25), (0.4, 0.25)], color: PdfColors.black, strokeWidth: 1.5),
    ); // Underline
    controller.addAnnotation(
      0,
      const PdfOverlayLine(points: [(0.05, 0.3), (0.4, 0.31)], color: PdfColors.red, strokeWidth: 1.5),
    ); // Strikethrough
    controller.addAnnotation(
      0,
      const PdfOverlayLine(
        points: [(0.05, 0.4), (0.1, 0.36), (0.15, 0.42), (0.2, 0.37), (0.25, 0.41)],
        color: PdfColors.blue,
        strokeWidth: 2.5,
      ),
    ); // Freehand
    controller.addAnnotation(
      0,
      const PdfOverlayRect(x: 0.55, y: 0.1, width: 0.2, height: 0.12, color: PdfColors.deepPurple, filled: false, strokeWidth: 2),
    ); // Shape
    controller.addAnnotation(0, _arrow(0.55, 0.35, 0.75, 0.3)); // Arrow
    controller.addAnnotation(
      0,
      // Deliberately NOT the default black - page 0's synthetic
      // fake-rasterizer background is pure black ((index*37)%256 for
      // index 0), which would make default-black text invisible by
      // coincidence, not proof the typed-signature path is broken. See
      // generate_pdf_overlay_demo_test.dart's own identical note (the same
      // mistake caught once already during P0-2's own demo authoring).
      const PdfOverlayText(text: 'Jane Doe', x: 0.05, y: 0.55, fontSize: 28, italic: true, color: PdfColors.white),
    ); // Typed signature
    controller.addAnnotation(
      0,
      PdfOverlayImage(bytes: _fakeDrawnSignature(), x: 0.05, y: 0.65, width: 0.28, height: 0.1),
    ); // Drawn signature

    // Page 1: imported signature/image, a second highlight, to prove
    // multi-page annotation placement stays on the right page.
    controller.addAnnotation(
      1,
      PdfOverlayImage(bytes: _fakeImportedImage(), x: 0.3, y: 0.3, width: 0.3, height: 0.12),
    ); // Imported image
    controller.addAnnotation(
      1,
      const PdfOverlayRect(x: 0.1, y: 0.1, width: 0.3, height: 0.06, color: PdfColor(0.3, 0.6, 1, 0.35)),
    );

    // Watermark - applies to every page at once.
    controller.applyWatermark('DRAFT');

    final state = container.read(pdfEditControllerProvider);
    expect(state.annotationsByPage[0], hasLength(10)); // 9 above + 1 watermark
    expect(state.annotationsByPage[1], hasLength(3)); // 2 above + 1 watermark

    final bytes = await controller.buildResultBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/pdf_edit_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes)');
  });
}
