import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where recorded/imported meeting audio lives on device: a `recordings/`
/// subfolder of the app's own private documents directory (never shared
/// storage), consistent with the app being fully offline and private. Used
/// by both live recording and file import so every meeting's audio ends up
/// in the same place regardless of source.
Future<String> newAudioFilePath() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final recordingsDir = Directory(p.join(docsDir.path, 'recordings'));
  if (!await recordingsDir.exists()) {
    await recordingsDir.create(recursive: true);
  }
  final fileName = 'meeting_${DateTime.now().millisecondsSinceEpoch}.m4a';
  return p.join(recordingsDir.path, fileName);
}
