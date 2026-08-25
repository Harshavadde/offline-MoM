import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/template/layout/content_line_renderer.dart';
import 'package:offline_mom/services/resume/template/layout/divider.dart';
import 'package:offline_mom/services/resume/template/layout/entry_block.dart';
import 'package:offline_mom/services/resume/template/layout/header_block.dart';
import 'package:offline_mom/services/resume/template/layout/section_block.dart';
import 'package:offline_mom/services/resume/template/layout/sidebar_column.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan.dart';
import 'package:offline_mom/services/resume/template/resume_design_tokens.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Physical-Mobile-First Validation phase (pagination fix): renderContentLines
/// now wraps a section heading together with its first content unit in one
/// non-splittable pw.Column (content_line_renderer.dart's own doc comment
/// on pendingSectionHeadingGroup) so the two can never be separated by a
/// page break. That changes the *shape* of the returned list (some
/// primitives that used to be independent top-level siblings are now
/// nested one level inside that wrapper) without changing what actually
/// gets painted - this depth-first flatten restores a single ordered list
/// of every widget (wrappers included) so assertions about which
/// primitives appear, and in what relative order, stay valid regardless of
/// whether a given widget happens to be wrapped for pagination purposes.
List<pw.Widget> _flattenAll(List<pw.Widget> widgets) {
  final result = <pw.Widget>[];
  void visit(pw.Widget widget) {
    result.add(widget);
    if (widget is pw.Column) {
      for (final child in widget.children) {
        visit(child);
      }
    } else if (widget is pw.Inseparable && widget.child != null) {
      visit(widget.child!);
    }
  }

  for (final widget in widgets) {
    visit(widget);
  }
  return result;
}

