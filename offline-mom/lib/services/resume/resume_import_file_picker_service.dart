import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../models/document.dart';

/// Thrown when a picked file can't be used as an import source (unsupported
/// extension, missing/unreadable file, empty file) - mirrors
/// [DocumentImportException]'s purpose for the Documents feature's own
/// import path.
class ResumeImportPickException implements Exception {
  ResumeImportPickException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One picked file, ready to be handed to a [DocumentTextExtractionService].
class PickedResumeImportFile {
  const PickedResumeImportFile({
    required this.filePath,
    required this.originalFilename,
    required this.sourceType,
    required this.fileSizeBytes,
  });

  final String filePath;
  final String originalFilename;
  final DocumentSourceType sourceType;
  final int fileSizeBytes;
}

/// File-system picking for Resume Import (PDF/DOCX/TXT/Markdown) - mirrors
/// `ToolkitFilePickerService`'s exact reasoning
/// (lib/services/toolkit/toolkit_file_picker_service.dart) for why this is
/// its own thin `file_picker` wrapper rather than reusing
/// `DocumentImportService`: an imported resume is a transient source ("read
/// it, structure it into the existing Resume model, discard the original
/// file") - it never becomes a stored [Document], so it doesn't belong in
/// Documents-owned storage the way [DocumentImportService.prepareDocumentFile]
/// assumes. The file is read directly from wherever the platform picker put
/// it; no permanent copy is made, since only the resulting structured
/// resume data is meant to persist (see the Batch 7 target flow: IMPORT ->
/// EXTRACT -> STRUCTURE -> EDIT -> REGENERATE - the original file is not a
/// step in that chain past EXTRACT).
abstract class ResumeImportFilePickerService {
  /// Opens a system file picker restricted to supported resume formats.
  /// Returns null if the user cancelled. Throws [ResumeImportPickException]
  /// for an unsupported extension, a missing file, or an empty file - the
  /// same validation [DocumentImportService.prepareDocumentFile] performs,
  /// checked here instead since this service never copies the file
  /// anywhere.
  Future<PickedResumeImportFile?> pickFile();
}

class FilePickerResumeImportFilePickerService implements ResumeImportFilePickerService {
  static const supportedExtensions = {'pdf', 'docx', 'txt', 'md'};

  @override
  Future<PickedResumeImportFile?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
      withData: false,
    );
    final pickedPath = result?.files.single.path;
    if (pickedPath == null) return null;

    final extension = p.extension(pickedPath).replaceFirst('.', '');
    final sourceType = DocumentSourceTypeMime.fromExtension(extension);
    if (sourceType == null) {
      throw ResumeImportPickException('Unsupported file type: .$extension');
    }

    final file = File(pickedPath);
    if (!await file.exists()) {
      throw ResumeImportPickException('The selected file could not be found.');
    }

    final fileSizeBytes = await file.length();
    if (fileSizeBytes == 0) {
      throw ResumeImportPickException('The selected file is empty.');
    }

    return PickedResumeImportFile(
      filePath: pickedPath,
      originalFilename: p.basename(pickedPath),
      sourceType: sourceType,
      fileSizeBytes: fileSizeBytes,
    );
  }
}

/// A fake for controller/widget tests - mirrors
/// `FakeToolkitFilePickerService`'s identical reasoning (lives here, not
/// only in `test/`, as a documented first-class part of this service's own
/// contract).
class FakeResumeImportFilePickerService implements ResumeImportFilePickerService {
  FakeResumeImportFilePickerService({this.result, this.errorToThrow});

  PickedResumeImportFile? result;
  Object? errorToThrow;

  @override
  Future<PickedResumeImportFile?> pickFile() async {
    if (errorToThrow != null) throw errorToThrow!;
    return result;
  }
}
