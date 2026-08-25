import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where imported documents live on device: a `documents/` subfolder of
/// the app's own private documents directory (never shared storage) -
/// mirrors `audio_paths.dart`'s `newAudioFilePath()` exactly, same
/// reasoning (fully offline, private, one place per content type).
Future<String> newDocumentFilePath(String extension) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final documentsDir = Directory(p.join(docsDir.path, 'documents'));
  if (!await documentsDir.exists()) {
    await documentsDir.create(recursive: true);
  }
  final fileName = 'document_${DateTime.now().millisecondsSinceEpoch}.$extension';
  return p.join(documentsDir.path, fileName);
}
