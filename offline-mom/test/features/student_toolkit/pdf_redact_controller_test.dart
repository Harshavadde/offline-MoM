// Tests PdfRedactController (Toolkit productization pass, P0-4) - Permanent
// PDF Redaction. Mirrors pdf_edit_controller_test.dart's exact
// ProviderContainer/fake-service pattern, but exercises PdfRedactionService
// (pixel-burn), never PdfOverlayService - see ADR-040/ADR-041/ADR-042 for
// why those two mechanisms are deliberately not interchangeable.
//
// Scenarios 6-8 from the P0-4 spec ("redaction over text/image/vector
// graphics") are not independently testable here: `FakePdfPageRenderingService`
// only ever produces a flat synthetic solid-color page (the same
// `Printing.raster` platform-channel limitation every other PDF Tool test in
// this codebase already lives with), and - more fundamentally - this app's
// whole PDF pipeline (ADR-034) already rasterizes every page to a flat
// image with no text/vector layer *before* redaction ever runs, so "was it
// text or an image underneath" is not a distinct code path at the point
// burnRedactions operates: it overwrites pixels, unconditionally, regardless
// of what produced them. That content-agnostic-by-construction property
// (and the actual per-pixel proof that pixel data is overwritten, not just
// covered) is what `pdf_redaction_test.dart`'s "security regression suite"
// group directly verifies, at the layer where it's actually possible to
// prove.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_redact_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_redaction.dart';
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
    docsDir = await Directory.systemTemp.createTemp('pdf_redact_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 3, pageWidth: 400, pageHeight: 520)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  Future<PdfRedactController> pickedController() async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final controller = container.read(pdfRedactControllerProvider.notifier);
    await controller.pickPdf();
    return controller;
  }

  test('pickPdf loads every page with its real pixel dimensions (page dimensions preserved)', () async {
    await pickedController();
    final state = container.read(pdfRedactControllerProvider);

    expect(state.pages, hasLength(3));
    expect(state.pages.map((p) => p.pageIndex).toList(), [0, 1, 2]);
    for (final page in state.pages) {
      expect(page.width, 400);
      expect(page.height, 520);
      expect(page.jpegBytes, isNotEmpty);
    }
  });

  test('a single redaction region on one page (scenario 1)', () async {
    final controller = await pickedController();

    final id = controller.addRegion(0, const RedactionRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.2));

    final state = container.read(pdfRedactControllerProvider);
    expect(state.marksByPage[0], hasLength(1));
    expect(state.marksByPage[0]!.single.id, id);
    expect(state.totalRegionCount, 1);
  });

  test('multiple redaction regions on one page (scenario 2)', () async {
    final controller = await pickedController();

    controller.addRegion(0, const RedactionRegion(x: 0.05, y: 0.05, width: 0.2, height: 0.1));
    controller.addRegion(0, const RedactionRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.1));
    controller.addRegion(0, const RedactionRegion(x: 0.7, y: 0.7, width: 0.2, height: 0.1));

    final page0 = container.read(pdfRedactControllerProvider).marksByPage[0]!;
    expect(page0, hasLength(3));
    expect(page0.map((m) => m.id).toSet(), hasLength(3)); // every id distinct
  });

  test('redactions on multiple pages, each staying on its own page (scenario 3)', () async {
    final controller = await pickedController();

    controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1));
    controller.addRegion(1, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1));
    controller.addRegion(2, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1));

    final state = container.read(pdfRedactControllerProvider);
    expect(state.marksByPage[0]!.single.pageIndex, 0);
    expect(state.marksByPage[1]!.single.pageIndex, 1);
    expect(state.marksByPage[2]!.single.pageIndex, 2);
    expect(state.totalRegionCount, 3);
  });

  test('a redaction near a page boundary (scenario 4) does not throw and produces a valid PDF', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.0, y: 0.0, width: 0.15, height: 0.1));
    controller.addRegion(0, const RedactionRegion(x: 0.9, y: 0.92, width: 0.15, height: 0.15)); // extends past the edge

    final bytes = await controller.buildResultBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('a large redaction covering most of a page (scenario 5)', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.02, y: 0.02, width: 0.96, height: 0.96));

    final bytes = await controller.buildResultBytes();
    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('overlapping regions on the same page are each applied - the union is redacted, not just the last one added '
      '(scenario 14: multiple regions must not accidentally leave part of the selection exposed)', () async {
    // page index 1's fake synthetic color is (37,73,113) - not black -
    // so genuine pixel replacement is distinguishable from the background.
    final controller = await pickedController();
    controller.addRegion(1, const RedactionRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.3));
    controller.addRegion(1, const RedactionRegion(x: 0.3, y: 0.3, width: 0.3, height: 0.3)); // overlaps the first

    final regions = container.read(pdfRedactControllerProvider).marksByPage[1]!.map((m) => m.region).toList();
    // Directly exercise the same pixel-burn primitive the controller's
    // buildResultBytes() will run, to prove both regions actually take
    // effect (not just whichever was added last) - a synthetic page here
    // stands in for the real rasterized page purely to keep this a fast,
    // deterministic pixel check.
    final page = img.Image(width: 400, height: 520);
    img.fill(page, color: img.ColorRgb8(37, 73, 113));
    burnRedactions(page, regions, 400, 520);

    // A point only the first region covers, a point only the second
    // covers, and a point only their overlap covers - all three must be
    // burned for the union to be genuinely complete.
    expect(page.getPixel(60, 60).r, 0); // inside region 1 only
    expect(page.getPixel(220, 220).r, 0); // inside region 2 only
    expect(page.getPixel(140, 140).r, 0); // inside the overlap
    expect(page.getPixel(390, 10).r, 37); // untouched, far from both
  });

  test('updateRegion moves/resizes a region (move/resize before confirmation)', () async {
    final controller = await pickedController();
    final id = controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.1));

    controller.updateRegion(id, const RedactionRegion(x: 0.5, y: 0.6, width: 0.3, height: 0.2));

    final region = container.read(pdfRedactControllerProvider).marksByPage[0]!.single.region;
    expect(region.x, 0.5);
    expect(region.y, 0.6);
    expect(region.width, 0.3);
    expect(region.height, 0.2);
  });

  test('deleteRegion removes exactly the targeted region', () async {
    final controller = await pickedController();
    final keepId = controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.1, height: 0.1));
    final deleteId = controller.addRegion(0, const RedactionRegion(x: 0.5, y: 0.5, width: 0.1, height: 0.1));

    controller.deleteRegion(deleteId);

    final page0 = container.read(pdfRedactControllerProvider).marksByPage[0]!;
    expect(page0.map((m) => m.id), [keepId]);
  });

  test('undo reverts the most recent mutation', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.1, height: 0.1));
    controller.addRegion(0, const RedactionRegion(x: 0.5, y: 0.5, width: 0.1, height: 0.1));
    expect(container.read(pdfRedactControllerProvider).totalRegionCount, 2);

    controller.undo();

    expect(container.read(pdfRedactControllerProvider).totalRegionCount, 1);
  });

  test('the original PDF (source bytes) is never mutated by adding regions, previewing, or saving '
      '(scenario 9: original PDF remains unchanged)', () async {
    final controller = await pickedController();
    final originalBytes = Uint8List.fromList(container.read(pdfRedactControllerProvider).source!.bytes);

    controller.addRegion(0, const RedactionRegion(x: 0.2, y: 0.2, width: 0.3, height: 0.2));
    await controller.buildResultBytes(); // preview
    await controller.save();

    expect(container.read(pdfRedactControllerProvider).source!.bytes, equals(originalBytes));
  });

  test('save() writes a real PDF, inserts a Recent Files row with the correct page count '
      '(scenarios 10-11: resulting PDF opens successfully, page count remains correct)', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.3, height: 0.2));
    controller.addRegion(2, const RedactionRegion(x: 0.4, y: 0.4, width: 0.2, height: 0.2));

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.pageCount, 3);
    expect(await File(saved.outputPath).exists(), isTrue);
    final onDisk = await File(saved.outputPath).readAsBytes();
    expect(String.fromCharCodes(onDisk.take(5)), '%PDF-');
  });

  test('cancel (reset without saving) discards regions and writes nothing (scenario 15: save/cancel behavior)', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2));

    controller.reset();

    final state = container.read(pdfRedactControllerProvider);
    expect(state.isEmpty, isTrue);
    expect(state.totalRegionCount, 0);
    expect(state.savedFile, isNull);
  });

  test('previewing (buildResultBytes) does not write a file or insert a Recent Files row '
      '(scenario 16: preview does not modify the original / does not persist anything)', () async {
    final controller = await pickedController();
    controller.addRegion(0, const RedactionRegion(x: 0.1, y: 0.1, width: 0.2, height: 0.2));

    await controller.buildResultBytes();
    await controller.buildResultBytes(); // calling it again (re-opening Preview) is also side-effect-free

    expect(container.read(pdfRedactControllerProvider).savedFile, isNull);
    final rows = await SqfliteToolkitFileRepository(db).getAll();
    expect(rows, isEmpty);
  });
}
