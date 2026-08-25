import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/documents/parsers/pdf_parser.dart';

/// [PdfParser] delegates to the `read_pdf_text` plugin's native Android/iOS
/// code via a `MethodChannel`, which isn't available in a plain `flutter
/// test` run - so these tests mock that channel directly rather than
/// exercising real PDF parsing (there is no pure-Dart PDF fixture path
/// that would reach [PdfParser] without it). This still exercises 100% of
/// [PdfParser]'s own logic: the success/empty/exception branches around
/// the plugin call, which is everything this class is responsible for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('read_pdf_text');
  late PdfParser parser;

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    parser = PdfParser();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the trimmed text the plugin reports', () async {
    mockChannel((call) async {
      expect(call.method, 'getPDFtext');
      return '  Extracted PDF body.  \n';
    });

    final text = await parser.extractText('/fake/document.pdf');

    expect(text, 'Extracted PDF body.');
  });

  test('returns null for a scanned/image-only PDF (empty text layer)',
      () async {
    mockChannel((call) async => '   ');

    expect(await parser.extractText('/fake/scanned.pdf'), isNull);
  });

  test('wraps a PlatformException as PdfReadException with a friendly message',
      () async {
    mockChannel((call) async {
      throw PlatformException(code: 'PDF_ERROR', message: 'file is corrupted');
    });

    await expectLater(
      parser.extractText('/fake/corrupt.pdf'),
      throwsA(
        isA<PdfReadException>().having(
          (e) => e.message,
          'message',
          contains('could not be read'),
        ),
      ),
    );
  });
}
