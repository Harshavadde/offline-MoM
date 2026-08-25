import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/template/archetypes/classic_single_column.dart';
import 'package:offline_mom/services/resume/template/archetypes/compact_technical.dart';
import 'package:offline_mom/services/resume/template/archetypes/creative_visual.dart';
import 'package:offline_mom/services/resume/template/archetypes/entry_level_student.dart';
import 'package:offline_mom/services/resume/template/archetypes/executive_summary_led.dart';
import 'package:offline_mom/services/resume/template/archetypes/government_dense.dart';
import 'package:offline_mom/services/resume/template/archetypes/minimalist_monochrome.dart';
import 'package:offline_mom/services/resume/template/archetypes/modern_accent_column.dart';
import 'package:offline_mom/services/resume/template/archetypes/two_column_right.dart';
import 'package:offline_mom/services/resume/template/archetypes/two_column_sidebar.dart';
import 'package:offline_mom/services/resume/template/resume_design_tokens.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';
import 'package:pdf/widgets.dart' as pw;

/// Exercises all 10 archetype build functions (4 from Milestone 1, 6 from
/// Milestone 4) against both an empty and a fully-populated snapshot with
/// every catalog token preset they can be paired with - docs/v3/01-prd.md
/// §25's "empty snapshot, realistic/full snapshot, no throw" requirement,
/// for every archetype.
void main() {
  ResumeSnapshot emptySnapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: ''),
    );
  }

  ResumeSnapshot fullSnapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        phone: '555-1234',
        location: 'Remote',
        links: [ResumeLink(label: 'GitHub', url: 'https://github.com/example')],
      ),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          startDate: '2022-01',
          bullets: ['Shipped the thing', 'Led the team'],
        ),
      ],
      education: const [
        ResolvedEducationEntry(
          sourceBlockId: 2,
          institution: 'State University',
          degree: 'B.Sc Computer Science',
          startDate: '2015-09',
          endDate: '2019-05',
        ),
      ],
      projects: const [
        ResolvedProjectEntry(sourceBlockId: 3, name: 'Side Project', bullets: ['Built a thing']),
      ],
      certifications: const [
        ResolvedCertificationEntry(sourceBlockId: 4, name: 'AWS Certified', issuer: 'Amazon'),
      ],
      skills: const [
        ResolvedSkillEntry(sourceBlockId: 5, name: 'Dart', category: SkillCategory.technical),
        ResolvedSkillEntry(sourceBlockId: 6, name: 'Flutter', category: SkillCategory.technical),
      ],
    );
  }

  void run(
    String archetypeId,
    List<pw.Widget> Function(ResumeSnapshot snapshot, ResumeDesignTokens tokens) build,
  ) {
    group(archetypeId, () {
      // Beta scope (post-Milestone 4): each archetype ships with exactly
      // one curated preset in the catalog, not both - see
      // resume_template_catalog.dart's own doc comment.
      final spec = ResumeTemplateCatalog.all.firstWhere((s) => s.archetypeId == archetypeId);

      test('renders an empty snapshot without throwing', () {
        expect(() => build(emptySnapshot(), spec.tokens), returnsNormally);
      });

      test('renders an empty snapshot to a non-empty widget list', () {
        expect(build(emptySnapshot(), spec.tokens), isNotEmpty);
      });

      test('renders a fully-populated snapshot without throwing', () {
        expect(() => build(fullSnapshot(), spec.tokens), returnsNormally);
      });

      test('renders a fully-populated snapshot to a non-empty widget list', () {
        expect(build(fullSnapshot(), spec.tokens), isNotEmpty);
      });
    });
  }

  run(ResumeArchetypeIds.classicSingleColumn, buildClassicSingleColumnPages);
  run(ResumeArchetypeIds.modernAccentColumn, buildModernAccentColumnPages);
  run(ResumeArchetypeIds.twoColumnSidebar, buildTwoColumnSidebarPages);
  run(ResumeArchetypeIds.compactTechnical, buildCompactTechnicalPages);
  run(ResumeArchetypeIds.executiveSummaryLed, buildExecutiveSummaryLedPages);
  run(ResumeArchetypeIds.creativeVisual, buildCreativeVisualPages);
  run(ResumeArchetypeIds.entryLevelStudent, buildEntryLevelStudentPages);
  run(ResumeArchetypeIds.minimalistMonochrome, buildMinimalistMonochromePages);
  run(ResumeArchetypeIds.governmentDense, buildGovernmentDensePages);
  run(ResumeArchetypeIds.twoColumnRight, buildTwoColumnRightPages);

  test('two-column-sidebar produces exactly one pw.Partitions (the pagination-safe '
      'sidebar+main layout - see the archetype\'s own doc comment for why not pw.Row)', () {
    final spec = ResumeTemplateCatalog.specById('two-column-sidebar-cool');
    final widgets = buildTwoColumnSidebarPages(fullSnapshot(), spec.tokens);
    expect(widgets.whereType<pw.Partitions>(), hasLength(1));
  });

  test('two-column-right (the tenth archetype) also produces exactly one '
      'pw.Partitions, reusing the same pagination-safe composition', () {
    final spec = ResumeTemplateCatalog.specById('two-column-right-warm');
    final widgets = buildTwoColumnRightPages(fullSnapshot(), spec.tokens);
    expect(widgets.whereType<pw.Partitions>(), hasLength(1));
  });

  test('two-column-right actually places its sidebar Partition last, unlike two-column-sidebar '
      'which places it first - the whole point of the tenth archetype', () {
    final spec = ResumeTemplateCatalog.specById('two-column-right-warm');

    final leftWidgets = buildTwoColumnSidebarPages(fullSnapshot(), spec.tokens);
    final leftPartitions = (leftWidgets.single as pw.Partitions).children;
    // The sidebar Partition is the only one with a fixed 168pt width
    // (widened from 140pt in the product composition-audit pass - see
    // two_column_sidebar.dart's own doc comment at the call site).
    expect(leftPartitions.first.width, 168);

    final rightWidgets = buildTwoColumnRightPages(fullSnapshot(), spec.tokens);
    final rightPartitions = rightWidgets.whereType<pw.Partitions>().single.children;
    // Balanced Two-Column's rail is 190pt (single-template prototype
    // pass, second round - paired with its own larger density profile),
    // not the shared 168pt Two-Column Sidebar still uses.
    expect(rightPartitions.last.width, 190);
    expect(rightPartitions.first.width, isNot(190));
  });

  test(
    'two-column-right (product single-template prototype pass) renders its header as a '
    'separate, full-width widget before the pw.Partitions, unlike two-column-sidebar - the '
    'one structural composition fix this pass made',
    () {
      final rightSpec = ResumeTemplateCatalog.specById('two-column-right-warm');
      final rightWidgets = buildTwoColumnRightPages(fullSnapshot(), rightSpec.tokens);
      // 3 top-level widgets: the header, a spacer, then the Partitions -
      // not folded into the rail column's own content.
      expect(rightWidgets, hasLength(3));
      expect(rightWidgets.first, isNot(isA<pw.Partitions>()));
      expect(rightWidgets.last, isA<pw.Partitions>());

      final leftSpec = ResumeTemplateCatalog.specById('two-column-sidebar-cool');
      final leftWidgets = buildTwoColumnSidebarPages(fullSnapshot(), leftSpec.tokens);
      // Two-Column Sidebar is deliberately unchanged: the header still
      // renders inside the narrow rail column, not pulled out.
      expect(leftWidgets, hasLength(1));
      expect(leftWidgets.single, isA<pw.Partitions>());
    },
  );

  test('classic-single-column never produces a pw.Partitions (single column, no sidebar risk)', () {
    final spec = ResumeTemplateCatalog.specById('classic-single-column-warm');
    final widgets = buildClassicSingleColumnPages(fullSnapshot(), spec.tokens);
    expect(widgets.whereType<pw.Partitions>(), isEmpty);
  });
}
