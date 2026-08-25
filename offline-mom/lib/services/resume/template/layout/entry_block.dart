import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../resume_design_tokens.dart';

/// A single styled text run - the [pw.Text]/[pw.TextSpan] choice is an
/// internal detail callers never need to know, since a `RichText` with one
/// span behaves identically to a plain `Text` for layout purposes.
pw.Widget _styledText(String text, pw.TextStyle style, {pw.TextAlign? textAlign}) {
  return pw.Text(text, style: style, textAlign: textAlign ?? pw.TextAlign.left);
}

/// One named sub-project nested under an entry, already resolved down to
/// plain display strings - the layout layer's own view of
/// `ExperienceSubProject` (`experience_block.dart`), kept separate so this
/// package never needs to import the data-model layer directly (matching
/// every other field `buildEntryBlock` takes as a plain String/List<String>,
/// never a model type).
class EntrySubProjectView {
  const EntrySubProjectView(this.name, this.bullets);

  final String name;
  final List<String> bullets;
}

/// One entry within a section - a structured header (role/degree/name,
/// optionally a company/institution, optionally a date range and
/// location), and zero or more bullets. The one shape every Experience/
/// Education/Project/Certification entry reduces to, shared across every
/// archetype rather than four near-identical widget trees.
///
/// **Reference-driven product redesign pass:** [primaryTitle]/
/// [secondaryTitle]/[metaPrimary]/[metaSecondary] are real structured
/// fields (role/degree/name, company/institution, date range, location) -
/// not a single pre-joined string a template has to heuristically re-split
/// to recover hierarchy. [ResumeDesignTokens.entryHeaderStyle] decides how
/// they compose: [EntryHeaderStyle.inline] (title row + right-aligned
/// date, the space-efficient default most archetypes keep),
/// [EntryHeaderStyle.stacked] (role, then company, then date+location,
/// each on their own line - Executive/Dense Senior-Leadership's
/// identity), or [EntryHeaderStyle.editorial] (role+date share one row,
/// company+location share a quiet second row - the approved design
/// specification's composition, Balanced Two-Column only). None of the
/// three modes alters the underlying text itself, only its layout/
/// styling, so this has zero effect on what a PDF-text extractor reads
/// back (docs/v3/01-prd.md §9) - all three still emit every field as
/// real, selectable text, in reading order.
pw.Widget buildEntryBlock({
  required String primaryTitle,
  String? secondaryTitle,
  String? metaPrimary,
  String? metaSecondary,
  List<String> bullets = const [],
  List<EntrySubProjectView> subProjects = const [],
  required ResumeDesignTokens tokens,
}) {
  final emphasisColor = tokens.headingUsesAccentColor ? tokens.accentColor : tokens.inkColor;
  final emphasisStyle = pw.TextStyle(
    fontSize: tokens.subheadingSize,
    fontWeight: pw.FontWeight.bold,
    color: emphasisColor,
  );
  // Design-execution pass: [companySize] gives the subordinate line its
  // own, smaller step in the type scale instead of only differing from
  // the emphasis line by weight - null falls back to subheadingSize,
  // every archetype's unchanged prior behavior. Approved design
  // specification pass: in EntryHeaderStyle.editorial specifically, the
  // subordinate (company/location) line is also italic - a real
  // typographic signal for "supporting information," not just smaller.
  final isEditorialHeader = tokens.entryHeaderStyle == EntryHeaderStyle.editorial;
  final subordinateStyle = pw.TextStyle(
    fontSize: tokens.companySize ?? tokens.subheadingSize,
    fontWeight: pw.FontWeight.normal,
    fontStyle: isEditorialHeader ? pw.FontStyle.italic : pw.FontStyle.normal,
    color: tokens.inkSoftColor,
  );
  // Product visual-audit pass: the two full-detail Enhance CV references
  // studied for this pass disagree with each other on whether role or
  // company carries the bold visual weight - it is a per-template
  // creative choice, not a universal rule (see [EntryTitleEmphasis]'s own
  // doc comment). `primaryTitle` is always role/degree/name in reading
  // order regardless of which one is visually emphasized - only the
  // style assignment swaps, never the text order.
  final titleStyle =
      tokens.entryTitleEmphasis == EntryTitleEmphasis.role ? emphasisStyle : subordinateStyle;
  final secondaryStyle =
      tokens.entryTitleEmphasis == EntryTitleEmphasis.role ? subordinateStyle : emphasisStyle;
  final metaStyle = pw.TextStyle(
    fontSize: tokens.captionSize,
    fontStyle: isEditorialHeader ? pw.FontStyle.italic : pw.FontStyle.normal,
    color: tokens.inkSoftColor,
  );

  final hasSecondary = secondaryTitle != null && secondaryTitle.isNotEmpty;
  final hasMeta = (metaPrimary != null && metaPrimary.isNotEmpty) ||
      (metaSecondary != null && metaSecondary.isNotEmpty);

  // Design-execution / approved specification passes: in
  // EntryRhythmStyle.editorial, the gap within the entry's own header
  // (title→company→meta) stays tight - they read as one unit - while the
  // gap before the first bullet is deliberately larger, separating
  // "who/where/when" from "what was achieved." Fixed to the specification's
  // exact micro/medium/small tiers (2pt/10pt/5pt) rather than derived from
  // lineGap, since the approved spec gives literal point values. In
  // EntryRhythmStyle.standard (every other archetype's unchanged
  // behavior), every internal gap is the same lineGap/2.
  final isEditorialRhythm = tokens.entryRhythmStyle == EntryRhythmStyle.editorial;
  const editorialMicroGap = 2.0;
  const editorialFirstBulletGap = 10.0;
  // Final visual-polish pass, point #3: 5pt→6pt - long bullets still felt
  // slightly dense; a small, deliberate increase to inter-bullet
  // breathing room, not a page-inflating one.
  const editorialInterBulletGap = 6.0;
  final headerInternalGap = isEditorialRhythm ? editorialMicroGap : tokens.lineGap / 2;

  pw.Widget header;
  if (tokens.entryHeaderStyle == EntryHeaderStyle.editorial) {
    // Approved design specification: role+date share row 1; company and
    // location share row 2, joined by a middle dot, in the subordinate
    // (smaller, italic, muted) style - two facts per row, each row a
    // single coherent unit rather than four fields all competing for
    // attention at once.
    final row1 = hasMeta
        ? pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _styledText(primaryTitle, titleStyle)),
              pw.SizedBox(width: 8),
              _styledText(metaPrimary ?? '', metaStyle, textAlign: pw.TextAlign.right),
            ],
          )
        : _styledText(primaryTitle, titleStyle);
    final row2Text =
        [secondaryTitle, metaSecondary].where((s) => s != null && s.isNotEmpty).join(' · ');
    header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        row1,
        if (row2Text.isNotEmpty) ...[
          pw.SizedBox(height: headerInternalGap),
          _styledText(row2Text, secondaryStyle),
        ],
      ],
    );
  } else if (tokens.entryHeaderStyle == EntryHeaderStyle.stacked) {
    header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _styledText(primaryTitle, titleStyle),
        if (hasSecondary) ...[
          pw.SizedBox(height: headerInternalGap),
          _styledText(secondaryTitle, secondaryStyle),
        ],
        if (hasMeta) ...[
          pw.SizedBox(height: headerInternalGap),
          _styledText(
            [metaPrimary, metaSecondary].where((s) => s != null && s.isNotEmpty).join('  |  '),
            metaStyle,
          ),
        ],
      ],
    );
  } else {
    final titleWidget = hasSecondary
        ? pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: primaryTitle, style: titleStyle),
              pw.TextSpan(text: ' - $secondaryTitle', style: secondaryStyle),
            ]),
          )
        : _styledText(primaryTitle, titleStyle);

    if (hasMeta) {
      header = pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(flex: 3, child: titleWidget),
          pw.SizedBox(width: 8),
          pw.Expanded(
            flex: 2,
            child: _styledText(
              [metaPrimary, metaSecondary].where((s) => s != null && s.isNotEmpty).join(' | '),
              metaStyle,
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      );
    } else {
      header = titleWidget;
    }
  }

  final firstBulletGap = isEditorialRhythm ? editorialFirstBulletGap : tokens.lineGap;
  final interBulletGap = isEditorialRhythm ? editorialInterBulletGap : tokens.lineGap;

  // Sub-project name style - one step down from the entry's own title
  // (subheadingSize, not the larger emphasis size) but still bold, so it
  // reads as a nested heading rather than another bullet - and indented,
  // so the Resume -> Experience -> Project nesting is visually legible,
  // not just structurally present in the data.
  final subProjectNameStyle = pw.TextStyle(
    fontSize: tokens.bodySize,
    fontWeight: pw.FontWeight.bold,
    color: tokens.inkColor,
  );
  const subProjectIndent = 10.0;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      header,
      for (var i = 0; i < bullets.length; i++) ...[
        pw.SizedBox(height: i == 0 ? firstBulletGap : interBulletGap),
        buildBullet(bullets[i], tokens),
      ],
      for (final subProject in subProjects) ...[
        pw.SizedBox(height: bullets.isEmpty ? firstBulletGap : interBulletGap),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: subProjectIndent),
          child: pw.Text(subProject.name, style: subProjectNameStyle),
        ),
        for (final bullet in subProject.bullets) ...[
          pw.SizedBox(height: interBulletGap),
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: subProjectIndent),
            child: buildBullet(bullet, tokens),
          ),
        ],
      ],
    ],
  );
}

