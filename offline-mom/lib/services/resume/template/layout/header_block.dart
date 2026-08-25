import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../resume_design_tokens.dart';
import 'contact_icons.dart';

/// Light text colors used only inside a colored [HeaderStyle.colorBand]/
/// [HeaderStyle.pill] surface - never used against the plain page
/// background, where [ResumeDesignTokens.inkColor]/[inkSoftColor] apply as
/// normal. Fixed rather than derived per-preset: both the warm and cool
/// accent colors in `resume_template_catalog.dart` are dark/saturated
/// enough that white text contrasts safely against either (confirmed by
/// direct visual inspection of the rendered PDFs, not assumed).
const _bandTextColor = PdfColors.white;
const _bandSoftTextColor = PdfColor.fromInt(0xFFEFF3F6);

/// A best-effort guess at which [ContactIconKind] a plain-text contact
/// item represents, used only when [ResumeDesignTokens.headerContactIcons]
/// is set - the underlying text is never altered or hidden, this only
/// picks which glyph precedes it.
ContactIconKind _classifyContactItem(String item) {
  if (item.contains('@')) return ContactIconKind.email;
  final digitCount = item.replaceAll(RegExp('[^0-9]'), '').length;
  if (digitCount >= 6) return ContactIconKind.phone;
  return ContactIconKind.location;
}

