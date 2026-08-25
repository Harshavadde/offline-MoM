// Tests ImageCompressController through a ProviderContainer with only the
// two leaf providers it reads - toolkitFileRepositoryProvider and
// toolkitImagePickerServiceProvider - overridden, mirroring
// notes_controller_test.dart's pattern. path_provider is faked the same way
// storage_providers_test.dart fakes it, since save() writes a real file via
// newToolkitOutputPath().
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/image_compress_providers.dart';
import 'package:offline_mom/features/student_toolkit/presentation/providers/toolkit_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/image_compression_service.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _syntheticPhotoBytes({int width = 400, int height = 300}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, (x ^ y) % 256);
    }
  }
  return img.encodeJpg(image, quality: 100);
}

void main() {
  late Database db;
  late Directory docsDir;
  late FakeToolkitImagePickerService pickerService;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    docsDir = await Directory.systemTemp.createTemp('image_compress_controller_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);
    pickerService = FakeToolkitImagePickerService();
    container = ProviderContainer(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(SqfliteToolkitFileRepository(db)),
        toolkitImagePickerServiceProvider.overrideWithValue(pickerService),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await docsDir.exists()) await docsDir.delete(recursive: true);
  });

  PickedToolkitImage picked({String fileName = 'photo.jpg'}) =>
      PickedToolkitImage(fileName: fileName, bytes: _syntheticPhotoBytes());

  test('starts empty, moves to ready after picking from gallery', () async {
    expect(container.read(imageCompressControllerProvider), isA<ImageCompressEmpty>());

    pickerService.galleryResult = picked();
    await container.read(imageCompressControllerProvider.notifier).pickFromGallery();

    expect(container.read(imageCompressControllerProvider), isA<ImageCompressReady>());
  });

  test('backing out of the picker (null result) leaves state empty', () async {
    pickerService.galleryResult = null;
    await container.read(imageCompressControllerProvider.notifier).pickFromGallery();

    expect(container.read(imageCompressControllerProvider), isA<ImageCompressEmpty>());
  });

  test('compress() moves ready -> done with a valid result', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();

    await controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);

    final state = container.read(imageCompressControllerProvider);
    expect(state, isA<ImageCompressDone>());
    expect((state as ImageCompressDone).result.bytes, isNotEmpty);
    expect(state.savedFile, isNull);
  });

  test('compress() on undecodable bytes moves ready -> error, not a crash',
      () async {
    pickerService.galleryResult =
        PickedToolkitImage(fileName: 'bad.jpg', bytes: Uint8List.fromList([1, 2, 3]));
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();

    await controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);

    final state = container.read(imageCompressControllerProvider);
    expect(state, isA<ImageCompressError>());
    expect((state as ImageCompressError).message, isNotEmpty);
  });

  test('save() writes the file, inserts a row, and is idempotent on a '
      'second call', () async {
    pickerService.galleryResult = picked(fileName: 'passport.jpg');
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();
    await controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.title, 'passport');
    expect(await File(saved.outputPath).exists(), isTrue);

    final rows = await SqfliteToolkitFileRepository(db).getAll();
    expect(rows, hasLength(1));

    final savedAgain = await controller.save();
    expect(savedAgain!.id, saved.id);
    final rowsAfterSecondSave = await SqfliteToolkitFileRepository(db).getAll();
    expect(rowsAfterSecondSave, hasLength(1));
  });

  test('save() invalidates toolkitFileListProvider', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();
    await controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);

    expect(await container.read(toolkitFileListProvider.future), isEmpty);
    await controller.save();
    expect(await container.read(toolkitFileListProvider.future), hasLength(1));
  });

  test('cancel() during processing returns to ready and discards the '
      'eventual compute() result (ADR-027 abandon semantics)', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();

    final future = controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);
    expect(container.read(imageCompressControllerProvider), isA<ImageCompressProcessing>());

    controller.cancel();
    expect(container.read(imageCompressControllerProvider), isA<ImageCompressReady>());

    await future;
    expect(container.read(imageCompressControllerProvider), isA<ImageCompressReady>());
  });

  test('reset() returns to empty regardless of prior state', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageCompressControllerProvider.notifier);
    await controller.pickFromGallery();
    await controller.compress(outputFormat: ImageOutputFormat.jpg, quality: 60);

    controller.reset();

    expect(container.read(imageCompressControllerProvider), isA<ImageCompressEmpty>());
  });
}
