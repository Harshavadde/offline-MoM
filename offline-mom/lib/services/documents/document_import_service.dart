import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/document_paths.dart';
import '../../models/document.dart';

/// Thrown when a picked file can't be turned into a usable, stored
/// document (unsupported extension, copy failure) - mirrors
/// [AudioImportException]'s purpose for the meeting-import path.
class DocumentImportException implements Exception {
  DocumentImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The result of successfully copying a picked file into app storage -
/// everything [DocumentImportUseCase] needs to create the [Document] row,
/// gathered in one place rather than re-derived by the use case.
class PreparedDocumentFile {
  const PreparedDocumentFile({
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

/// Contract for turning a user-picked PDF/DOCX/TXT/Markdown file into a
/// document living in the app's own storage, ready for text extraction -
/// mirrors [AudioImportService]'s shape exactly.
abstract class DocumentImportService {
  /// Opens a system file picker restricted to supported document formats.
  /// Returns null if the user cancelled.
  Future<String?> pickFile();

  /// Given a picked file's path, copies it into app storage and returns
  /// everything needed to create its [Document] row. Throws
  /// [DocumentImportException] for an unsupported extension or a copy
  /// failure.
  Future<PreparedDocumentFile> prepareDocumentFile(String pickedFilePath);
}

class FilePickerDocumentImportService implements DocumentImportService {
  static const supportedExtensions = {'pdf', 'docx', 'txt', 'md'};

  @override
  Future<String?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions.toList(),
      withData: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<PreparedDocumentFile> prepareDocumentFile(String pickedFilePath) async {
    final extension = p.extension(pickedFilePath).replaceFirst('.', '').toLowerCase();
    final sourceType = DocumentSourceTypeMime.fromExtension(extension);
    if (sourceType == null) {
      throw DocumentImportException('Unsupported file type: .$extension');
    }

    final sourceFile = File(pickedFilePath);
    if (!await sourceFile.exists()) {
      throw DocumentImportException('The selected file could not be found.');
    }

    final originalFilename = p.basename(pickedFilePath);
    final fileSizeBytes = await sourceFile.length();
    final destinationPath = await newDocumentFilePath(extension);

    try {
      await sourceFile.copy(destinationPath);
    } on FileSystemException catch (e) {
      throw DocumentImportException('Could not import this file: ${e.message}');
    }

    return PreparedDocumentFile(
      filePath: destinationPath,
      originalFilename: originalFilename,
      sourceType: sourceType,
      fileSizeBytes: fileSizeBytes,
    );
  }
}
