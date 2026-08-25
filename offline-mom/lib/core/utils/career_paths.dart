import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where Career module outputs live on device: a `career/` subfolder of the
/// app's own private documents directory (never shared storage) - mirrors
/// `toolkit_paths.dart`/`audio_paths.dart`/`document_paths.dart` exactly,
/// same reasoning (fully offline, private, one place per content type).
///
/// Unlike Student Toolkit's several tool types, M1 has exactly one kind of
/// Career output (an exported resume PDF), so this exposes a single
/// function rather than [ToolkitToolType]-style dispatch - matching
/// `newAudioFilePath`'s own single-purpose shape more closely than
/// `newToolkitOutputPath`'s.
Future<String> newCareerOutputPath(String extension) async {
  final docsDir = await getApplicationDocumentsDirectory();
  final careerDir = Directory(p.join(docsDir.path, 'career'));
  if (!await careerDir.exists()) {
    await careerDir.create(recursive: true);
  }
  final fileName = 'resume_${DateTime.now().millisecondsSinceEpoch}.$extension';
  return p.join(careerDir.path, fileName);
}
