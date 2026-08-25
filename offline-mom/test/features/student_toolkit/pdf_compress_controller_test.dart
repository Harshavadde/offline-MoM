import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_compress_providers.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/toolkit_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_compression_service.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitFilePickerService pickerService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('pdf_compress_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 3)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('picking then compressing moves empty -> ready -> done', () async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'resume.pdf', bytes: Uint8List(0));
    final controller = container.read(pdfCompressControllerProvider.notifier);

    await controller.pickPdf();
    expect(container.read(pdfCompressControllerProvider), isA<PdfCompressReady>());

    await controller.compress(PdfCompressionPreset.resumeUpload);

    final state = container.read(pdfCompressControllerProvider);
    expect(state, isA<PdfCompressDone>());
    expect((state as PdfCompressDone).result.pageCount, 3);
  });

  test('save() writes a real PDF and inserts a Recent Files row titled '
      'from the source filename', () async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'scholarship_form.pdf', bytes: Uint8List(0));
    final controller = container.read(pdfCompressControllerProvider.notifier);
    await controller.pickPdf();
    await controller.compress(PdfCompressionPreset.scholarship);

    final saved = await controller.save();

    expect(saved, isNotNull);
    // V2.2 Production Hardening, Priority 7: the toolkit's title-from
    // -filename logic now reuses deriveDocumentTitle() (previously a
    // naive "strip the extension" that left "scholarship_form" verbatim,
    // underscore and all) - normalizes separators to spaces the same way
    // document import already does, in addition to stripping UUIDs/hash
    // -like tokens this test's own fixture doesn't happen to exercise.
    expect(saved!.title, 'scholarship form');
    expect(await File(saved.outputPath).exists(), isTrue);
    expect(await container.read(toolkitFileListProvider.future), hasLength(1));

    // Idempotent on a second call.
    final savedAgain = await controller.save();
    expect(savedAgain!.id, saved.id);
    expect(await container.read(toolkitFileListProvider.future), hasLength(1));
  });

  test('a rasterization failure moves to an error state with a friendly '
      'message, not a crash', () async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'broken.pdf', bytes: Uint8List(0));
    container.dispose();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(
          FakePdfPageRenderingService(
            throwOnRasterize: const PdfRenderingException('This PDF is password-protected.'),
          ),
        ),
      ],
    );
    final controller = container.read(pdfCompressControllerProvider.notifier);
    await controller.pickPdf();

    await controller.compress(PdfCompressionPreset.custom, customDpi: 100, customQuality: 60);

    final state = container.read(pdfCompressControllerProvider);
    expect(state, isA<PdfCompressError>());
    expect((state as PdfCompressError).message, 'This PDF is password-protected.');
  });

  test('cancel() during compression returns to ready and discards the '
      'eventual result', () async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'resume.pdf', bytes: Uint8List(0));
    final controller = container.read(pdfCompressControllerProvider.notifier);
    await controller.pickPdf();

    final future = controller.compress(PdfCompressionPreset.resumeUpload);
    expect(container.read(pdfCompressControllerProvider), isA<PdfCompressProcessing>());

    controller.cancel();
    expect(container.read(pdfCompressControllerProvider), isA<PdfCompressReady>());

    await future;
    expect(container.read(pdfCompressControllerProvider), isA<PdfCompressReady>());
  });
}
