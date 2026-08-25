import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/resume_snapshot.dart';
import 'resume_pdf_export_service.dart' show ResumePdfRenderException;
import 'template/archetypes/classic_single_column.dart';
import 'template/archetypes/compact_technical.dart';
import 'template/archetypes/creative_visual.dart';
import 'template/archetypes/entry_level_student.dart';
import 'template/archetypes/executive_summary_led.dart';
import 'template/archetypes/government_dense.dart';
import 'template/archetypes/minimalist_monochrome.dart';
import 'template/archetypes/modern_accent_column.dart';
import 'template/archetypes/two_column_right.dart';
import 'template/archetypes/two_column_sidebar.dart';
import 'template/resume_design_tokens.dart';
import 'template/resume_template_catalog.dart';
import 'template/resume_template_spec.dart';

/// Turns a compiled [ResumeSnapshot] into PDF bytes using a specific
/// [ResumeTemplateSpec] - docs/v3/01-prd.md §22.2's
/// `(ResumeSnapshot, ResumeTemplateSpec) → pw.Document → PDF file` shape.
/// [ResumeSnapshot] itself stays completely template-independent (never
/// imports anything from `template/`) - this class is the only place
/// content and template selection actually meet, exactly once, at render
/// time. `ResumePdfExportService` (`resume_pdf_export_service.dart`) is
/// the public-facing service every use case/screen actually depends on;
/// this renderer is its internal implementation detail, replacing what
/// used to be one hardcoded `pw.MultiPage` build closure.
class ResumeTemplateRenderer {
  const ResumeTemplateRenderer();

  /// Loads the bundled Inter font family (SIL Open Font License 1.1,
  /// `assets/fonts/Inter-LICENSE.txt`) once and reuses it for every render
  /// call - post-Milestone-5 visual-quality redesign pass. Previously every
  /// template rendered with `package:pdf`'s built-in Helvetica-clone base14
  /// font, which reads as a generic, dated "form" typeface next to a
  /// commercial resume product's own typography. Inter is a modern,
  /// highly-legible, print-and-screen-proven sans-serif shipped as a
  /// static asset bundled into the app at build time (`pubspec.yaml`) -
  /// loaded here via `rootBundle`, never fetched over the network, so this
  /// does not touch the app's offline requirement (docs/v3/01-prd.md §14)
  /// any more than any other bundled asset (app icons, `terms-of-service.md`)
  /// already does. Cached in a static `Future` so concurrent/repeated
  /// render calls share one load rather than re-reading ~1.2MB of font
  /// bytes from the asset bundle every time.
  static Future<pw.ThemeData>? _themeFuture;

  static Future<pw.ThemeData> _loadTheme() {
    return _themeFuture ??= () async {
      final regular = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
      final bold = await rootBundle.load('assets/fonts/Inter-Bold.ttf');
      final italic = await rootBundle.load('assets/fonts/Inter-Italic.ttf');
      return pw.ThemeData.withFont(
        base: pw.Font.ttf(regular),
        bold: pw.Font.ttf(bold),
        italic: pw.Font.ttf(italic),
      );
    }();
  }

  /// Renders [snapshot] with [spec]'s archetype and tokens. Throws
  /// [ResumePdfRenderException] on any renderer failure - never returns
  /// partial/corrupt bytes, mirroring the exact contract
  /// `PwResumePdfExportService.render` already had before this milestone.
  Future<Uint8List> render(ResumeSnapshot snapshot, ResumeTemplateSpec spec) async {
    try {
      final theme = await _loadTheme();
      final doc = pw.Document(theme: theme);
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(spec.tokens.pageMargin),
          build: (context) => _pagesFor(spec.archetypeId, snapshot, spec.tokens),
        ),
      );
      return await doc.save();
    } on ResumePdfRenderException {
      rethrow;
    } catch (e) {
      // A genuine renderer-library limitation (e.g. a glyph the loaded
      // font cannot encode) surfaces here as some `pdf`-package-internal
      // exception, not a typed one - never let that raw exception (or a
      // silently corrupt/partial document) escape uncaught.
      throw ResumePdfRenderException('This resume could not be rendered to PDF.', cause: e);
    }
  }

  /// Dispatches to the archetype build function [archetypeId] names. An
  /// unrecognized id (should never happen - [ResumeTemplateCatalog.specById]
  /// already resolves any unknown/missing id to [ResumeTemplateCatalog
  /// .defaultSpec] before a spec ever reaches here) falls back to Classic
  /// Single-Column rather than throwing, the same "always something
  /// sensible" discipline the catalog itself applies.
  List<pw.Widget> _pagesFor(String archetypeId, ResumeSnapshot snapshot, ResumeDesignTokens tokens) {
    switch (archetypeId) {
      case ResumeArchetypeIds.modernAccentColumn:
        return buildModernAccentColumnPages(snapshot, tokens);
      case ResumeArchetypeIds.twoColumnSidebar:
        return buildTwoColumnSidebarPages(snapshot, tokens);
      case ResumeArchetypeIds.compactTechnical:
        return buildCompactTechnicalPages(snapshot, tokens);
      case ResumeArchetypeIds.executiveSummaryLed:
        return buildExecutiveSummaryLedPages(snapshot, tokens);
      case ResumeArchetypeIds.creativeVisual:
        return buildCreativeVisualPages(snapshot, tokens);
      case ResumeArchetypeIds.entryLevelStudent:
        return buildEntryLevelStudentPages(snapshot, tokens);
      case ResumeArchetypeIds.minimalistMonochrome:
        return buildMinimalistMonochromePages(snapshot, tokens);
      case ResumeArchetypeIds.governmentDense:
        return buildGovernmentDensePages(snapshot, tokens);
      case ResumeArchetypeIds.twoColumnRight:
        return buildTwoColumnRightPages(snapshot, tokens);
      case ResumeArchetypeIds.classicSingleColumn:
      default:
        return buildClassicSingleColumnPages(snapshot, tokens);
    }
  }
}
