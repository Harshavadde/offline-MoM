import 'package:flutter/material.dart';

import '../../../models/toolkit_file.dart';

/// One shared icon-per-[ToolkitToolType] mapping, used by every screen that
/// renders a [ToolkitFile] row (`StudentToolkitScreen`'s recent-files
/// preview, `ToolkitRecentFilesScreen`'s full list) - kept in one place
/// (not duplicated per screen) specifically so growing from 2 tool types
/// (Phase 5A) to 7 (Phase 5B: Scanner + PDF Tools) didn't mean copying the
/// same exhaustive `switch` twice. Lives in `presentation/`, not
/// `models/toolkit_file.dart` itself, since `IconData` is a Flutter UI
/// concern the model layer otherwise has no dependency on.
IconData toolkitToolTypeIcon(ToolkitToolType type) => switch (type) {
      ToolkitToolType.imageCompress => Icons.compress_rounded,
      ToolkitToolType.imageResize => Icons.aspect_ratio_rounded,
      ToolkitToolType.scan => Icons.document_scanner_rounded,
      ToolkitToolType.pdfCompress => Icons.picture_as_pdf_rounded,
      ToolkitToolType.pdfMerge => Icons.call_merge_rounded,
      ToolkitToolType.pdfSplit => Icons.call_split_rounded,
      ToolkitToolType.pdfOrganize => Icons.reorder_rounded,
      ToolkitToolType.pdfEdit => Icons.edit_document,
      ToolkitToolType.pdfRedact => Icons.hide_source_rounded,
      ToolkitToolType.imagesToPdf => Icons.image_outlined,
      ToolkitToolType.pdfToImages => Icons.perm_media_outlined,
      ToolkitToolType.ocr => Icons.text_fields_rounded,
      ToolkitToolType.pdfProtect => Icons.lock_outline_rounded,
      ToolkitToolType.pdfUnlock => Icons.lock_open_rounded,
    };
