import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/toolkit/scanner_pdf_service.dart';

Uint8List _pageJpeg({int width = 300, int height = 400}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(50, 60, 70));
  return img.encodeJpg(image, quality: 90);
}

void main() {
  group('PwScannerPdfService', () {
    test('builds a valid multi-page PDF from an ordered page list', () async {
      final service = PwScannerPdfService();
      final pages = [
        ScannedPage(id: 'a', jpegBytes: _pageJpeg(), width: 300, height: 400),
        ScannedPage(id: 'b', jpegBytes: _pageJpeg(width: 200, height: 260), width: 200, height: 260),
      ];

      final bytes = await service.buildPdf(pages);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('throws when given no pages', () {
      final service = PwScannerPdfService();
      expect(
        () => service.buildPdf(const []),
        throwsA(isA<ScannerPdfException>()),
      );
    });

    test('a single-page PDF is smaller than a ten-page PDF built from the '
        'same page (a sanity check that pages are genuinely repeated, not '
        'deduplicated/dropped)', () async {
      final service = PwScannerPdfService();
      final page = ScannedPage(id: 'a', jpegBytes: _pageJpeg(), width: 300, height: 400);

      final onePage = await service.buildPdf([page]);
      final tenPages = await service.buildPdf(List.filled(10, page));

      expect(tenPages.lengthInBytes, greaterThan(onePage.lengthInBytes));
    });
  });
}
