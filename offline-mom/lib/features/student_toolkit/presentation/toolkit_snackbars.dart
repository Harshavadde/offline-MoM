import 'package:flutter/material.dart';

/// The one save-confirmation every Student Toolkit tool shows after
/// writing its output to `toolkit_files` (Batch 3, Design System
/// Consolidation) - `SnackBar(content: Text('Saved to Recent Files.'))`
/// was repeated verbatim across seven save call sites (Image Compress,
/// Image Resize, PDF Compress, PDF Merge, PDF Organize, PDF Split,
/// Scanner) rather than genuinely varying per tool.
void showSavedToRecentFilesSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Saved to Recent Files.')),
  );
}

/// P0-7 (OCR) - shown after saving a searchable PDF, instead of the plain
/// "Saved to Recent Files." every other tool uses: the whole point of Run
/// OCR is that it never overwrites the original, so this says so
/// explicitly rather than leaving the user to wonder whether their
/// original file just got replaced.
void showSearchableCopyCreatedSnackBar(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Searchable copy created - your original file was not changed.')),
  );
}