/// The resume owner's name, optional role tagline, contact line, and links
/// line - always the first content any reader (human or ATS) encounters,
/// regardless of which archetype places it in the main column or a
/// sidebar. Reusable across every archetype (docs/v3/01-prd.md §22.2)
/// rather than each one hand-building its own header layout.
///
/// **Product visual-audit pass:** this pass's own design audit found every
/// archetype's header was plain text on the page background - the single
/// biggest visual-weight gap against the studied Enhance CV references,
/// which use a colored role-tagline pill or a full-width color band as the
/// page's first, strongest visual signal. [ResumeDesignTokens.headerStyle]
/// now selects between the original [HeaderStyle.plain] treatment, a
/// [HeaderStyle.pill] (role tagline only, in a filled rounded badge), and
/// a [HeaderStyle.colorBand] (the whole header on a solid fill). The
/// [HeaderStyle.colorBand] fill spans the column's available *content*
/// width (the same `width: double.infinity` + parent-constraint mechanism
/// already used below for centered headers) - **not** true edge-to-edge
/// page bleed. Achieving literal bleed past the printed margin would
/// require restructuring every layout primitive's shared assumption that
/// `ResumeDesignTokens.pageMargin` is the page's own margin (set once on
/// `pw.MultiPage`, not re-applied per widget) - a much larger, higher-risk
/// change than this pass's own content-width color block, which delivers
/// the same "bold color anchor" effect the references use without
/// touching the page-margin architecture at all. Disclosed explicitly
/// here and in this pass's final report, not overstated as a pixel match.
pw.Widget buildHeaderBlock({
  required String name,
  String? roleTagline,
  String? contactLine,
  String? linksLine,
  required ResumeDesignTokens tokens,
  bool centered = false,
  bool nameUsesAccentColor = false,
  bool stackedContact = false,
}) {
  final crossAxisAlignment = centered ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start;
  final textAlign = centered ? pw.TextAlign.center : pw.TextAlign.left;
  final hasTagline = roleTagline != null && roleTagline.trim().isNotEmpty;

  // Post-Milestone-5 visual-quality pass, RV3-17: a single `" | "`-joined
  // contact line does not fit a ~140pt sidebar width at realistic content
  // lengths, wrapping awkwardly mid-item (confirmed by direct PDF
  // inspection, not a synthetic edge case). [stackedContact] renders each
  // item on its own line instead - every item still real, selectable
  // pw.Text, never a rasterized substitute. [ResumeDesignTokens
  // .headerContactIcons] (product visual-audit pass) additionally prefixes
  // each item with a small vector glyph (`contact_icons.dart`) - the
  // classification is a display-only best guess, the text itself is
  // unchanged either way.
  List<pw.Widget> contactWidgets(String line, PdfColor textColor) {
    final items = line.split(' | ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    pw.Widget item(String text) {
      final content = pw.Text(text, style: pw.TextStyle(fontSize: tokens.captionSize, color: textColor));
      if (!tokens.headerContactIcons) return content;
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          buildContactIcon(_classifyContactItem(text), size: tokens.captionSize, color: textColor),
          pw.SizedBox(width: 3),
          content,
        ],
      );
    }

    if (!stackedContact) {
      if (!tokens.headerContactIcons) {
        // Approved design specification pass: [headerContactCompactDots]
        // redisplays the contact items joined by a middle dot (" · ")
        // instead of the raw " | " storage separator - a typographic
        // punctuation mark instead of a formatting character. Display
        // only; the underlying stored contact line text is unchanged.
        final display = tokens.headerContactCompactDots ? items.join(' · ') : line;
        return [pw.Text(display, textAlign: textAlign, style: pw.TextStyle(fontSize: tokens.captionSize, color: textColor))];
      }
      return [
        pw.Wrap(
          spacing: 10,
          runSpacing: 3,
          children: [for (final i in items) item(i)],
        ),
      ];
    }
    return [
      for (final i in items)
        pw.Padding(
          padding: pw.EdgeInsets.only(top: tokens.lineGap / 2),
          child: item(i),
        ),
    ];
  }

  pw.Widget nameText(PdfColor color) => pw.Text(
        name,
        textAlign: textAlign,
        style: pw.TextStyle(
          fontSize: tokens.nameSize,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.2,
          color: color,
        ),
      );

  switch (tokens.headerStyle) {
    case HeaderStyle.colorBand:
      // The whole header (name + tagline + contact + links) on a solid
      // accent fill, light text throughout - the boldest of the three
      // treatments, reserved for archetypes whose identity is explicitly
      // "more visual personality." See this function's own doc comment
      // for why this is a content-width block, not true page-edge bleed.
      final column = pw.Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          nameText(_bandTextColor),
          if (hasTagline) ...[
            pw.SizedBox(height: tokens.lineGap),
            pw.Text(
              roleTagline,
              textAlign: textAlign,
              style: pw.TextStyle(fontSize: tokens.subheadingSize, color: _bandSoftTextColor),
            ),
          ],
          if (contactLine != null && contactLine.isNotEmpty) ...[
            pw.SizedBox(height: tokens.lineGap * 1.4),
            ...contactWidgets(contactLine, _bandSoftTextColor),
          ],
          if (linksLine != null && linksLine.isNotEmpty) ...[
            pw.SizedBox(height: tokens.lineGap),
            pw.Text(linksLine, textAlign: textAlign, style: pw.TextStyle(fontSize: tokens.captionSize, color: _bandSoftTextColor)),
          ],
        ],
      );
      return pw.Container(
        width: double.infinity,
        padding: pw.EdgeInsets.symmetric(horizontal: tokens.pageMargin * 0.5, vertical: tokens.pageMargin * 0.45),
        decoration: pw.BoxDecoration(
          color: tokens.accentColor,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
        ),
        child: column,
      );

    case HeaderStyle.pill:
      // Name and contact stay plain; only the role tagline sits inside a
      // filled, rounded accent badge directly under the name - reproduces
      // the studied reference's "colored banner under the name" motif
      // without recoloring the rest of the header.
      final column = pw.Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          nameText(nameUsesAccentColor ? tokens.accentColor : tokens.inkColor),
          if (hasTagline) ...[
            pw.SizedBox(height: tokens.lineGap),
            pw.Container(
              padding: pw.EdgeInsets.symmetric(horizontal: tokens.lineGap * 2.2, vertical: tokens.lineGap * 1.1),
              decoration: pw.BoxDecoration(
                color: tokens.accentColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              child: pw.Text(
                roleTagline,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: tokens.captionSize, color: _bandTextColor, fontWeight: pw.FontWeight.bold),
              ),
            ),
          ],
          if (contactLine != null && contactLine.isNotEmpty) ...[
            pw.SizedBox(height: tokens.lineGap),
            ...contactWidgets(contactLine, tokens.inkSoftColor),
          ],
          if (linksLine != null && linksLine.isNotEmpty) ...[
            pw.SizedBox(height: tokens.lineGap),
            pw.Text(linksLine, textAlign: textAlign, style: pw.TextStyle(fontSize: tokens.captionSize, color: tokens.inkSoftColor)),
          ],
        ],
      );
      if (!centered) return column;
      return pw.Container(width: double.infinity, alignment: pw.Alignment.center, child: column);

    case HeaderStyle.plain:
      // Design-execution pass: [headerRhythmGap] gives the header
      // deliberate breathing room between its own lines - null (every
      // archetype's unchanged behavior) falls back to the same tight
      // [lineGap] used everywhere else on the page.
      final headerGap = tokens.headerRhythmGap ?? tokens.lineGap;
      final gapAfterTagline = tokens.headerGapAfterTagline ?? headerGap;
      final column = pw.Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          nameText(nameUsesAccentColor ? tokens.accentColor : tokens.inkColor),
          if (hasTagline) ...[
            pw.SizedBox(height: headerGap),
            pw.Text(
              roleTagline,
              textAlign: textAlign,
              // [headerTaglineSize] gives the tagline its own step in the
              // scale - null falls back to subheadingSize (entry-title
              // scale), the pre-this-pass behavior an independent visual
              // review judged as competing with the name. [headerTaglineItalic]
              // (approved design specification pass) marks it as a caption
              // to the name, not a second headline.
              style: pw.TextStyle(
                fontSize: tokens.headerTaglineSize ?? tokens.subheadingSize,
                fontStyle: tokens.headerTaglineItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
                color: tokens.inkSoftColor,
              ),
            ),
          ],
          if (contactLine != null && contactLine.isNotEmpty) ...[
            pw.SizedBox(height: hasTagline ? gapAfterTagline : headerGap),
            ...contactWidgets(contactLine, tokens.inkSoftColor),
          ],
          if (linksLine != null && linksLine.isNotEmpty) ...[
            pw.SizedBox(height: headerGap),
            pw.Text(linksLine, textAlign: textAlign, style: pw.TextStyle(fontSize: tokens.captionSize, color: tokens.inkSoftColor)),
          ],
        ],
      );

      if (!centered) return column;

      // A bare pw.Column sizes itself to its widest child's *intrinsic*
      // width, not the full page width - so centering its children only
      // centers them relative to each other, producing a lopsided result
      // where the shorter/longer lines don't actually align under the
      // page's true center (a real visual bug this quality pass found and
      // fixed by manual PDF inspection, not caught by any structural
      // test). Wrapping in a full-width pw.Container forces the column
      // itself to span the page's available width first, so
      // `crossAxisAlignment.center` then centers every line against the
      // *page*, not against each other.
      return pw.Container(
        width: double.infinity,
        alignment: pw.Alignment.center,
        child: column,
      );
  }
}
