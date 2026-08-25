import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where Whisper `.bin` model files live on this device - extracted (Phase
/// 6A, AI Model Manager) from `WhisperSpeechToTextEngine`'s original
/// inline expression so both that engine and the new
/// `ModelDownloadController` (`lib/features/ai_models/`) resolve the exact
/// same directory, rather than each hardcoding the platform check
/// separately and risking drift.
Future<Directory> whisperModelDirectory() async {
  return Platform.isAndroid ? await getApplicationSupportDirectory() : await getLibraryDirectory();
}
