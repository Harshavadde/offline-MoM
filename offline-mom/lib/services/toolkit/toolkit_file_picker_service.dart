import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

/// One PDF or image file the user picked from device storage for a PDF
/// Tool (not from the gallery/camera - `ToolkitImagePickerService` already
/// covers that for Image Tools/Scanner).
class PickedToolkitFile {
  const PickedToolkitFile({required this.fileName, required this.bytes});
  final String fileName;
  final Uint8List bytes;

  int get sizeBytes => bytes.lengthInBytes;
}

/// File-system PDF/image picking for PDF Tools (V2 Phase 5B) - a
/// toolkit-scoped wrapper over `file_picker`, mirroring
/// `ToolkitImagePickerService`'s existing precedent (services/toolkit/) of
/// wrapping a platform plugin behind this app's own boundary rather than
/// reusing `DocumentImportService` (that one is coupled to copying into
/// `Document`-owned storage and creating a `Document` row - a different,
/// heavier concern than PDF Tools' transient "read these bytes, process
/// them, throw the source away" need).
abstract class ToolkitFilePickerService {
  /// Null if the user backed out without choosing anything - not an error.
  Future<PickedToolkitFile?> pickPdf();

  /// Empty (not null) if the user backed out without choosing anything.
  Future<List<PickedToolkitFile>> pickMultiplePdfsOrImages();
}

class FilePickerToolkitFilePickerService implements ToolkitFilePickerService {
  static const _pdfExtensions = ['pdf'];
  static const _pdfAndImageExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  @override
  Future<PickedToolkitFile?> pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _pdfExtensions,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return null;
    return PickedToolkitFile(fileName: p.basename(path), bytes: await File(path).readAsBytes());
  }

  @override
  Future<List<PickedToolkitFile>> pickMultiplePdfsOrImages() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _pdfAndImageExtensions,
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return [];
    final picked = <PickedToolkitFile>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue;
      picked.add(PickedToolkitFile(fileName: file.name, bytes: await File(path).readAsBytes()));
    }
    return picked;
  }
}

/// A fake for widget/controller tests - mirrors
/// `FakeToolkitImagePickerService`'s identical reasoning (lives here, not
/// only in `test/`, as a documented first-class part of this service's own
/// contract).
class FakeToolkitFilePickerService implements ToolkitFilePickerService {
  FakeToolkitFilePickerService({this.pdfResult, this.multiResult = const []});

  PickedToolkitFile? pdfResult;
  List<PickedToolkitFile> multiResult;

  @override
  Future<PickedToolkitFile?> pickPdf() async => pdfResult;

  @override
  Future<List<PickedToolkitFile>> pickMultiplePdfsOrImages() async => multiResult;
}
