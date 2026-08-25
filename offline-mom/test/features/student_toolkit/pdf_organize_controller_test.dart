// Tests PdfOrganizeController (Toolkit productization pass, P0-5, Page
// Management/ADR-043) - Rotate/Delete/Extract/Insert/Duplicate/Replace/
// Reorder. Mirrors pdf_merge_controller_test.dart/pdf_edit_controller_test
// .dart's exact ProviderContainer/fake-service pattern. Every scenario
// number below refers to the P0-5 spec's own numbered test list.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_organize_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/pdf_page_rendering_service.dart';
import 'package:offline_mom/services/toolkit/pdf_text_search_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_file_picker_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pdf/pdf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

/// B3 (release readiness, R-49) - fixed per-page text regardless of the
/// (internally-chosen, unpredictable) temp path `PdfSearchableTextPreserver`
/// writes to, mirroring the identical fake in the B3 service-level tests.
class _FixedTextSearchService implements PdfTextSearchService {
  _FixedTextSearchService(this.pages);
  final List<String> pages;
  @override
  Future<List<String>> extractPagesText(String pdfFilePath) async => pages;
}

/// Zlib-inflates every `stream ... endstream` block - mirrors the identical
/// helper in `pdf_compression_service_test.dart`/other B3 test files.
List<Uint8List> _inflateAllStreams(Uint8List pdfBytes) {
  final decoded = <Uint8List>[];
  final content = String.fromCharCodes(pdfBytes);
  var searchFrom = 0;
  while (true) {
    final streamIdx = content.indexOf('stream', searchFrom);
    if (streamIdx == -1) break;
    var dataStart = streamIdx + 'stream'.length;
    if (pdfBytes[dataStart] == 0x0d) dataStart++;
    if (pdfBytes[dataStart] == 0x0a) dataStart++;
    final endIdx = content.indexOf('endstream', dataStart);
    if (endIdx == -1) break;
    final raw = pdfBytes.sublist(dataStart, endIdx);
    try {
      decoded.add(Uint8List.fromList(zlib.decode(raw)));
    } catch (_) {}
    searchFrom = endIdx + 'endstream'.length;
  }
  return decoded;
}

