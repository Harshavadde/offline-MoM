import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/audio_paths.dart';
import 'audio_import_service.dart';

/// [AudioImportService] implementation: `file_picker` for selecting a file,
/// `ffmpeg_kit_flutter_new` for stripping audio out of video files.
///
/// Extracted/copied audio always ends up encoded the same way the recorder
/// produces it (AAC-LC, 16kHz mono) so every meeting - recorded or imported -
/// flows through the exact same downstream (transcription) pipeline.
class FilePickerAudioImportService implements AudioImportService {
  static const audioExtensions = {'mp3', 'wav', 'm4a', 'aac'};
  static const videoExtensions = {'mp4', 'mkv', 'mov'};

  @override
  Future<String?> pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [...audioExtensions, ...videoExtensions],
      withData: false,
    );
    return result?.files.single.path;
  }

  @override
  Future<String> prepareAudioFile(String pickedFilePath) async {
    final extension = p
        .extension(pickedFilePath)
        .replaceFirst('.', '')
        .toLowerCase();
    final destinationPath = await newAudioFilePath();

    if (videoExtensions.contains(extension)) {
      final command =
          '-y -i "$pickedFilePath" -vn -acodec aac -ar 16000 -ac 1 "$destinationPath"';
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (returnCode == null || !ReturnCode.isSuccess(returnCode)) {
        throw AudioImportException(
          'Could not extract audio from this video (ffmpeg exit code: '
          '$returnCode).',
        );
      }
      return destinationPath;
    }

    if (audioExtensions.contains(extension)) {
      // Real-device QA finding: this copy was previously unguarded, unlike
      // the equivalent document-import path (document_import_service.dart)
      // - a raw FileSystemException (e.g. a full disk) propagated straight
      // through ImportController, which only catches AudioImportException,
      // leaving the Import screen stuck on its spinner forever with no
      // error shown.
      try {
        await File(pickedFilePath).copy(destinationPath);
      } on FileSystemException catch (e) {
        throw AudioImportException('Could not import this file: ${e.message}');
      }
      return destinationPath;
    }

    throw AudioImportException('Unsupported file type: .$extension');
  }
}
