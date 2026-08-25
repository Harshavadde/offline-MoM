// Mirrors image_compress_controller_test.dart's setup exactly, adapted for
// ImageResizeController - same leaf-provider-override pattern, same faked
// path_provider for save()'s real file write.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/providers/image_resize_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/image_resize_service.dart';
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
    docsDir = await Directory.systemTemp.createTemp('image_resize_controller_test_');
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

  PickedToolkitImage picked({String fileName = 'notes.png'}) =>
      PickedToolkitImage(fileName: fileName, bytes: _syntheticPhotoBytes());

  test('starts empty, moves to ready after capturing from camera', () async {
    pickerService.cameraResult = picked();
    await container.read(imageResizeControllerProvider.notifier).captureFromCamera();

    expect(container.read(imageResizeControllerProvider), isA<ImageResizeReady>());
  });

  test('resize() by percentage moves ready -> done with a smaller image',
      () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageResizeControllerProvider.notifier);
    await controller.pickFromGallery();

    await controller.resize(
      mode: ImageResizeMode.percentage,
      outputFormat: ImageResizeOutputFormat.jpg,
      percentage: 50,
    );

    final state = container.read(imageResizeControllerProvider);
    expect(state, isA<ImageResizeDone>());
    final result = (state as ImageResizeDone).result;
    expect(result.width, 200);
    expect(result.height, 150);
  });

  test('resize() on undecodable bytes moves ready -> error, not a crash',
      () async {
    pickerService.galleryResult =
        PickedToolkitImage(fileName: 'bad.png', bytes: Uint8List.fromList([9, 9, 9]));
    final controller = container.read(imageResizeControllerProvider.notifier);
    await controller.pickFromGallery();

    await controller.resize(
      mode: ImageResizeMode.percentage,
      outputFormat: ImageResizeOutputFormat.jpg,
      percentage: 50,
    );

    expect(container.read(imageResizeControllerProvider), isA<ImageResizeError>());
  });

  test('save() writes the file, inserts a row, and is idempotent', () async {
    pickerService.galleryResult = picked(fileName: 'diagram.png');
    final controller = container.read(imageResizeControllerProvider.notifier);
    await controller.pickFromGallery();
    await controller.resize(
      mode: ImageResizeMode.width,
      outputFormat: ImageResizeOutputFormat.png,
      targetWidth: 100,
    );

    final saved = await controller.save();

    expect(saved, isNotNull);
    expect(saved!.title, 'diagram');
    expect(await File(saved.outputPath).exists(), isTrue);

    final saveAgain = await controller.save();
    expect(saveAgain!.id, saved.id);
    expect(await SqfliteToolkitFileRepository(db).getAll(), hasLength(1));
  });

  test('cancel() during processing returns to ready and discards the '
      'eventual compute() result', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageResizeControllerProvider.notifier);
    await controller.pickFromGallery();

    final future = controller.resize(
      mode: ImageResizeMode.percentage,
      outputFormat: ImageResizeOutputFormat.jpg,
      percentage: 50,
    );
    expect(container.read(imageResizeControllerProvider), isA<ImageResizeProcessing>());

    controller.cancel();
    expect(container.read(imageResizeControllerProvider), isA<ImageResizeReady>());

    await future;
    expect(container.read(imageResizeControllerProvider), isA<ImageResizeReady>());
  });

  test('reset() returns to empty regardless of prior state', () async {
    pickerService.galleryResult = picked();
    final controller = container.read(imageResizeControllerProvider.notifier);
    await controller.pickFromGallery();
    await controller.resize(
      mode: ImageResizeMode.percentage,
      outputFormat: ImageResizeOutputFormat.jpg,
      percentage: 50,
    );

    controller.reset();

    expect(container.read(imageResizeControllerProvider), isA<ImageResizeEmpty>());
  });
}
