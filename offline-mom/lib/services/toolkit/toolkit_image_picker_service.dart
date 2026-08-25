import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// One image the user picked/captured - already read into memory (the
/// source file itself is wherever `image_picker` put it, outside this
/// app's control/ownership - see `toolkit_paths.dart`'s doc comment).
class PickedToolkitImage {
  const PickedToolkitImage({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;

  int get sizeBytes => bytes.lengthInBytes;
}

/// Gallery pick + camera capture for the Student Toolkit (V2 Phase 5A) -
/// an interface (not a direct `ImagePicker` dependency in controllers)
/// mirroring `RecorderService`/`AudioPlayerService`'s existing precedent
/// (services/audio/) for wrapping a platform plugin behind this app's own
/// boundary, so controllers stay testable without a real device/plugin.
abstract class ToolkitImagePickerService {
  /// Null if the user backed out of the picker without choosing anything -
  /// not an error.
  Future<PickedToolkitImage?> pickFromGallery();

  /// Null if the user backed out of the camera without capturing anything -
  /// not an error.
  Future<PickedToolkitImage?> captureFromCamera();

  /// Multi-select gallery import (V2 Phase 5B, Scanner's "Gallery Import" -
  /// picking several existing photos of a multi-page document at once
  /// rather than one at a time). Empty (not null) if the user backed out
  /// without choosing anything - matches `pickMultiImage`'s own contract of
  /// never returning null, only a possibly-empty list.
  Future<List<PickedToolkitImage>> pickMultipleFromGallery();
}

class ImagePickerToolkitImagePickerService implements ToolkitImagePickerService {
  ImagePickerToolkitImagePickerService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<PickedToolkitImage?> _fromXFile(XFile? file) async {
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedToolkitImage(fileName: file.name, bytes: bytes);
  }

  @override
  Future<PickedToolkitImage?> pickFromGallery() async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    return _fromXFile(file);
  }

  @override
  Future<PickedToolkitImage?> captureFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera);
    return _fromXFile(file);
  }

  @override
  Future<List<PickedToolkitImage>> pickMultipleFromGallery() async {
    final files = await _picker.pickMultiImage();
    final results = <PickedToolkitImage>[];
    for (final file in files) {
      final picked = await _fromXFile(file);
      if (picked != null) results.add(picked);
    }
    return results;
  }
}

/// A fake for widget/controller tests - returns fixed, pre-supplied images
/// (or nulls) instead of ever touching a real gallery/camera, since neither
/// exists under `flutter test`. Lives here (not in `test/`) so it can be a
/// documented, first-class part of this service's own contract, mirroring
/// `FakeLlmEngine`/`FakeEmbeddingEngine`'s existing precedent
/// (test/test_helpers/fake_ai_engines.dart) of fakes shipping alongside
/// the interface they implement - unlike those, this one is trivial enough
/// (two fixed-return methods, no state machine) that it doesn't need its
/// own dedicated test-helpers file.
class FakeToolkitImagePickerService implements ToolkitImagePickerService {
  FakeToolkitImagePickerService({
    this.galleryResult,
    this.cameraResult,
    this.multiGalleryResult = const [],
  });

  PickedToolkitImage? galleryResult;
  PickedToolkitImage? cameraResult;
  List<PickedToolkitImage> multiGalleryResult;

  @override
  Future<PickedToolkitImage?> pickFromGallery() async => galleryResult;

  @override
  Future<PickedToolkitImage?> captureFromCamera() async => cameraResult;

  @override
  Future<List<PickedToolkitImage>> pickMultipleFromGallery() async => multiGalleryResult;
}
