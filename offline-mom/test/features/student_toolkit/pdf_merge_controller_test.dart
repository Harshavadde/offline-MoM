import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/pdf_merge_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
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
    docsDir = await Directory.systemTemp.createTemp('pdf_merge_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitFilePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitFilePickerServiceProvider.overrideWithValue(pickerService),
        pdfPageRenderingServiceProvider
            .overrideWithValue(FakePdfPageRenderingService(pageCount: 2)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  test('addFiles builds up the queue; removeItem/reorderItem edit it in place',
      () async {
    pickerService.multiResult = [
      PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List(0)),
      PickedToolkitFile(fileName: 'b.pdf', bytes: Uint8List(0)),
    ];
    final controller = container.read(pdfMergeControllerProvider.notifier);

    await controller.addFiles();
    expect(container.read(pdfMergeControllerProvider).items, hasLength(2));

    final ids = container.read(pdfMergeControllerProvider).items.map((i) => i.id).toList();
    controller.reorderItem(0, 1);
    expect(
      container.read(pdfMergeControllerProvider).items.map((i) => i.id).toList(),
      [ids[1], ids[0]],
    );

    controller.removeItem(ids[0]);
    expect(container.read(pdfMergeControllerProvider).items, hasLength(1));
  });

  test('merging fewer than two files sets a friendly error', () async {
    pickerService.multiResult = [PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List(0))];
    final controller = container.read(pdfMergeControllerProvider.notifier);
    await controller.addFiles();

    await controller.merge();

    expect(container.read(pdfMergeControllerProvider).error, isNotNull);
    expect(container.read(pdfMergeControllerProvider).mergedBytes, isNull);
  });

  test('merge() then save() writes a real PDF with the combined page count',
      () async {
    pickerService.multiResult = [
      PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List(0)),
      PickedToolkitFile(fileName: 'b.pdf', bytes: Uint8List(0)),
    ];
    final controller = container.read(pdfMergeControllerProvider.notifier);
    await controller.addFiles();

    await controller.merge();
    expect(container.read(pdfMergeControllerProvider).mergedPageCount, 4); // 2 files x 2 pages

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.pageCount, 4);
    expect(await File(saved.outputPath).exists(), isTrue);
  });

  test('adding or removing a file after merging invalidates the merged '
      'bytes', () async {
    pickerService.multiResult = [
      PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List(0)),
      PickedToolkitFile(fileName: 'b.pdf', bytes: Uint8List(0)),
    ];
    final controller = container.read(pdfMergeControllerProvider.notifier);
    await controller.addFiles();
    await controller.merge();
    expect(container.read(pdfMergeControllerProvider).mergedBytes, isNotNull);

    pickerService.multiResult = [PickedToolkitFile(fileName: 'c.pdf', bytes: Uint8List(0))];
    await controller.addFiles();

    expect(container.read(pdfMergeControllerProvider).mergedBytes, isNull);
  });

  test('reset() clears the queue and any merged result', () async {
    pickerService.multiResult = [
      PickedToolkitFile(fileName: 'a.pdf', bytes: Uint8List(0)),
      PickedToolkitFile(fileName: 'b.pdf', bytes: Uint8List(0)),
    ];
    final controller = container.read(pdfMergeControllerProvider.notifier);
    await controller.addFiles();
    await controller.merge();

    controller.reset();

    final state = container.read(pdfMergeControllerProvider);
    expect(state.items, isEmpty);
    expect(state.mergedBytes, isNull);
  });
}