/// One achievement bullet - dispatches on [ResumeDesignTokens.bulletMarkerStyle].
///
/// **Approved design specification pass:** [BulletMarkerStyle.dash]
/// (Balanced Two-Column only) is composed by hand - a `pw.Row` of a
/// literal "–" glyph and the bullet text - since `pw.Bullet` only draws a
/// geometric marker shape (`BoxShape.circle`/`.rectangle`), never an
/// arbitrary character. Text is always left-aligned/ragged-right, never
/// justified: justified text in a narrow column produces uneven,
/// sometimes very stretched inter-word gaps line to line, a visible
/// "machine-generated" signal the independent visual review's own
/// diagnosis pointed to. [BulletMarkerStyle.shape] (every other
/// archetype's unchanged behavior) keeps the original `pw.Bullet`
/// composition and justified alignment exactly as before.
///
/// Public (Product Validation phase, beta data-fidelity fix): reused
/// directly by `content_line_renderer.dart` for a *standalone* bullet - a
/// custom/generic section's entry line, which has no entry title to
/// attach to (see that file's own doc comment on why a title-less bullet
/// needs this).
pw.Widget buildBullet(String text, ResumeDesignTokens tokens) {
  final bodyStyle = pw.TextStyle(
    fontSize: tokens.bodySize,
    color: tokens.inkColor,
    lineSpacing: tokens.bulletLineSpacing,
  );

  if (tokens.bulletMarkerStyle == BulletMarkerStyle.dash) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 12,
          child: pw.Text('–', style: bodyStyle),
        ),
        pw.Expanded(
          child: pw.Text(text, style: bodyStyle, textAlign: pw.TextAlign.left),
        ),
      ],
    );
  }

  return pw.Bullet(
    text: text,
    textAlign: pw.TextAlign.justify,
    bulletSize: 1.1 * PdfPageFormat.mm,
    bulletShape: pw.BoxShape.rectangle,
    bulletColor: tokens.inkSoftColor,
    bulletMargin: pw.EdgeInsets.only(
      top: tokens.bodySize * 0.38,
      left: 5.0 * PdfPageFormat.mm,
      right: 2.5 * PdfPageFormat.mm,
    ),
    style: bodyStyle,
  );
}
