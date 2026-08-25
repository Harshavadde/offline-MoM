/// Thrown when a picked file can't be turned into a usable audio file
/// (e.g. ffmpeg extraction failed).
class AudioImportException implements Exception {
  AudioImportException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Contract for turning a user-picked audio/video file into an audio file
/// living in the app's own storage, ready for transcription.
abstract class AudioImportService {
  /// Opens a system file picker restricted to supported audio/video
  /// formats. Returns null if the user cancelled.
  Future<String?> pickFile();

  /// Given a picked file's path, returns a path to a ready-to-use audio
  /// file in app storage - video files have their audio extracted, audio
  /// files are copied in as-is.
  Future<String> prepareAudioFile(String pickedFilePath);
}