void main() {
  const tokens = ResumeDesignTokens(
    nameSize: 24,
    headingSize: 14,
    subheadingSize: 11,
    bodySize: 10,
    captionSize: 9,
    pageMargin: 32,
    sectionGap: 14,
    entryGap: 10,
    lineGap: 3,
    inkColor: PdfColors.black,
    inkSoftColor: PdfColors.grey600,
    accentColor: PdfColors.blue,
    dividerColor: PdfColors.grey300,
  );

  group('buildHeaderBlock', () {
    test('returns a widget without throwing for name-only input', () {
      expect(() => buildHeaderBlock(name: 'Jane Doe', tokens: tokens), returnsNormally);
    });

    test('returns a pw.Column', () {
      final widget = buildHeaderBlock(name: 'Jane Doe', tokens: tokens);
      expect(widget, isA<pw.Column>());
    });

    test('handles null/empty contact and links without throwing', () {
      expect(
        () => buildHeaderBlock(name: 'Jane Doe', contactLine: null, linksLine: '', tokens: tokens),
        returnsNormally,
      );
    });
  });

  group('buildSectionHeading', () {
    test('returns a pw.Text carrying the exact heading string', () {
      final widget = buildSectionHeading('Experience', tokens);
      expect(widget, isA<pw.Text>());
      // pw.Text wraps its string in a TextSpan (RichText.text: InlineSpan),
      // so the literal string lives at (.text as TextSpan).text.
      expect(((widget as pw.Text).text as pw.TextSpan).text, 'Experience');
    });

    test('does not alter the section heading text in any way', () {
      final widget = buildSectionHeading('Certifications', tokens) as pw.Text;
      expect((widget.text as pw.TextSpan).text, 'Certifications');
    });
  });

  group('buildEntryBlock', () {
    test('returns a widget without throwing for a title-only entry', () {
      expect(
        () => buildEntryBlock(primaryTitle: 'Engineer', secondaryTitle: 'Acme', tokens: tokens),
        returnsNormally,
      );
    });

    test('returns a widget without throwing with meta and bullets', () {
      expect(
        () => buildEntryBlock(
          primaryTitle: 'Engineer',
          secondaryTitle: 'Acme',
          metaPrimary: '2022-01 - Present',
          bullets: const ['Did a thing', 'Did another thing'],
          tokens: tokens,
        ),
        returnsNormally,
      );
    });

    test('returns a pw.Column', () {
      expect(
        buildEntryBlock(primaryTitle: 'Engineer', secondaryTitle: 'Acme', tokens: tokens),
        isA<pw.Column>(),
      );
    });
  });

  group('buildSidebarColumn', () {
    test('wraps children into a pw.Column without throwing', () {
      expect(() => buildSidebarColumn(children: [pw.Text('Jane Doe')]), returnsNormally);
    });

    test('returns a pw.Column (a SpanningWidget, required by pw.Partition - see the '
        'function\'s own doc comment)', () {
      expect(buildSidebarColumn(children: [pw.Text('Jane Doe')]), isA<pw.Column>());
    });
  });

  group('buildDivider', () {
    test('returns a pw.Container without throwing', () {
      expect(() => buildDivider(tokens), returnsNormally);
      expect(buildDivider(tokens), isA<pw.Container>());
    });
  });

  group('renderContentLines', () {
    test('an empty line list produces an empty widget list', () {
      expect(renderContentLines(const [], tokens), isEmpty);
    });

    test('name + contact + links lines collapse into exactly one header widget', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe'),
        ResumeContentLine(ResumeContentLineKind.contact, 'jane@x.com'),
        ResumeContentLine(ResumeContentLineKind.links, 'GitHub: x'),
      ], tokens);

      expect(widgets, hasLength(1));
      expect(widgets.single, isA<pw.Column>());
    });

    test('a section heading followed by one entry produces a non-empty widget list without throwing', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Engineer - Acme'),
        ResumeContentLine(ResumeContentLineKind.entryMeta, '2022-01 - Present'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Did a thing'),
      ], tokens);

      expect(widgets, isNotEmpty);
    });

    test('Physical-Mobile-First Validation phase - pagination fix: a section heading and its '
        'first entry are wrapped in one pw.Inseparable, so pw.MultiPage can never break the '
        'page between a heading and its first content (the orphaned-heading defect found by '
        'direct visual PDF inspection across all 5 beta templates on an ordinary realistic '
        'resume, never a contrived edge case). Must be pw.Inseparable specifically - neither '
        'pw.Column nor pw.Container actually prevent the split: both delegate their own '
        'canSpan to their child, so wrapping a spanning Column inside either still reports '
        'canSpan == true and MultiPage still splits inside it (confirmed by direct visual PDF '
        're-inspection: two earlier versions of this fix, using a nested Column and then a '
        'Container, both had zero effect on the real defect). pw.Inseparable is package:pdf\'s '
        'own purpose-built "keep together" primitive - its canSpan/hasMoreWidgets are hardcoded '
        'false regardless of the child.', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Engineer - Acme'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Did a thing'),
      ], tokens);

      expect(widgets, hasLength(1), reason: 'heading + its only/first entry collapse into one atomic widget');
      final group = widgets.single as pw.Inseparable;
      expect(group.canSpan, isFalse, reason: 'this is the actual property that keeps MultiPage from splitting it');
      final inner = group.child! as pw.Column;
      expect(inner.children.whereType<pw.Text>(), isNotEmpty, reason: 'the heading text is inside the group');
      expect(inner.children.whereType<pw.Column>(), isNotEmpty, reason: 'the entry block is inside the group too');
    });

    test('Physical-Mobile-First Validation phase - pagination fix: only the heading\'s *first* '
        'entry is glued to it - a second entry in the same section still becomes its own '
        'independent, freely-paginating top-level widget, so a section too large for one page '
        'still continues naturally onto the next rather than being forced to fit', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Role A'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Bullet for A'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Role B'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Bullet for B'),
      ], tokens);

      // heading+entryA group, then spacer(s), then entryB standing alone -
      // more than the single atomic widget the heading-plus-one-entry case
      // above produces.
      expect(widgets.length, greaterThan(1));
    });

    test('two consecutive entries under one heading both get their own entry block '
        '(no bullet bleeding from one entry into the next)', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Role A'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Bullet for A'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Role B'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Bullet for B'),
      ], tokens);

      // heading + spacer + entry A + spacer + entry B, at minimum two
      // pw.Column entry widgets among the output - exact count depends on
      // internal spacer widgets, so this asserts on presence rather than
      // a brittle total count. Entry A is nested inside the heading's
      // pw.Inseparable wrapper (pagination fix); flatten first so it's
      // still found alongside entry B, which stays a free top-level item.
      final columns = _flattenAll(widgets).whereType<pw.Column>().toList();
      expect(columns.length, greaterThanOrEqualTo(2));
    });

    test(
      'sub-projects (migration v20 - Resume -> Experience -> Project -> Project bullets): '
      'each subProjectTitle line accumulates only its own following bullet lines, never '
      'bleeding into a sibling sub-project or the parent entry\'s own bullets',
      () {
        final widgets = renderContentLines(const [
          ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
          ResumeContentLine(ResumeContentLineKind.entryTitle, 'Software Engineer - Acme'),
          ResumeContentLine(ResumeContentLineKind.bullet, 'Main entry bullet'),
          ResumeContentLine(ResumeContentLineKind.subProjectTitle, 'SciLab'),
          ResumeContentLine(ResumeContentLineKind.bullet, 'SciLab bullet 1'),
          ResumeContentLine(ResumeContentLineKind.bullet, 'SciLab bullet 2'),
          ResumeContentLine(ResumeContentLineKind.subProjectTitle, 'ByHeart'),
          ResumeContentLine(ResumeContentLineKind.bullet, 'ByHeart bullet 1'),
        ], tokens);

        // entry_block.dart wraps every sub-project name and every
        // sub-project bullet (but never the parent entry's own top-level
        // bullets) in its own pw.Padding for the nested-indent treatment -
        // 2 sub-project names + 3 sub-project bullets = 5, regardless of
        // how the pagination-fix wrapper nests the surrounding widgets.
        final paddings = _flattenAll(widgets).whereType<pw.Padding>().toList();
        expect(paddings.length, 5);
      },
    );

    test(
      'sub-projects: an entry with no subProjectTitle lines produces no pw.Padding-wrapped '
      'sub-project content (unchanged behavior for every ordinary entry)',
      () {
        final widgets = renderContentLines(const [
          ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
          ResumeContentLine(ResumeContentLineKind.entryTitle, 'Role A'),
          ResumeContentLine(ResumeContentLineKind.bullet, 'Ordinary bullet'),
        ], tokens);

        expect(_flattenAll(widgets).whereType<pw.Padding>(), isEmpty);
      },
    );

    test('Product Validation phase, beta data-fidelity fix: a bullet line '
        'with no preceding entryTitle (a custom/generic section\'s entry) is '
        'still rendered - not silently dropped. Regression test for a real '
        'bug found by direct visual PDF inspection: flushEntry()\'s own '
        '"if (!hasOpenEntry) return" guard discarded every accumulated '
        'bullet when nothing ever opened an entry to flush them from.', () {
      final headingOnly = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Awards'),
      ], tokens);
      final headingWithBullet = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Awards'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Employee of the Year'),
      ], tokens);

      // Pagination fix: the heading and its first bullet are now grouped
      // into one non-splittable wrapper widget, so top-level .length alone
      // no longer distinguishes "bullet present" from "no bullet" - flatten
      // first to compare the real widget count regardless of nesting.
      expect(_flattenAll(headingWithBullet).length, greaterThan(_flattenAll(headingOnly).length));
    });

    test('multiple standalone bullets under one heading (a custom section '
        'with several entries) all render - none dropped', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Publications'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'A Paper About Something'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'Another Paper'),
        ResumeContentLine(ResumeContentLineKind.bullet, 'A Third Paper'),
      ], tokens);

      // heading widget + one widget per standalone bullet, at minimum -
      // the heading and its first bullet are now grouped into one
      // wrapper (pagination fix), so flatten before counting.
      expect(_flattenAll(widgets).length, greaterThanOrEqualTo(4));
    });

    test('a standalone paragraph line (Skills) produces a pw.Paragraph', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Skills'),
        ResumeContentLine(ResumeContentLineKind.paragraph, 'Dart, Flutter'),
      ], tokens);

      expect(_flattenAll(widgets).whereType<pw.Paragraph>(), isNotEmpty);
    });

    test('Beta Template Quality Pass: skillsAsChips renders the paragraph line as a pw.Wrap '
        '(chips) instead of a pw.Paragraph', () {
      const chipTokens = ResumeDesignTokens(
        nameSize: 24,
        headingSize: 14,
        subheadingSize: 11,
        bodySize: 10,
        captionSize: 9,
        pageMargin: 32,
        sectionGap: 14,
        entryGap: 10,
        lineGap: 3,
        inkColor: PdfColors.black,
        inkSoftColor: PdfColors.grey600,
        accentColor: PdfColors.blue,
        dividerColor: PdfColors.grey300,
        skillsAsChips: true,
      );

      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Skills'),
        ResumeContentLine(ResumeContentLineKind.paragraph, 'Dart, Flutter', isSkillsList: true),
      ], chipTokens);

      expect(_flattenAll(widgets).whereType<pw.Paragraph>(), isEmpty);
      expect(_flattenAll(widgets).whereType<pw.Wrap>(), isNotEmpty);
    });

    test(
      'skillsAsChips does NOT apply to a non-Skills paragraph (e.g. a Summary) - real-device '
      'beta fix: a Modern Accent-style archetype with skillsAsChips set previously rendered '
      'the Summary paragraph as comma-split chip fragments too, since the check only looked '
      'at the token, never at which paragraph it was',
      () {
        const chipTokens = ResumeDesignTokens(
          nameSize: 24,
          headingSize: 14,
          subheadingSize: 11,
          bodySize: 10,
          captionSize: 9,
          pageMargin: 32,
          sectionGap: 14,
          entryGap: 10,
          lineGap: 3,
          inkColor: PdfColors.black,
          inkSoftColor: PdfColors.grey600,
          accentColor: PdfColors.blue,
          dividerColor: PdfColors.grey300,
          skillsAsChips: true,
        );

        final widgets = renderContentLines(const [
          ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Summary'),
          ResumeContentLine(ResumeContentLineKind.paragraph, 'Engineer with 5 years, skilled in Dart, Flutter.'),
        ], chipTokens);

        expect(_flattenAll(widgets).whereType<pw.Wrap>(), isEmpty);
        expect(_flattenAll(widgets).whereType<pw.Paragraph>(), isNotEmpty);
      },
    );

    test('Beta Template Quality Pass: an entry with meta renders title and meta on one '
        'line (a pw.Row), not stacked', () {
      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.entryTitle, 'Engineer - Acme'),
        ResumeContentLine(ResumeContentLineKind.entryMeta, '2022-01 - Present'),
      ], tokens);

      final entryColumn = _flattenAll(widgets).whereType<pw.Column>().last;
      expect(entryColumn.children.whereType<pw.Row>(), isNotEmpty);
    });

    test('Beta Template Quality Pass: sectionHeadingStyle.ruleBelow places the divider '
        'after the heading, never before it', () {
      const ruleBelowTokens = ResumeDesignTokens(
        nameSize: 24,
        headingSize: 14,
        subheadingSize: 11,
        bodySize: 10,
        captionSize: 9,
        pageMargin: 32,
        sectionGap: 14,
        entryGap: 10,
        lineGap: 3,
        inkColor: PdfColors.black,
        inkSoftColor: PdfColors.grey600,
        accentColor: PdfColors.blue,
        dividerColor: PdfColors.grey300,
        sectionHeadingStyle: SectionHeadingStyle.ruleBelow,
      );

      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
      ], ruleBelowTokens);

      final flattened = _flattenAll(widgets);
      final headingIndex = flattened.indexWhere((w) => w is pw.Text);
      final dividerIndex = flattened.indexWhere((w) => w is pw.Container);
      expect(headingIndex, greaterThanOrEqualTo(0));
      expect(dividerIndex, greaterThan(headingIndex));
    });

    test('Beta Template Quality Pass: sectionHeadingStyle.label draws no divider at all', () {
      const labelTokens = ResumeDesignTokens(
        nameSize: 24,
        headingSize: 14,
        subheadingSize: 11,
        bodySize: 10,
        captionSize: 9,
        pageMargin: 32,
        sectionGap: 14,
        entryGap: 10,
        lineGap: 3,
        inkColor: PdfColors.black,
        inkSoftColor: PdfColors.grey600,
        accentColor: PdfColors.blue,
        dividerColor: PdfColors.grey300,
        sectionHeadingStyle: SectionHeadingStyle.label,
      );

      final widgets = renderContentLines(const [
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
        ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Education'),
      ], labelTokens);

      expect(widgets.whereType<pw.Container>(), isEmpty);
    });
  });

  group('buildSectionHeading (Beta Template Quality Pass - SectionHeadingStyle.label)', () {
    test('label style reduces heading size and adds letter-spacing, never changing the text', () {
      const labelTokens = ResumeDesignTokens(
        nameSize: 24,
        headingSize: 14,
        subheadingSize: 11,
        bodySize: 10,
        captionSize: 9,
        pageMargin: 32,
        sectionGap: 14,
        entryGap: 10,
        lineGap: 3,
        inkColor: PdfColors.black,
        inkSoftColor: PdfColors.grey600,
        accentColor: PdfColors.blue,
        dividerColor: PdfColors.grey300,
        sectionHeadingStyle: SectionHeadingStyle.label,
      );

      final ruleAboveWidget = buildSectionHeading('Experience', tokens) as pw.Text;
      final labelWidget = buildSectionHeading('Experience', labelTokens) as pw.Text;
      final ruleAboveSpan = ruleAboveWidget.text as pw.TextSpan;
      final labelSpan = labelWidget.text as pw.TextSpan;

      expect(labelSpan.text, 'Experience');
      expect(labelSpan.style?.letterSpacing, isNotNull);
      expect(ruleAboveSpan.style?.letterSpacing, isNull);
      expect(labelSpan.style!.fontSize, lessThan(ruleAboveSpan.style!.fontSize!));
    });
  });
}
