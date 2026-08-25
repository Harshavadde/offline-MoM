import 'dart:io';
import 'dart:typed_data';

import '../../models/resume_snapshot.dart';
import 'resume_template_renderer.dart';
import 'template/resume_template_catalog.dart';
import 'template/resume_template_spec.dart';

/// Thrown by [ResumePdfExportService.render] when the underlying PDF
/// renderer cannot produce output for a snapshot - e.g. a genuine
/// rendering-library limitation, not a missing file or a bad path. Kept
/// separate from a raw exception so a future caller (a use case, not this
/// service) can catch it specifically and map it through
/// `friendlyErrorMessage`, rather than this service reaching into UI-layer
/// error copy itself.
class ResumePdfRenderException implements Exception {
  ResumePdfRenderException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ResumePdfRenderException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Contract for turning a compiled [ResumeSnapshot] into a PDF - mirrors
/// [PdfExportService]'s shape (services/export/pdf_export_service.dart): a
/// pure function of already-gathered data, no repository access, no file
/// I/O in the rendering step itself.
abstract class ResumePdfExportService {
  /// Pure bytes, no file I/O - [snapshot] rendered with [templateSpec]'s
  /// archetype and design tokens (docs/v3/01-prd.md §22.2). `null` (the
  /// default) resolves to [ResumeTemplateCatalog.defaultSpec] (Classic
  /// Single-Column) - the same template every pre-Milestone-1 caller
  /// already rendered with, so an existing call site that never passes
  /// this parameter keeps behaving exactly as before. Throws
  /// [ResumePdfRenderException] if the renderer itself fails; never
  /// returns partial or corrupt bytes.
  Future<Uint8List> render(ResumeSnapshot snapshot, {ResumeTemplateSpec? templateSpec});

  /// Renders [snapshot] (with [templateSpec], same default as [render])
  /// and writes it safely to [destinationPath]: writes to a temporary
  /// path first, and only renames it into the final destination once that
  /// write has fully succeeded - [destinationPath] is never left holding
  /// a partially-written file, and is never touched at all if rendering
  /// or writing fails. Returns the final path only after this completes
  /// successfully; cleans up the temporary file on any failure.
  Future<String> exportToFile(
    ResumeSnapshot snapshot,
    String destinationPath, {
    ResumeTemplateSpec? templateSpec,
  });
}

/// [ResumePdfExportService] implementation backed by [ResumeTemplateRenderer]
/// (docs/v3/01-prd.md §22.2/§25 Milestone 1) - before this milestone, this
/// class built its one hardcoded `pw.MultiPage` directly; now it only owns
/// template-selection defaulting and the atomic file-write discipline
/// below, delegating actual rendering to the shared, multi-archetype
/// renderer every template goes through.
class PwResumePdfExportService implements ResumePdfExportService {
  const PwResumePdfExportService({ResumeTemplateRenderer renderer = const ResumeTemplateRenderer()})
      : _renderer = renderer;

  final ResumeTemplateRenderer _renderer;

  @override
  Future<Uint8List> render(ResumeSnapshot snapshot, {ResumeTemplateSpec? templateSpec}) {
    return _renderer.render(snapshot, templateSpec ?? ResumeTemplateCatalog.defaultSpec);
  }

  @override
  Future<String> exportToFile(
    ResumeSnapshot snapshot,
    String destinationPath, {
    ResumeTemplateSpec? templateSpec,
  }) async {
    final bytes = await render(snapshot, templateSpec: templateSpec);

    final tempPath = '$destinationPath.tmp';
    final tempFile = File(tempPath);
    try {
      await tempFile.parent.create(recursive: true);
      await tempFile.writeAsBytes(bytes, flush: true);
      // Same-directory temp file so this rename is a same-filesystem move
      // - the only way dart:io's rename is guaranteed atomic - never a
      // separate copy+delete that could itself leave a partial file at
      // destinationPath.
      final finalFile = await tempFile.rename(destinationPath);
      return finalFile.path;
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }
}
