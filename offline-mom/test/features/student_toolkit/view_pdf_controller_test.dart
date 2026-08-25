// Tests ViewPdfController (Toolkit productization pass, P0-6, View PDF +
// Search) - mirrors the established ProviderContainer/fake-service pattern.
// FakePdfTextSearchService stands in for read_pdf_text (a real native
// plugin, no implementation under `flutter test` - the same standing
// limitation as Printing.raster, R-32) - keyed by the exact toolkit temp
// file path the controller itself writes the picked bytes to, so these
// tests also implicitly prove the controller writes a real temp file and
// cleans it up (asserted directly below too).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/ocr_providers.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/view_pdf_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/pdf_security/pdf_security_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_composer.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// A fake that records every temp-file path it was asked to extract text
/// from and returns a fixed set of per-page text regardless of the exact
/// path (the controller generates a fresh path per call via
/// `DateTime.now()`, so tests can't predict it exactly) - proves the
/// controller actually calls through to a real file path, not bytes
/// directly, without needing to match that path precisely.
class _RecordingPdfTextSearchService implements PdfTextSearchService {
  _RecordingPdfTextSearchService(this.pagesText);
  final List<String> pagesText;
  final List<String> requestedPaths = [];
  bool throwOnNextCall = false;

  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async {
    requestedPaths.add(pdfFilePath);
    if (throwOnNextCall) throw const PdfTextSearchException('boom');
    return pagesText;
  }
}

