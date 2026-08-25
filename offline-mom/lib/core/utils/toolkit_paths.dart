import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/toolkit_file.dart';

/// Where Student Toolkit outputs live on device: a `toolkit/` subfolder of
/// the app's own private documents directory (never shared storage) -
/// mirrors `audio_paths.dart`/`document_paths.dart` exactly, same reasoning
/// (fully offline, private, one place per content type).
///
/// The Image Tools pipeline (V2 Phase 5A) writes only this one file per
/// operation - source bytes and intermediate processing all stay in memory,
/// so there is no temp file for that pipeline to leak. Scanner and PDF
/// Tools (V2 Phase 5B) are different: a multi-page scan or a large PDF
/// can't safely stay fully in memory at once (see ADR-034,
/// docs/v2/implementation/03-decisions.md, and this app's own performance
/// requirement to avoid loading huge documents into memory) - those tools
/// use [newToolkitTempFilePath] for intermediate per-page working files,
/// under their own explicit `try/finally` cleanup discipline, directly
/// applying the lesson Phase 4B learned the hard way from `BackupScreen`'s
/// leaked backup-export temp file (ADR-032).
Future<String> newToolkitOutputPath(ToolkitToolType toolType, String extension) async {
  final toolkitDir = await _toolkitDir();
  final fileName = '${_prefixFor(toolType)}_${DateTime.now().millisecondsSinceEpoch}.$extension';
  return p.join(toolkitDir.path, fileName);
}

/// A throwaway intermediate file (e.g. one rasterized PDF page) under
/// `toolkit/tmp/` - callers are responsible for deleting every path they
/// request from this, in a `finally` block, once the operation using them
/// completes (successfully or not). `clearToolkitTempFiles` (below) is the
/// safety net for the case that discipline misses (e.g. the process being
/// killed mid-operation), mirroring `clearTempTranscodeCache`'s existing
/// precedent (`storage_providers.dart`).
Future<String> newToolkitTempFilePath(String extension) async {
  final toolkitDir = await _toolkitDir();
  final tmpDir = Directory(p.join(toolkitDir.path, 'tmp'));
  if (!await tmpDir.exists()) {
    await tmpDir.create(recursive: true);
  }
  final fileName = 'tmp_${DateTime.now().microsecondsSinceEpoch}_'
      '${_tempCounter++}.$extension';
  return p.join(tmpDir.path, fileName);
}

/// Deletes every leftover file under `toolkit/tmp/` - the safety net for
/// [newToolkitTempFilePath] callers that didn't get to clean up after
/// themselves (process killed mid-operation). Safe to call any time (e.g.
/// app startup, alongside `clearTempTranscodeCache`); returns the count
/// deleted.
Future<int> clearToolkitTempFiles() async {
  final toolkitDir = await _toolkitDir();
  final tmpDir = Directory(p.join(toolkitDir.path, 'tmp'));
  if (!await tmpDir.exists()) return 0;
  var deleted = 0;
  await for (final entity in tmpDir.list()) {
    if (entity is File) {
      await entity.delete();
      deleted++;
    }
  }
  return deleted;
}

int _tempCounter = 0;

Future<Directory> _toolkitDir() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final toolkitDir = Directory(p.join(docsDir.path, 'toolkit'));
  if (!await toolkitDir.exists()) {
    await toolkitDir.create(recursive: true);
  }
  return toolkitDir;
}

String _prefixFor(ToolkitToolType toolType) => switch (toolType) {
      ToolkitToolType.imageCompress => 'compressed',
      ToolkitToolType.imageResize => 'resized',
      ToolkitToolType.scan => 'scan',
      ToolkitToolType.pdfCompress => 'pdf_compressed',
      ToolkitToolType.pdfMerge => 'pdf_merged',
      ToolkitToolType.pdfSplit => 'pdf_split',
      ToolkitToolType.pdfOrganize => 'pdf_organized',
      ToolkitToolType.pdfEdit => 'pdf_edited',
      ToolkitToolType.pdfRedact => 'pdf_redacted',
      ToolkitToolType.imagesToPdf => 'images_to_pdf',
      ToolkitToolType.pdfToImages => 'pdf_page_image',
      ToolkitToolType.ocr => 'searchable_pdf',
      ToolkitToolType.pdfProtect => 'pdf_protected',
      ToolkitToolType.pdfUnlock => 'pdf_unlocked',
    };
