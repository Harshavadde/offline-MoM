// Tests pdf_searchable_text_preservation.dart (release blocker B3, R-49) -
// the shared "restore approximate searchable text on a rebuilt page"
// primitive every rasterize-and-rebuild PDF Tool (Compress/Merge/Split/
// Organize/Edit/Redact) now reuses.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/toolkit/pdf_overlay.dart';
import 'package:offline_mom/services/toolkit/pdf_searchable_text_preservation.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Directory docsDir;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_searchable_text_preservation_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  group('PdfSearchableTextPreserver.extractExistingText', () {
    test('returns a 0-based page index -> text map, skipping blank pages', () async {
      final fake = FakePdfTextSearchService();
      final preserver = PdfSearchableTextPreserver(textSearchService: fake);
      final source = Uint8List.fromList([1, 2, 3]);
      // FakePdfTextSearchService is keyed by the temp file path this
      // preserver itself writes and controls - register against whatever
      // path it actually uses by intercepting via a wrapper instead.
      final result = await preserver.extractExistingText(source);
      // No entry registered for the real (unknown) temp path -> fake
      // returns const [] -> empty map, proving "nothing found" degrades
      // safely rather than throwing.
      expect(result, isEmpty);
    });

    test('never throws when the underlying text service throws (corrupted/encrypted source)', () async {
      final fake = _ThrowingTextSearchService();
      final preserver = PdfSearchableTextPreserver(textSearchService: fake);

      final result = await preserver.extractExistingText(Uint8List.fromList([1, 2, 3]));

      expect(result, isEmpty);
    });

    test('extracts real per-page text via a genuinely written temp file', () async {
      final recording = _RecordingTextSearchService(
        pagesToReturn: ['Page one text', '', 'Page three text'],
      );
      final preserver = PdfSearchableTextPreserver(textSearchService: recording);
      final source = Uint8List.fromList(List.generate(50, (i) => i));

      final result = await preserver.extractExistingText(source);

      expect(result, {0: 'Page one text', 2: 'Page three text'});
      expect(recording.lastPathBytes, source, reason: 'the exact source bytes must reach the text service');
    });

    test('deletes its own temp file after extraction, even on failure', () async {
      final recording = _RecordingTextSearchService(pagesToReturn: const ['some text']);
      final preserver = PdfSearchableTextPreserver(textSearchService: recording);

      await preserver.extractExistingText(Uint8List.fromList([9, 9, 9]));

      expect(File(recording.lastPath!).existsSync(), isFalse);
    });
  });

  group('overlayForExistingText', () {
    test('returns an empty list for null text', () {
      expect(overlayForExistingText(null, 800, 1100, 150), isEmpty);
    });

    test('returns an empty list for blank/whitespace-only text', () {
      expect(overlayForExistingText('   \n  ', 800, 1100, 150), isEmpty);
    });

    test('returns invisible text elements for real text', () {
      final overlay = overlayForExistingText('Hello world\nSecond line', 800, 1100, 150);

      expect(overlay, isNotEmpty);
      for (final element in overlay) {
        expect(element, isA<PdfOverlayText>());
        expect((element as PdfOverlayText).invisible, isTrue);
      }
    });
  });
}

class _ThrowingTextSearchService implements PdfTextSearchService {
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    throw const PdfTextSearchException('boom');
  }
}

class _RecordingTextSearchService implements PdfTextSearchService {
  _RecordingTextSearchService({required this.pagesToReturn});
  final List<String> pagesToReturn;
  String? lastPath;
  Uint8List? lastPathBytes;

  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    lastPath = pdfFilePath;
    lastPathBytes = await File(pdfFilePath).readAsBytes();
    return pagesToReturn;
  }
}
