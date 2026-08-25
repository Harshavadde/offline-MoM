import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../models/document.dart';

/// Thrown when a picked file can't be used as a JD import source -
/// mirrors `ResumeImportPickException`'s exact purpose and shape
/// (lib/services/resume/resume_import_file_picker_service.dart).
class JdImportPickException implements Exception {
  JdImportPickException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// One picked JD file, ready to be handed to a
/// [DocumentTextExtractionService].
class PickedJdImportFile {
  const PickedJdImportFile({
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

/// File-system picking for Job Description import (PDF/DOCX/TXT/Markdown) -
/// mirrors `ResumeImportFilePickerService`'s exact shape and reasoning
/// (lib/services/resume/resume_import_file_picker_service.dart): a
/// transient source (read it, structure it, discard the original - a JD is
/// never persisted, see the Batch 8 report for why) gets its own thin
/// `file_picker` wrapper rather than reusing `DocumentImportService`'s
/// Documents-owned-storage-copying flow.
abstract class JdImportFilePickerService {
  /// Opens a system file picker restricted to supported JD formats.
  /// Returns null if the user cancelled. Throws [JdImportPickException]
  /// for an unsupported extension, a missing file, or an empty file.
  Future<PickedJdImportFile?> pickFile();
}

class FilePickerJdImportFilePickerService implements JdImportFilePickerService {
  static const supportedExtensions = {'pdf', 'docx', 'txt', 'md'};

  @override
  Future<PickedJdImportFile?> pickFile() async {
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
      throw JdImportPickException('Unsupported file type: .$extension');
    }

    final file = File(pickedPath);
    if (!await file.exists()) {
      throw JdImportPickException('The selected file could not be found.');
    }

    final fileSizeBytes = await file.length();
    if (fileSizeBytes == 0) {
      throw JdImportPickException('The selected file is empty.');
    }

    return PickedJdImportFile(
      filePath: pickedPath,
      originalFilename: p.basename(pickedPath),
      sourceType: sourceType,
      fileSizeBytes: fileSizeBytes,
    );
  }
}

/// A fake for controller/widget tests - mirrors
/// `FakeResumeImportFilePickerService`'s identical reasoning.
class FakeJdImportFilePickerService implements JdImportFilePickerService {
  FakeJdImportFilePickerService({this.result, this.errorToThrow});

  PickedJdImportFile? result;
  Object? errorToThrow;

  @override
  Future<PickedJdImportFile?> pickFile() async {
    if (errorToThrow != null) throw errorToThrow!;
    return result;
  }
}
