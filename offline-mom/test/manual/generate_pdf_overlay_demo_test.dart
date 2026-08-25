// Manual verification script (Toolkit productization pass, P0-2) - NOT
// part of the regular regression suite. Runs PdfOverlayService end to end
// against FakePdfPageRenderingService (the same fake every Printing.raster-
// backed service test in this project already uses, since the real
// platform channel has no implementation under `flutter test`) and writes
// a real, inspectable PDF - so the overlay positioning/color/text/line
// math in pdf_overlay.dart can be visually verified against actual output,
// not just asserted by a unit test. The rebuild step (doc.save()) is 100%
// real `package:pdf` output; only the "read an existing source PDF's
// pages" step is faked (synthetic solid-color base pages stand in for a
// genuinely-rasterized real PDF - that rasterization step itself is
// unchanged by this pass and already covered by every other PDF Tool
// service's own tests).
//
// Run with: flutter test test/manual/generate_pdf_overlay_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders every overlay element kind on top of a synthetic source PDF, for visual inspection', () async {
    final docsDir = await Directory.systemTemp.createTemp('pdf_overlay_demo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final service = PdfOverlayService();
    final fakeRenderer = FakePdfPageRenderingService(pageCount: 2, pageWidth: 850, pageHeight: 1100);

    // A minimal, valid "source PDF" - PdfPageRenderingService.rasterizePages
    // only cares about pageIndices/pageCount here (the fake ignores the
    // actual bytes), so any non-empty byte sequence stands in.
    final sourceBytes = Uint8List.fromList([1, 2, 3]);

    final bytes = await service.applyOverlays(
      sourceBytes,
      renderingService: fakeRenderer,
      overlaysByPage: {
        0: [
          const PdfOverlayText(
            text: 'Add Text: CONFIDENTIAL',
            x: 0.05,
            y: 0.05,
            fontSize: 24,
            color: PdfColors.red,
          ),
          // An opaque yellow rect, then a translucent blue rect drawn
          // partially over it - if the highlight's alpha is genuinely
          // respected (not accidentally opaque), the overlapping region
          // should show a blended color, visually distinct from the
          // non-overlapping parts of both rects.
          const PdfOverlayRect(
            x: 0.1,
            y: 0.2,
            width: 0.3,
            height: 0.08,
            color: PdfColors.yellow,
          ),
          const PdfOverlayRect(
            x: 0.25,
            y: 0.2,
            width: 0.3,
            height: 0.08,
            color: PdfColor.fromInt(0x664dabf5), // translucent blue - Highlight
          ),
          const PdfOverlayLine(
            points: [(0.1, 0.35), (0.4, 0.35)],
            // Deliberately NOT black - page 0's synthetic fake-rasterizer
            // background is pure black ((index*37)%256 for index 0), which
            // would make a black line invisible by coincidence, not proof
            // the overlay itself is broken. White makes this visually
            // conclusive against that specific background.
            color: PdfColors.white,
            strokeWidth: 1.5,
          ), // Underline
          const PdfOverlayLine(
            points: [(0.1, 0.42), (0.4, 0.44)],
            color: PdfColors.red,
            strokeWidth: 2,
          ), // Strikethrough
          const PdfOverlayLine(
            points: [(0.5, 0.6), (0.55, 0.65), (0.52, 0.7), (0.6, 0.75)],
            color: PdfColors.green,
            strokeWidth: 3,
          ), // Freehand
          const PdfOverlayRect(
            x: 0.6,
            y: 0.1,
            width: 0.15,
            height: 0.15,
            color: PdfColors.purple,
            filled: false,
            strokeWidth: 2,
          ), // Shape (outlined rect)
        ],
        // page 1 (index 1) deliberately has no overlay - proves the
        // no-overlay path renders unchanged alongside an overlaid page in
        // the same document.
      },
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/pdf_overlay_demo.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('OK   wrote ${file.path} (${bytes.length} bytes)');
  });
}
