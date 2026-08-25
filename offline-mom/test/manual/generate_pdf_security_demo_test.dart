// Manual verification script (P0-8, PDF Security) - NOT part of the
// regular regression suite. Every byte written here is real, shipped
// production output: PdfPageComposerService/SearchablePdfBuilderService
// build the plain source PDFs (the exact primitives every other PDF Tool
// uses), then the REAL PdfSecurityService.protect()/removePassword() do the
// encryption/decryption - nothing here is faked.
//
// Independent verification, per the P0-8 spec's own "do not merely test
// your own service's output" instruction:
//   1. Every protected file is reopened with pdf_cos's own CosDocument.open
//      directly - a wholly separate code path from PdfSecurityService.
//   2. Naive zlib-inflation of every `stream ... endstream` block (the same
//      technique the P0-7 OCR demo used) is run against BOTH the protected
//      and the unlocked bytes. On the protected file this must find *zero*
//      occurrences of the known content marker, because the stream bytes
//      are now AES ciphertext, not Flate-then-plaintext - proving the
//      content is genuinely encrypted, not merely flagged as such. On the
//      unlocked file the same search must find every marker again.
//   3. Permissions are read back from the real /P entry in the reopened
//      /Encrypt dictionary, not from PdfSecurityService's own claims.
//
// Run with: flutter test test/manual/generate_pdf_security_demo_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/services/ocr/hocr_parser.dart';
import 'package:offline_mom/services/ocr/ocr_text_extraction_service.dart';
import 'package:offline_mom/services/ocr/searchable_pdf_builder_service.dart';
import 'package:offline_mom/services/pdf_security/pdf_permissions.dart';
import 'package:offline_mom/services/pdf_security/pdf_security_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_composer.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf_cos/pdf_cos.dart';
import 'package:pdf_document/pdf_document.dart' as pdfdoc;

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _photoJpeg(String label, {int width = 600, int height = 800}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(210, 220, 235));
  img.drawString(image, label, font: img.arial24, x: 30, y: 30, color: img.ColorRgb8(20, 20, 20));
  return Uint8List.fromList(img.encodeJpg(image));
}

Future<Uint8List> _plainPdf({int pages = 1}) async {
  final composer = PdfPageComposerService();
  return composer.compose([
    for (var i = 0; i < pages; i++) PdfPageInput(jpegBytes: _photoJpeg('Page ${i + 1} of $pages'), width: 600, height: 800),
  ]);
}

