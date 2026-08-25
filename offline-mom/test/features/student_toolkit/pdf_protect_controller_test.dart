// Tests ProtectPdfController - mirrors the established ProviderContainer
// pattern. PdfSecurityService itself is real (pure Dart, no native
// platform channel - unlike Printing.raster()/read_pdf_text, nothing here
// needs faking), so these tests exercise the real crypto path end to end,
// same as pdf_security_service_test.dart, but through the controller's own
// state machine (password/confirm validation, busy/error states, save).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_protect_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/pdf_security/pdf_permissions.dart';
import 'package:offline_mom/services/toolkit/pdf_page_composer.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf_cos/pdf_cos.dart' show CosDocument, CosPasswordException;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _tinyJpeg() {
  final image = img.Image(width: 40, height: 40);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(img.encodeJpg(image));
}

// The rasterization step (preview thumbnails) is faked via
// FakePdfPageRenderingService, but protect() itself calls the REAL
// PdfSecurityService on `source.bytes` directly - so the picked "PDF" must
// be a real, valid PDF (built with the same PdfPageComposerService every
// other PDF Tool uses), not arbitrary bytes.
Future<Uint8List> _realPlainPdf() async {
  final composer = PdfPageComposerService();
  return composer.compose([PdfPageInput(jpegBytes: _tinyJpeg(), width: 40, height: 40)]);
}

void main() {
  late Directory docsDir;
  late Database db;
  late FakeToolkitFilePickerService pickerService;
  late ProviderContainer container;

  setUp(() async {
    docsDir = await Directory.systemTemp.createTemp('pdf_protect_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    db = await openTestDatabase();
    pickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        pdfPageRenderingServiceProvider.overrideWithValue(
          FakePdfPageRenderingService(pageCount: 1, pageWidth: 40, pageHeight: 40),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  Future<void> pick() async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'plain.pdf', bytes: await _realPlainPdf());
    await container.read(protectPdfControllerProvider.notifier).pickPdf();
  }

  test('canProtect is false until a non-empty password is confirmed (scenario: empty/mismatched password)', () async {
    await pick();
    final controller = container.read(protectPdfControllerProvider.notifier);
    expect(container.read(protectPdfControllerProvider).canProtect, isFalse);

    controller.setPassword('secret');
    expect(container.read(protectPdfControllerProvider).canProtect, isFalse, reason: 'not confirmed yet');

    controller.setConfirmPassword('different');
    expect(container.read(protectPdfControllerProvider).canProtect, isFalse, reason: 'mismatched');

    controller.setConfirmPassword('secret');
    expect(container.read(protectPdfControllerProvider).canProtect, isTrue);
  });

  test('protect() produces real, independently-verifiable encrypted bytes', () async {
    await pick();
    final controller = container.read(protectPdfControllerProvider.notifier);
    controller.setPassword('correct-horse');
    controller.setConfirmPassword('correct-horse');

    await controller.protect();

    final state = container.read(protectPdfControllerProvider);
    expect(state.isDone, isTrue);
    expect(state.error, isNull);

    final doc = CosDocument.open(state.resultBytes!, password: 'correct-horse');
    expect(doc.isEncrypted, isTrue);
    expect(
      () => CosDocument.open(state.resultBytes!, password: 'wrong'),
      throwsA(isA<CosPasswordException>()),
    );
  });

  test('the chosen permissions really are encoded in the output', () async {
    await pick();
    final controller = container.read(protectPdfControllerProvider.notifier);
    controller.setPassword('pw');
    controller.setConfirmPassword('pw');
    controller.setPermissions(const PdfPermissions(allowCopying: false));

    await controller.protect();

    final bytes = container.read(protectPdfControllerProvider).resultBytes!;
    final doc = CosDocument.open(bytes, password: 'pw');
    final encrypt = doc.resolve(doc.trailer['Encrypt']);
    expect(encrypt, isNotNull);
  });

  test('save() writes a new ToolkitFile with pdfProtect tool type', () async {
    await pick();
    final controller = container.read(protectPdfControllerProvider.notifier);
    controller.setPassword('pw');
    controller.setConfirmPassword('pw');
    await controller.protect();

    final saved = await controller.save();
    expect(saved, isNotNull);
    expect(await File(saved!.outputPath).exists(), isTrue);

    // Idempotent - a second call returns the same row, not a duplicate.
    final savedAgain = await controller.save();
    expect(savedAgain!.id, saved.id);
  });

  test('reset() clears the whole session', () async {
    await pick();
    final controller = container.read(protectPdfControllerProvider.notifier);
    controller.setPassword('pw');
    controller.reset();
    final state = container.read(protectPdfControllerProvider);
    expect(state.isEmpty, isTrue);
    expect(state.password, isEmpty);
  });
}
