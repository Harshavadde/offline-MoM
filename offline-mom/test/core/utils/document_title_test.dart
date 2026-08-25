import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/utils/document_title.dart';

void main() {
  group('deriveDocumentTitle', () {
    test('a clean filename is left alone (just the extension dropped)', () {
      expect(deriveDocumentTitle('Quarterly Report.pdf'), 'Quarterly Report');
    });

    test('underscores/dashes become spaces', () {
      expect(deriveDocumentTitle('Resume_Final-v2.pdf'), 'Resume Final v2');
    });

    test('a long numeric timestamp prefix is stripped', () {
      expect(
        deriveDocumentTitle('202607291339933883_resume_final.pdf'),
        'resume final',
      );
    });

    test('a short numeric token (e.g. a year or version) is preserved', () {
      expect(deriveDocumentTitle('resume_final_v2_2024.pdf'), 'resume final v2 2024');
    });

    test('a UUID is stripped entirely', () {
      expect(
        deriveDocumentTitle('a1b2c3d4-e5f6-4a5b-9c8d-1234567890ab_invoice.pdf'),
        'invoice',
      );
    });

    test('a hash-like hex token is stripped', () {
      expect(deriveDocumentTitle('invoice_9f8e7d6c5b4a.pdf'), 'invoice');
    });

    test('a parenthesized copy counter is stripped', () {
      expect(deriveDocumentTitle('Resume (1).pdf'), 'Resume');
    });

    test('percent-encoded URL garbage is decoded and cleaned', () {
      expect(deriveDocumentTitle('My%20Resume%20Final.pdf'), 'My Resume Final');
    });

    test('a generic leading download-tool prefix is stripped', () {
      expect(deriveDocumentTitle('download_invoice_march.pdf'), 'invoice march');
    });

    test('falls back to "Untitled Document" when nothing meaningful survives', () {
      expect(deriveDocumentTitle('a1b2c3d4-e5f6-4a5b-9c8d-1234567890ab.pdf'), 'Untitled Document');
      expect(deriveDocumentTitle('202607291339933883.pdf'), 'Untitled Document');
      // A phone camera's default naming scheme: a generic "IMG" prefix
      // followed by nothing but a date and a time - there's no real title
      // information left once both are stripped.
      expect(deriveDocumentTitle('IMG_20240615_143022.jpg'), 'Untitled Document');
    });

    test('a custom fallback can be supplied', () {
      expect(
        deriveDocumentTitle('202607291339933883.pdf', fallback: 'New Document'),
        'New Document',
      );
    });
  });
}
