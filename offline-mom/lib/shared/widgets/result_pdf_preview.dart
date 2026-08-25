import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'error_state.dart';

/// Read-only, resolution-aware preview of finished PDF bytes - the shared
/// replacement for `package:printing`'s `PdfPreview` widget across every
/// Productivity Toolkit "preview before you save" step (Merge, Organize,
/// Edit, Redact).
///
/// `PdfPreview` rasterizes via its own internal path (`Printing.raster()`,
/// the same OS-level renderer `PdfiumPdfPageRenderingService` replaced for
/// this app's actual rasterize-and-rebuild pipeline - see that class's own
/// doc comment for why) - meaning the preview a user saw before saving was
/// completely bypassing PDFium and every quality fix (300dpi/
/// FilterQuality.high/crop-to-content) this app's own tools already apply
/// to the file being saved, so the preview looked meaningfully blurrier
/// than the real output. This widget instead reuses `pdfrx`'s own native
/// viewer (the same one View PDF uses, `view_pdf_screen.dart`), backed by
/// the same bundled PDFium engine, so what's previewed genuinely matches
/// the file that gets saved.
///
/// Read-only by construction - this is never used for the interactive
/// drawing/redaction canvases themselves (`pdf_edit_screen.dart`'s/
/// `pdf_redact_screen.dart`'s own `_Pdf*Canvas` widgets, which place
/// annotations/redaction boxes at precise coordinates baked into the saved
/// file - a fundamentally different, coordinate-critical concern this
/// widget has no involvement in).
class ResultPdfPreview extends StatefulWidget {
  const ResultPdfPreview({super.key, required this.bytesLoader, required this.sourceName});

  /// Loads the PDF bytes to preview - a simple `async => alreadyComputedBytes`
  /// where the result already sits in memory (Merge/Organize), or a real
  /// async computation (Redact/Edit, whose `buildResultBytes()` builds the
  /// PDF on demand). Called exactly once per widget lifetime (`initState`),
  /// not on every rebuild - unlike invoking it directly inside `build()`,
  /// which would silently re-trigger the (possibly expensive) computation
  /// on every unrelated rebuild.
  final Future<Uint8List> Function() bytesLoader;

  /// An identifying name for this PDF (e.g. the tool name) - `pdfrx` needs
  /// this to distinguish document instances; only used as an ID, never
  /// shown to the user.
  final String sourceName;

  @override
  State<ResultPdfPreview> createState() => _ResultPdfPreviewState();
}

class _ResultPdfPreviewState extends State<ResultPdfPreview> {
  late final Future<Uint8List> _bytesFuture = widget.bytesLoader();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorState(title: 'Preview unavailable', error: snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfViewer.data(snapshot.data!, sourceName: widget.sourceName);
      },
    );
  }
}
