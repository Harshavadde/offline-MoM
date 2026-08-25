// Manual verification script (Toolkit productization pass, P0-4, Permanent
// PDF Redaction) - NOT part of the regular regression suite. Drives
// PdfRedactionService end to end against a page with genuinely rendered
// text and an image-like block (TextImagePdfPageRenderingService,
// test_helpers/), applies redaction over both, and writes both the
// PRE-redaction and POST-redaction pages as real, independently-openable
// PDFs so the two can be visually compared side by side - the P0-4 spec's
// own "generate a real PDF containing obvious text and an image, apply
// redactions, generate the final PDF, open the resulting PDF, confirm the
// redacted output visually looks correct" manual-verification steps.
//
// Run with: flutter test test/manual/generate_pdf_redaction_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../test_helpers/text_image_pdf_page_rendering_service.dart';

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

  test('redacts a page with real rendered text and an image-like block; writes before/after PDFs for visual inspection', () async {
    final docsDir = await Directory.systemTemp.createTemp('pdf_redaction_demo_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    final service = PdfRedactionService();
    final rendering = TextImagePdfPageRenderingService(
      text: 'CONFIDENTIAL: SSN 123-45-6789',
      pageWidth: 600,
      pageHeight: 800,
    );
    final sourceBytes = Uint8List.fromList([1, 2, 3]);

    // BEFORE - the same page, rebuilt with zero redactions, so it's
    // visually the true "what did the original page look like" reference.
    final before = await service.applyRedactions(sourceBytes, renderingService: rendering, regionsByPage: const {});

    // AFTER - the sensitive text (drawn at x:40,y:60 in a 600x800 page)
    // AND the image-like block (drawn at 60,300-260,420) are both
    // redacted; the unrelated control paragraph at y:500 is left alone,
    // so a visual diff between before/after should show it untouched.
    final after = await service.applyRedactions(
      sourceBytes,
      renderingService: rendering,
      regionsByPage: const {
        0: [
          RedactionRegion(x: 0.02, y: 0.04, width: 0.65, height: 0.1), // the SSN text
          // The "photo" block is drawn at pixel (60,300)-(260,420) in a
          // 600x800 page (normalized x:0.10-0.43, y:0.375-0.525) - this
          // region is deliberately larger than that exact rect (a small
          // margin on every side), not just an exact fit, so a region
          // drawn slightly imprecisely (as a real user's finger-drag
          // easily could be) still fully covers the sensitive content
          // instead of leaving a sliver of it exposed at the edge.
          RedactionRegion(x: 0.07, y: 0.35, width: 0.42, height: 0.2),
        ],
      },
    );

    expect(before, isNotEmpty);
    expect(after, isNotEmpty);
    expect(String.fromCharCodes(before.take(5)), '%PDF-');
    expect(String.fromCharCodes(after.take(5)), '%PDF-');
    expect(after, isNot(equals(before)));

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final beforeFile = File('${outDir.path}/pdf_redaction_demo_before.pdf');
    final afterFile = File('${outDir.path}/pdf_redaction_demo_after.pdf');
    await beforeFile.writeAsBytes(before);
    await afterFile.writeAsBytes(after);
    // ignore: avoid_print
    print('OK   wrote ${beforeFile.path} (${before.length} bytes)');
    // ignore: avoid_print
    print('OK   wrote ${afterFile.path} (${after.length} bytes)');
  });
}