void main() {
  late Directory docsDir;
  late FakeToolkitFilePickerService pickerService;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('view_pdf_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
  });

  tearDown(() async {
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  ProviderContainer buildContainer(_RecordingPdfTextSearchService searchService, {int pageCount = 5}) {
    return ProviderContainer(
      overrides: [
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(FakePdfPageRenderingService(pageCount: pageCount, pageWidth: 300, pageHeight: 400)),
        pdfTextSearchServiceProvider.overrideWithValue(searchService),
      ],
    );
  }

  test('picking a PDF rasterizes every page for display', () async {
    final container = buildContainer(_RecordingPdfTextSearchService(const []));
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1, 2, 3]));

    await container.read(viewPdfControllerProvider.notifier).pickPdf();

    expect(container.read(viewPdfControllerProvider).pages, hasLength(5));
  });

  test('goToPage navigates within bounds and ignores out-of-range indices', () async {
    final container = buildContainer(_RecordingPdfTextSearchService(const []));
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    controller.goToPage(3);
    expect(container.read(viewPdfControllerProvider).currentPage, 3);

    controller.goToPage(99);
    expect(container.read(viewPdfControllerProvider).currentPage, 3); // unchanged
  });

  test('ensureTextExtracted calls the search service with a real on-disk temp file path, cleaned up after', () async {
    final searchService = _RecordingPdfTextSearchService(['page one', 'Kubernetes here', 'page three', 'page four', 'page five']);
    final container = buildContainer(searchService);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    await controller.ensureTextExtracted();

    expect(searchService.requestedPaths, hasLength(1));
    final requestedPath = searchService.requestedPaths.single;
    expect(await File(requestedPath).exists(), isFalse); // cleaned up in finally
    expect(container.read(viewPdfControllerProvider).pagesText, hasLength(5));
  });

  test('ensureTextExtracted only runs once - a second call is a no-op while already extracted', () async {
    final searchService = _RecordingPdfTextSearchService(['a', 'b']);
    final container = buildContainer(searchService, pageCount: 2);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    await controller.ensureTextExtracted();
    await controller.ensureTextExtracted();

    expect(searchService.requestedPaths, hasLength(1));
  });

  test('search returns the correct matching pages and jumps to the first match (scenario 31)', () async {
    final searchService = _RecordingPdfTextSearchService([
      'Azure Kubernetes Service overview',
      'nothing relevant',
      'Kubernetes networking deep dive',
      'GitHub Actions pipeline',
      'more Kubernetes content',
    ]);
    final container = buildContainer(searchService);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();
    await controller.ensureTextExtracted();

    controller.setSearchQuery('Kubernetes');

    final state = container.read(viewPdfControllerProvider);
    expect(state.matches.map((m) => m.pageIndex), [0, 2, 4]);
    expect(state.currentPage, 0); // jumped to the first match's page
  });

  test('next/previous navigation cycles through matches correctly (scenario 30)', () async {
    final searchService = _RecordingPdfTextSearchService(['Terraform', 'nothing', 'Terraform', 'nothing', 'Terraform']);
    final container = buildContainer(searchService);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();
    await controller.ensureTextExtracted();
    controller.setSearchQuery('Terraform');
    expect(container.read(viewPdfControllerProvider).currentPage, 0);

    controller.nextMatch();
    expect(container.read(viewPdfControllerProvider).currentPage, 2);

    controller.nextMatch();
    expect(container.read(viewPdfControllerProvider).currentPage, 4);

    controller.nextMatch(); // wraps back to the first match
    expect(container.read(viewPdfControllerProvider).currentPage, 0);

    controller.previousMatch(); // wraps back to the last match
    expect(container.read(viewPdfControllerProvider).currentPage, 4);
  });

  test('selectMatch jumps directly to the chosen result\'s page', () async {
    final searchService = _RecordingPdfTextSearchService(['Terraform', 'nothing', 'Terraform']);
    final container = buildContainer(searchService, pageCount: 3);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();
    await controller.ensureTextExtracted();
    controller.setSearchQuery('Terraform');

    controller.selectMatch(1);

    expect(container.read(viewPdfControllerProvider).currentPage, 2);
  });

  test('a scanned/image-only PDF (no extractable text) is reported honestly, not falsely searchable (scenario 32)', () async {
    final searchService = _RecordingPdfTextSearchService(['', '', '']);
    final container = buildContainer(searchService, pageCount: 3);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'scanned.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    await controller.ensureTextExtracted();

    final state = container.read(viewPdfControllerProvider);
    expect(state.hasExtractedText, isTrue);
    expect(state.isSearchable, isFalse);
  });

  test('clearSearch resets the query and matches without discarding the extracted text', () async {
    final searchService = _RecordingPdfTextSearchService(['Terraform', 'nothing']);
    final container = buildContainer(searchService, pageCount: 2);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();
    await controller.ensureTextExtracted();
    controller.setSearchQuery('Terraform');

    controller.clearSearch();

    final state = container.read(viewPdfControllerProvider);
    expect(state.searchQuery, '');
    expect(state.matches, isEmpty);
    expect(state.hasExtractedText, isTrue); // still extracted, just no active query
  });

  test('searching does not mutate the original picked PDF bytes (scenario 33)', () async {
    final searchService = _RecordingPdfTextSearchService(['Terraform']);
    final container = buildContainer(searchService, pageCount: 1);
    addTearDown(container.dispose);
    final originalBytes = Uint8List.fromList([9, 9, 9, 9]);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: originalBytes);
    final originalCopy = Uint8List.fromList(originalBytes);
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    await controller.ensureTextExtracted();
    controller.setSearchQuery('Terraform');

    expect(container.read(viewPdfControllerProvider).source!.bytes, equals(originalCopy));
  });

  test('a text-extraction failure surfaces a friendly error, not a crash', () async {
    final searchService = _RecordingPdfTextSearchService(const [])..throwOnNextCall = true;
    final container = buildContainer(searchService, pageCount: 1);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    await controller.ensureTextExtracted();

    final state = container.read(viewPdfControllerProvider);
    expect(state.error, isNotNull);
    expect(state.pagesText, isNull);
  });

  test('reset() clears the entire session', () async {
    final container = buildContainer(_RecordingPdfTextSearchService(const []), pageCount: 1);
    addTearDown(container.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List.fromList([1]));
    final controller = container.read(viewPdfControllerProvider.notifier);
    await controller.pickPdf();

    controller.reset();

    expect(container.read(viewPdfControllerProvider).isEmpty, isTrue);
  });

  test(
    'runOcr() (P0-7) primes the OCR session with existing text for already-searchable pages '
    'and null for image-only pages, so those pages are never re-OCR\'d (scenario 26)',
    () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final searchService = _RecordingPdfTextSearchService(const ['Real text on page 1', '', 'Real text on page 3']);
      final container = ProviderContainer(
        overrides: [
          toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
          pdfPageRenderingServiceProvider.overrideWithValue(
            FakePdfPageRenderingService(pageCount: 3, pageWidth: 300, pageHeight: 400),
          ),
          pdfTextSearchServiceProvider.overrideWithValue(searchService),
          installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'mixed.pdf', bytes: Uint8List.fromList([1]));
      final controller = container.read(viewPdfControllerProvider.notifier);
      await controller.pickPdf();

      await controller.runOcr();

      final ocrState = container.read(ocrSessionControllerProvider);
      expect(ocrState.sourcePages, hasLength(3));
      expect(ocrState.sourcePages[0].existingText, 'Real text on page 1');
      expect(ocrState.sourcePages[1].existingText, anyOf(isNull, isEmpty));
      expect(ocrState.sourcePages[2].existingText, 'Real text on page 3');
      // No OCR model installed in this test's db - the session correctly
      // reports that instead of ever calling the (unregistered here)
      // native OCR plugin.
      expect(ocrState.modelMissing, isTrue);
    },
  );

  group('P0-8: encrypted-PDF detection + password flow', () {
    Future<Uint8List> realProtectedPdf({required String password}) async {
      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final plain = await PdfPageComposerService().compose([
        PdfPageInput(jpegBytes: Uint8List.fromList(img.encodeJpg(image)), width: 100, height: 100),
      ]);
      return const PdfSecurityService().protect(plain, userPassword: password);
    }

    late Directory docsDir2;
    setUp(() async {
      docsDir2 = await Directory.systemTemp.createTemp('view_pdf_password_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir2.path);
    });
    tearDown(() async {
      if (await docsDir2.exists()) await docsDir2.delete(recursive: true);
    });

    test('picking an encrypted PDF sets needsPassword instead of attempting to rasterize (scenario B)', () async {
      final container = buildContainer(_RecordingPdfTextSearchService(const []));
      addTearDown(container.dispose);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'locked.pdf', bytes: await realProtectedPdf(password: 'secret'));

      await container.read(viewPdfControllerProvider.notifier).pickPdf();

      final state = container.read(viewPdfControllerProvider);
      expect(state.needsPassword, isTrue);
      expect(state.pages, isEmpty);
    });

    test('the wrong password is rejected with "Incorrect password.", not a crash', () async {
      final container = buildContainer(_RecordingPdfTextSearchService(const []));
      addTearDown(container.dispose);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'locked.pdf', bytes: await realProtectedPdf(password: 'secret'));
      final controller = container.read(viewPdfControllerProvider.notifier);
      await controller.pickPdf();

      await controller.tryPassword('wrong-guess');

      final state = container.read(viewPdfControllerProvider);
      expect(state.needsPassword, isTrue);
      expect(state.passwordError, 'Incorrect password.');
    });

    test('the correct password unlocks and rasterizes the real decrypted content (scenario: unlock)', () async {
      final container = buildContainer(_RecordingPdfTextSearchService(const []), pageCount: 1);
      addTearDown(container.dispose);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'locked.pdf', bytes: await realProtectedPdf(password: 'right-pw'));
      final controller = container.read(viewPdfControllerProvider.notifier);
      await controller.pickPdf();

      await controller.tryPassword('right-pw');

      final state = container.read(viewPdfControllerProvider);
      expect(state.needsPassword, isFalse);
      expect(state.passwordError, isNull);
      expect(state.unlockedBytes, isNotNull);
      expect(state.pages, isNotEmpty);
    });

    test('saveUnlockedCopy writes a new ToolkitFile and never touches the original picked bytes', () async {
      final db = await openTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
          pdfPageRenderingServiceProvider.overrideWithValue(FakePdfPageRenderingService(pageCount: 1, pageWidth: 100, pageHeight: 100)),
          pdfTextSearchServiceProvider.overrideWithValue(_RecordingPdfTextSearchService(const [])),
          toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        ],
      );
      addTearDown(container.dispose);
      final originalBytes = await realProtectedPdf(password: 'pw');
      final originalCopy = Uint8List.fromList(originalBytes);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'locked.pdf', bytes: originalBytes);
      final controller = container.read(viewPdfControllerProvider.notifier);
      await controller.pickPdf();
      await controller.tryPassword('pw');

      final saved = await controller.saveUnlockedCopy();

      expect(saved, isNotNull);
      expect(saved!.pageCount, 1);
      expect(originalBytes, originalCopy, reason: 'the originally-picked encrypted bytes must never be mutated');
      expect(await File(saved.outputPath).exists(), isTrue);
    });

    test('a corrupted (not encrypted) PDF is never mistaken for password-protected - it falls through '
        'to the ordinary rasterization/error path unchanged', () async {
      final container = buildContainer(_RecordingPdfTextSearchService(const []));
      addTearDown(container.dispose);
      pickerService.pdfResult = PickedToolkitFile(fileName: 'garbage.pdf', bytes: Uint8List.fromList([1, 2, 3]));

      await container.read(viewPdfControllerProvider.notifier).pickPdf();

      expect(container.read(viewPdfControllerProvider).needsPassword, isFalse);
    });
  });
}