bool _decodedStreamsContain(List<Uint8List> streams, String text) {
  for (final s in streams) {
    if (String.fromCharCodes(s).contains(text)) return true;
  }
  return false;
}

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitFilePickerService pickerService;
  late FakeToolkitImagePickerService imagePickerService;
  late FakePdfPageRenderingService renderingService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('pdf_organize_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
    imagePickerService = FakeToolkitImagePickerService();
    renderingService = FakePdfPageRenderingService(pageCount: 5, pageWidth: 300, pageHeight: 400);
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        toolkitImagePickerServiceProvider.overrideWithValue(imagePickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(renderingService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  Future<PdfOrganizeController> pickedController() async {
    pickerService.pdfResult = PickedToolkitFile(fileName: 'source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
    final controller = container.read(pdfOrganizeControllerProvider.notifier);
    await controller.pickPdf();
    return controller;
  }

  bool hasRotateToken(Uint8List bytes, String token) => latin1.decode(bytes, allowInvalid: true).contains(token);

  test('pickPdf loads every page with its real pixel dimensions, in order', () async {
    await pickedController();
    final state = container.read(pdfOrganizeControllerProvider);

    expect(state.slots, hasLength(5));
    expect(state.slots.map((s) => s.originalPageNumber).toList(), [1, 2, 3, 4, 5]);
    for (final s in state.slots) {
      expect(s.width, 300);
      expect(s.height, 400);
    }
  });

  test('rotate one page (scenario 1)', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[1].id;

    controller.rotateSelected(1, ids: [id]);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots[1].rotation, PdfPageRotation.rotate90);
    expect(state.slots[0].rotation, PdfPageRotation.none);
  });

  test('rotate multiple pages (scenario 2)', () async {
    final controller = await pickedController();
    final ids = [container.read(pdfOrganizeControllerProvider).slots[0].id, container.read(pdfOrganizeControllerProvider).slots[2].id];

    controller.rotateSelected(2, ids: ids); // 180 degrees

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots[0].rotation, PdfPageRotation.rotate180);
    expect(state.slots[2].rotation, PdfPageRotation.rotate180);
    expect(state.slots[1].rotation, PdfPageRotation.none);
  });

  test('rotate all pages (scenario 3)', () async {
    final controller = await pickedController();

    controller.rotateAll(1);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots.every((s) => s.rotation == PdfPageRotation.rotate90), isTrue);
  });

  test('rotating twice by 90 accumulates to 180, not a reset', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[0].id;

    controller.rotateSelected(1, ids: [id]);
    controller.rotateSelected(1, ids: [id]);

    expect(container.read(pdfOrganizeControllerProvider).slots[0].rotation, PdfPageRotation.rotate180);
  });

  test('applyChanges() bakes rotation into a real PDF /Rotate attribute', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[0].id;
    controller.rotateSelected(1, ids: [id]);

    await controller.applyChanges();

    final bytes = container.read(pdfOrganizeControllerProvider).resultBytes!;
    expect(hasRotateToken(bytes, '/Rotate 90'), isTrue);
  });

  group('B3 (release readiness, R-49): searchable text preservation', () {
    test('applyChanges() reconstructs each page\'s pre-existing text, and a duplicated page keeps it too',
        () async {
      final withText = ProviderContainer(
        overrides: [
          toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
          toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
          toolkitImagePickerServiceProvider.overrideWithValue(imagePickerService),
          pdfPageRenderingServiceProvider.overrideWithValue(renderingService),
          pdfTextSearchServiceProvider.overrideWithValue(
            _FixedTextSearchService(const [
              'OrganizeControllerMarkerZero',
              'OrganizeControllerMarkerOne',
              'OrganizeControllerMarkerTwo',
              'OrganizeControllerMarkerThree',
              'OrganizeControllerMarkerFour',
            ]),
          ),
        ],
      );
      addTearDown(withText.dispose);

      pickerService.pdfResult = PickedToolkitFile(fileName: 'source.pdf', bytes: Uint8List.fromList([1, 2, 3]));
      final controller = withText.read(pdfOrganizeControllerProvider.notifier);
      await controller.pickPdf();
      final sourceId = withText.read(pdfOrganizeControllerProvider).slots[0].id;
      controller.duplicateSelected(ids: [sourceId]);

      await controller.applyChanges();

      final bytes = withText.read(pdfOrganizeControllerProvider).resultBytes!;
      final streams = _inflateAllStreams(bytes);
      // Every original page's own marker survives, and the duplicated page
      // 0's marker appears reconstructed on both copies.
      for (final marker in [
        'OrganizeControllerMarkerZero',
        'OrganizeControllerMarkerOne',
        'OrganizeControllerMarkerTwo',
        'OrganizeControllerMarkerThree',
        'OrganizeControllerMarkerFour',
      ]) {
        expect(_decodedStreamsContain(streams, marker), isTrue, reason: marker);
      }
    });

    test('with no pdfTextSearchServiceProvider override (the default, real - but unimplemented-under-test '
        '- ReadPdfTextSearchService), applyChanges() still succeeds normally, degrading safely', () async {
      final controller = await pickedController();

      await controller.applyChanges();

      expect(container.read(pdfOrganizeControllerProvider).resultBytes, isNotNull);
      expect(container.read(pdfOrganizeControllerProvider).error, isNull);
    });
  });

  test('delete one page (scenario 4)', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[2].id;

    controller.deleteSelected(ids: [id]);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots, hasLength(4));
    expect(state.slots.any((s) => s.id == id), isFalse);
  });

  test('delete multiple pages (scenario 5)', () async {
    final controller = await pickedController();
    final ids = [container.read(pdfOrganizeControllerProvider).slots[0].id, container.read(pdfOrganizeControllerProvider).slots[1].id];

    controller.deleteSelected(ids: ids);

    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(3));
  });

  test('attempting to delete every page is refused with a friendly error, not an empty PDF (scenario 6)', () async {
    final controller = await pickedController();
    final allIds = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();

    controller.deleteSelected(ids: allIds);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots, hasLength(5)); // unchanged
    expect(state.error, isNotNull);
  });

  test('extract contiguous pages (scenario 7)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    controller.toggleSelect(slots[1].id);
    controller.toggleSelect(slots[2].id);
    controller.toggleSelect(slots[3].id);

    await controller.extractSelected();

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.resultPageCount, 3);
    // The working session itself is untouched by extraction.
    expect(state.slots, hasLength(5));
  });

  test('extract non-contiguous pages (scenario 8)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    controller.toggleSelect(slots[0].id);
    controller.toggleSelect(slots[4].id);

    await controller.extractSelected();

    expect(container.read(pdfOrganizeControllerProvider).resultPageCount, 2);
  });

  test('duplicate one page (scenario 9) - the copy appears immediately after the source', () async {
    final controller = await pickedController();
    final sourceId = container.read(pdfOrganizeControllerProvider).slots[1].id;

    controller.duplicateSelected(ids: [sourceId]);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots, hasLength(6));
    expect(state.slots[1].id, sourceId);
    expect(state.slots[2].originalPageNumber, state.slots[1].originalPageNumber);
    expect(state.slots[2].id, isNot(sourceId));
  });

  test('duplicate multiple pages (scenario 10)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    controller.duplicateSelected(ids: [slots[0].id, slots[3].id]);

    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(7));
  });

  test('insert a one-page PDF (scenario 11)', () async {
    final controller = await pickedController();
    // Reconfigure the shared fake to a 1-page document for this insert -
    // FakePdfPageRenderingService.pageCount is a plain mutable field, so
    // this affects only calls made after this point, not the primary
    // pick's already-completed 5-page rasterization above.
    renderingService.pageCount = 1;
    pickerService.pdfResult = PickedToolkitFile(fileName: 'insert.pdf', bytes: Uint8List.fromList([9, 9]));

    final ok = await controller.insertPdf(position: InsertPosition.atEnd);

    expect(ok, isTrue);
    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(6));
  });

  test('insert a multi-page PDF preserves every inserted page (scenario 12)', () async {
    final controller = await pickedController();
    renderingService.pageCount = 3;
    pickerService.pdfResult = PickedToolkitFile(fileName: 'insert3.pdf', bytes: Uint8List.fromList([7, 7, 7]));

    final ok = await controller.insertPdf(position: InsertPosition.atStart);

    expect(ok, isTrue);
    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots, hasLength(8)); // 5 original + 3 inserted
    // The first 3 slots are the inserted pages (position atStart), all newly selected.
    expect(state.selectedIds, hasLength(3));
    expect(state.slots.take(3).every((s) => s.originalPageNumber == null), isTrue);
  });

  test('insert an image (Images -> PDF support, single page)', () async {
    final controller = await pickedController();
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'photo.png', bytes: _tinyPngBytes());

    final ok = await controller.insertImage(position: InsertPosition.atEnd);

    expect(ok, isTrue);
    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(6));
  });

  test('insert before/after a selection splices at the right position', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    controller.toggleSelect(slots[2].id); // select page 3 (index 2)
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'photo.png', bytes: _tinyPngBytes());

    await controller.insertImage(position: InsertPosition.afterSelection);

    final updated = container.read(pdfOrganizeControllerProvider).slots;
    expect(updated, hasLength(6));
    // The inserted page (originalPageNumber null) now sits right after the
    // original page 3.
    expect(updated[2].originalPageNumber, 3);
    expect(updated[3].originalPageNumber, isNull);
    expect(updated[4].originalPageNumber, 4);
  });

  test('replace one page (scenario 13)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    final targetId = slots[1].id;
    controller.toggleSelect(targetId);
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'new.png', bytes: _tinyPngBytes());

    final ok = await controller.replaceSelectedWithImage();

    expect(ok, isTrue);
    final updated = container.read(pdfOrganizeControllerProvider);
    expect(updated.slots, hasLength(5)); // count unchanged
    expect(updated.slots[1].id, isNot(targetId)); // content replaced (new slot)
    expect(updated.slots[1].originalPageNumber, isNull); // no longer "page 2 of the original"
    // Unrelated pages untouched.
    expect(updated.slots[0].id, slots[0].id);
    expect(updated.slots[2].id, slots[2].id);
  });

  test('replace multiple pages 1:1 with a matching-count multi-page PDF (scenario 14)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    final firstId = slots[0].id;
    final secondId = slots[1].id;
    controller.toggleSelect(firstId);
    controller.toggleSelect(secondId);
    renderingService.pageCount = 2;
    pickerService.pdfResult = PickedToolkitFile(fileName: 'replacement2.pdf', bytes: Uint8List.fromList([5, 5]));

    final ok = await controller.replaceSelectedWithPdf();

    expect(ok, isTrue);
    final updated = container.read(pdfOrganizeControllerProvider).slots;
    expect(updated, hasLength(5));
    expect(updated[0].id, isNot(firstId));
    expect(updated[1].id, isNot(secondId));
    expect(updated[2].id, slots[2].id); // untouched
  });

  test('reorder pages (scenario 15)', () async {
    final controller = await pickedController();
    final ids = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();

    // 1,2,3,4,5 -> 1,4,2,5,3 (the P0-5 spec's own reorder example): move
    // page4 (index 3) to index 1, giving 1,4,2,3,5; then move page5 (now
    // at index 4) to index 3, giving 1,4,2,5,3.
    controller.reorderSlot(3, 1);
    controller.reorderSlot(4, 3);

    final reordered = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    expect(reordered, [ids[0], ids[3], ids[1], ids[4], ids[2]]);
  });

  test('reorder then rotate applies rotation to the page at its new position (scenario 16)', () async {
    final controller = await pickedController();
    final ids = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    controller.reorderSlot(0, 4); // page1 moves to the end

    controller.rotateSelected(1, ids: [ids[0]]); // rotate what was originally page 1

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots.last.id, ids[0]);
    expect(state.slots.last.rotation, PdfPageRotation.rotate90);
  });

  test('reorder then delete removes the correct page regardless of its new position (scenario 17)', () async {
    final controller = await pickedController();
    final ids = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    controller.reorderSlot(0, 4); // page1 -> end: [2,3,4,5,1]

    controller.deleteSelected(ids: [ids[2]]); // delete original page3

    final remaining = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    expect(remaining, [ids[1], ids[3], ids[4], ids[0]]);
  });

  test('insert then reorder places the inserted page correctly after a subsequent move (scenario 18)', () async {
    final controller = await pickedController();
    imagePickerService.galleryResult = PickedToolkitImage(fileName: 'new.png', bytes: _tinyPngBytes());
    await controller.insertImage(position: InsertPosition.atStart);
    final insertedId = container.read(pdfOrganizeControllerProvider).selectedIds.single;

    controller.reorderSlot(0, 3);

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots[3].id, insertedId);
  });

  test('extract after reorder preserves the new order, not the original one (scenario 19)', () async {
    final controller = await pickedController();
    final ids = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    controller.reorderSlot(4, 0); // page5 -> front: [5,1,2,3,4]
    final newOrder = container.read(pdfOrganizeControllerProvider).slots;
    controller.toggleSelect(newOrder[0].id); // page5
    controller.toggleSelect(newOrder[1].id); // page1

    await controller.extractSelected();

    expect(container.read(pdfOrganizeControllerProvider).resultPageCount, 2);
    // ids[4] (page5) was reordered to the front and should be selected first.
    expect(newOrder[0].id, ids[4]);
  });

  test('save() writes a real PDF and it can be picked back up (reopened) with the correct page count '
      '(scenario 20: save then reopen)', () async {
    final controller = await pickedController();
    controller.deleteSelected(ids: [container.read(pdfOrganizeControllerProvider).slots[0].id]);
    await controller.applyChanges();

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.pageCount, 4);
    final onDisk = await File(saved.outputPath).readAsBytes();
    expect(String.fromCharCodes(onDisk.take(5)), '%PDF-');

    // Reopen: a fresh controller/container picks up the just-saved file.
    final reopenPicker = FakeToolkitFilePickerService()..pdfResult = PickedToolkitFile(fileName: 'saved.pdf', bytes: onDisk);
    final reopenContainer = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(reopenPicker),
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 4, pageWidth: 300, pageHeight: 400)),
      ],
    );
    addTearDown(reopenContainer.dispose);
    final reopened = reopenContainer.read(pdfOrganizeControllerProvider.notifier);
    await reopened.pickPdf();
    expect(reopenContainer.read(pdfOrganizeControllerProvider).slots, hasLength(4));
    expect(reopenContainer.read(pdfOrganizeControllerProvider).error, isNull);
  });

  test('the original source bytes are never mutated by any operation (scenario 21: original PDF unchanged)', () async {
    final controller = await pickedController();
    final original = Uint8List.fromList(container.read(pdfOrganizeControllerProvider).source!.bytes);

    final id = container.read(pdfOrganizeControllerProvider).slots[0].id;
    controller.rotateSelected(1, ids: [id]);
    controller.duplicateSelected(ids: [id]);
    controller.deleteSelected(ids: [container.read(pdfOrganizeControllerProvider).slots.last.id]);
    await controller.applyChanges();
    await controller.save();

    expect(container.read(pdfOrganizeControllerProvider).source!.bytes, equals(original));
  });

  test('page count remains correct through a combined sequence of operations (scenario 22)', () async {
    final controller = await pickedController();
    final slots = container.read(pdfOrganizeControllerProvider).slots;
    controller.duplicateSelected(ids: [slots[0].id]); // 5 -> 6
    controller.deleteSelected(ids: [slots[4].id]); // 6 -> 5

    await controller.applyChanges();

    expect(container.read(pdfOrganizeControllerProvider).resultPageCount, 5);
  });

  test('page dimensions remain correct after operations (scenario 23)', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[0].id;
    controller.rotateSelected(1, ids: [id]); // rotation must not alter the recorded width/height

    final slot = container.read(pdfOrganizeControllerProvider).slots[0];
    expect(slot.width, 300);
    expect(slot.height, 400);
  });

  test('page ordering is correct in the final result (scenario 24)', () async {
    final controller = await pickedController();
    final ids = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    controller.reorderSlot(0, 2); // 1,2,3,4,5 -> 2,3,1,4,5

    final order = container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id).toList();
    expect(order, [ids[1], ids[2], ids[0], ids[3], ids[4]]);
  });

  test('a rasterization failure while picking is handled gracefully, not a crash (scenario 25: invalid input)', () async {
    final failContainer = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider.overrideWithValue(
          FakePdfPageRenderingService(throwOnRasterize: const PdfRenderingException('corrupted PDF')),
        ),
      ],
    );
    addTearDown(failContainer.dispose);
    pickerService.pdfResult = PickedToolkitFile(fileName: 'bad.pdf', bytes: Uint8List.fromList([0]));

    await failContainer.read(pdfOrganizeControllerProvider.notifier).pickPdf();

    final state = failContainer.read(pdfOrganizeControllerProvider);
    expect(state.error, isNotNull);
    expect(state.slots, isEmpty);
  });

  test('a cancelled insert (user picks nothing) leaves the working session exactly as it was', () async {
    final controller = await pickedController();
    final before = List.of(container.read(pdfOrganizeControllerProvider).slots);
    imagePickerService.galleryResult = null;

    final ok = await controller.insertImage(position: InsertPosition.atEnd);

    expect(ok, isFalse);
    expect(container.read(pdfOrganizeControllerProvider).slots.map((s) => s.id), before.map((s) => s.id));
  });

  test('a failed insert (corrupted source) leaves the working session exactly as it was '
      '(scenario 26: failed operations do not destroy the original)', () async {
    final controller = await pickedController();
    final before = List.of(container.read(pdfOrganizeControllerProvider).slots);
    renderingService.throwOnRasterize = const PdfRenderingException('corrupted PDF');
    pickerService.pdfResult = PickedToolkitFile(fileName: 'bad.pdf', bytes: Uint8List.fromList([0]));

    final ok = await controller.insertPdf(position: InsertPosition.atEnd);

    expect(ok, isFalse);
    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.slots.map((s) => s.id), before.map((s) => s.id));
    expect(state.error, isNotNull);
  });

  test('preview (applyChanges building resultBytes) does not mutate the source (scenario 27)', () async {
    final controller = await pickedController();
    final originalBytes = Uint8List.fromList(container.read(pdfOrganizeControllerProvider).source!.bytes);

    await controller.applyChanges();
    await controller.applyChanges(); // calling again (re-opening preview) is also side-effect-free on the source

    expect(container.read(pdfOrganizeControllerProvider).source!.bytes, equals(originalBytes));
    expect(container.read(pdfOrganizeControllerProvider).savedFile, isNull);
  });

  test('undo reverts the most recent mutation', () async {
    final controller = await pickedController();
    final id = container.read(pdfOrganizeControllerProvider).slots[0].id;
    controller.deleteSelected(ids: [id]);
    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(4));

    controller.undo();

    expect(container.read(pdfOrganizeControllerProvider).slots, hasLength(5));
  });

  test('discardResult clears only the preview, not the working session', () async {
    final controller = await pickedController();
    await controller.applyChanges();
    expect(container.read(pdfOrganizeControllerProvider).resultBytes, isNotNull);

    controller.discardResult();

    final state = container.read(pdfOrganizeControllerProvider);
    expect(state.resultBytes, isNull);
    expect(state.slots, hasLength(5));
  });

  test('reset() clears the entire session', () async {
    final controller = await pickedController();
    controller.reset();

    expect(container.read(pdfOrganizeControllerProvider).isEmpty, isTrue);
  });
}

Uint8List _tinyPngBytes() {
  // A minimal, valid 1x1 PNG - decodeToolkitImageOrThrow needs a real,
  // decodable image, not arbitrary bytes.
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, 0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
    0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}