/// Same zlib-block-scan technique as the P0-7 OCR demo script - decodes
/// every stream that happens to be valid zlib and searches the decoded
/// bytes for [text]. Deliberately naive (no decryption, no filter-chain
/// awareness) so a "found" result on a protected file would mean real
/// plaintext leakage, and a "not found" result on the unlocked file would
/// mean real content loss.
bool _rawStreamsContain(Uint8List pdfBytes, String text) {
  final content = String.fromCharCodes(pdfBytes);
  var searchFrom = 0;
  while (true) {
    final streamIdx = content.indexOf('stream', searchFrom);
    if (streamIdx == -1) return false;
    var dataStart = streamIdx + 'stream'.length;
    if (dataStart < pdfBytes.length && pdfBytes[dataStart] == 0x0d) dataStart++;
    if (dataStart < pdfBytes.length && pdfBytes[dataStart] == 0x0a) dataStart++;
    final endIdx = content.indexOf('endstream', dataStart);
    if (endIdx == -1) return false;
    final raw = pdfBytes.sublist(dataStart, endIdx);
    try {
      final decoded = zlib.decode(raw);
      if (String.fromCharCodes(decoded).contains(text)) return true;
    } catch (_) {
      // Not valid zlib (ciphertext, or a font binary) - not a leak, skip.
    }
    searchFrom = endIdx + 'endstream'.length;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = PdfSecurityService();
  late Directory docsDir;
  late Directory outDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_security_demo_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    outDir = Directory(_outputDir)..createSync(recursive: true);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('1-page PDF: protect, independently verify, wrong/correct password, unlock (scenario: 1-page)', () async {
    final plain = await _plainPdf();
    final protected = await service.protect(plain, userPassword: 'S3cret!', permissions: const PdfPermissions());

    // Independent reopen #1 - a wholly separate code path from protect().
    final noPwCheck = PdfSecurityInfo(isEncrypted: (() {
      try {
        CosDocument.open(protected);
        return false;
      } on CosPasswordException {
        return true;
      }
    })());
    expect(noPwCheck.isEncrypted, isTrue, reason: 'reopening with no password must fail - it is genuinely encrypted');

    expect(() => CosDocument.open(protected, password: 'wrong'), throwsA(isA<CosPasswordException>()));
    final opened = CosDocument.open(protected, password: 'S3cret!');
    expect(opened.isEncrypted, isTrue);

    final unlocked = await service.removePassword(protected, 'S3cret!');
    final reopenedUnlocked = CosDocument.open(unlocked);
    expect(reopenedUnlocked.isEncrypted, isFalse);

    await File('${outDir.path}/security_1page_protected.pdf').writeAsBytes(protected);
    await File('${outDir.path}/security_1page_unlocked.pdf').writeAsBytes(unlocked);
    // ignore: avoid_print
    print('OK   wrote security_1page_protected.pdf (${protected.length}B) + '
        'security_1page_unlocked.pdf (${unlocked.length}B) - open the protected one in a PDF '
        'viewer and confirm it prompts for a password ("S3cret!"), then confirm the unlocked '
        'copy opens directly with the same visible page content.');
  });

  test('multi-page PDF: page count preserved through protect + unlock (scenario: multi-page)', () async {
    final plain = await _plainPdf(pages: 6);
    final plainPageCount = pdfdoc.PdfDocument.open(plain).pageCount;
    expect(plainPageCount, 6);

    final protected = await service.protect(plain, userPassword: 'multi-pw');
    final unlocked = await service.removePassword(protected, 'multi-pw');

    expect(pdfdoc.PdfDocument.open(protected, password: 'multi-pw').pageCount, 6);
    expect(pdfdoc.PdfDocument.open(unlocked).pageCount, 6, reason: 'unlock must not drop or merge pages');

    await File('${outDir.path}/security_multipage_protected.pdf').writeAsBytes(protected);
    await File('${outDir.path}/security_multipage_unlocked.pdf').writeAsBytes(unlocked);
    // ignore: avoid_print
    print('OK   wrote security_multipage_protected.pdf + security_multipage_unlocked.pdf '
        '(6 pages each, independently confirmed via pdf_document.pageCount) - open both and '
        'page through to confirm all 6 pages render in order.');
  });

  test('permissions are genuinely encoded in the real /P entry, not merely claimed by the UI (scenario: permissions)', () async {
    final plain = await _plainPdf();
    const chosen = PdfPermissions(allowPrinting: false, allowCopying: false, allowModify: true, allowAnnotations: true);
    final protected = await service.protect(plain, userPassword: 'perm-pw', permissions: chosen);

    // Independent read: reopen, resolve the real /Encrypt dictionary, read
    // /P directly - not PdfPermissions.toPBits()' own claim about itself.
    final doc = CosDocument.open(protected, password: 'perm-pw');
    final encryptDict = doc.resolve(doc.trailer['Encrypt']) as CosDictionary;
    final pValue = (encryptDict['P'] as CosInteger).value;
    final decoded = PdfPermissions.fromPBits(pValue);

    expect(decoded.allowPrinting, isFalse);
    expect(decoded.allowCopying, isFalse);
    expect(decoded.allowModify, isTrue);
    expect(decoded.allowAnnotations, isTrue);

    await File('${outDir.path}/security_permissions_protected.pdf').writeAsBytes(protected);
    // ignore: avoid_print
    print('OK   wrote security_permissions_protected.pdf - printing and copying disallowed, '
        'modify/annotations allowed; confirmed by decoding the real /P entry independently, '
        'not by asking PdfSecurityService what it thinks it did.');
  });

  test('OCR-generated searchable PDF: text is real ciphertext when protected, real plaintext once unlocked '
      '(scenario: search/OCR interaction with protected PDFs)', () async {
    const marker = 'ConfidentialQuarterlyRevenueFigures';
    final ocr = FakeOcrTextExtractionService(
      defaultWords: [const OcrWord(text: marker, x0: 40, y0: 90, x1: 500, y1: 120)],
    );
    final builder = SearchablePdfBuilderService(ocrService: ocr);
    final plain = await builder.build(
      [OcrSourcePage(jpegBytes: _photoJpeg('Scanned report'), width: 850, height: 1100)],
      language: 'eng',
    );
    // Sanity: the marker really is present, in the clear, before protection.
    expect(_rawStreamsContain(plain, marker), isTrue, reason: 'the plain OCR PDF must contain the marker in the clear');

    final protected = await service.protect(plain, userPassword: 'ocr-pw');
    expect(
      _rawStreamsContain(protected, marker),
      isFalse,
      reason: 'the SAME naive scan must find NOTHING once protected - proof the content stream is '
          'genuinely AES-ciphertext, not merely relabeled or hidden by a viewer-side flag',
    );

    final unlocked = await service.removePassword(protected, 'ocr-pw');
    expect(_rawStreamsContain(unlocked, marker), isTrue, reason: 'unlocking must restore the exact original searchable text');

    await File('${outDir.path}/security_ocr_plain.pdf').writeAsBytes(plain);
    await File('${outDir.path}/security_ocr_protected.pdf').writeAsBytes(protected);
    await File('${outDir.path}/security_ocr_unlocked.pdf').writeAsBytes(unlocked);
    // ignore: avoid_print
    print('OK   wrote security_ocr_plain.pdf, security_ocr_protected.pdf, security_ocr_unlocked.pdf - '
        'open the protected copy, enter "ocr-pw", and confirm Ctrl+F for '
        '"$marker" still finds it once unlocked in a real viewer (Adobe/browser), matching this '
        'script\'s own independent zlib-level confirmation.');
  });

  test('removing protection never touches the original protected bytes (scenario: original file unchanged)', () async {
    final plain = await _plainPdf();
    final protected = await service.protect(plain, userPassword: 'immutable-pw');
    final protectedCopy = Uint8List.fromList(protected);

    await service.removePassword(protected, 'immutable-pw');

    expect(protected, orderedEquals(protectedCopy), reason: 'removePassword must return a new buffer, never mutate its input');
    expect(CosDocument.open(protected, password: 'immutable-pw').isEncrypted, isTrue, reason: 'the original protected bytes must still open with the same password after unlocking a copy');
  });

  test('a corrupted PDF and an incorrect existing password both fail cleanly, offline, with no crash (scenario: error handling)', () async {
    final garbage = Uint8List.fromList(List.generate(200, (i) => i % 256));
    expect(service.inspect(garbage).isCorrupted, isTrue);
    await expectLater(
      service.protect(garbage, userPassword: 'pw'),
      throwsA(isA<PdfSecurityException>()),
    );

    final plain = await _plainPdf();
    final protected = await service.protect(plain, userPassword: 'right-pw');
    await expectLater(
      service.removePassword(protected, 'wrong-pw'),
      throwsA(isA<PdfSecurityException>().having((e) => e.isWrongPassword, 'isWrongPassword', isTrue)),
    );
    // ignore: avoid_print
    print('OK   corrupted-PDF and wrong-password paths both threw PdfSecurityException '
        'with no crash, entirely offline.');
  });
}
