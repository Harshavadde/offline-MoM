// Tests the pure helpers in
// lib/services/resume/resume_import_second_pass.dart (docs/v3/01-prd.md
// §10, Milestone 4) - ratio calculation, threshold, and merge.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/skill_entry.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';
import 'package:offline_mom/services/resume/resume_import_second_pass.dart';

void main() {
  final now = DateTime(2024, 1, 1);

  ExperienceBlock experience({required String role, required String company, List<String> bullets = const []}) {
    return ExperienceBlock(
      id: null,
      role: role,
      company: company,
      startDate: '2020-01',
      bullets: bullets,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('importUnclassifiedRatio', () {
    test('is 0 when there is no unclassified text', () {
      final draft = ParsedResumeDraft(experience: [experience(role: 'Engineer', company: 'Acme')]);
      expect(importUnclassifiedRatio(draft), 0);
    });

    test('is 0 for a completely empty draft (no division by zero)', () {
      const draft = ParsedResumeDraft();
      expect(importUnclassifiedRatio(draft), 0);
    });

    test('is 1 when there is only unclassified text and nothing structured', () {
      const draft = ParsedResumeDraft(unclassifiedText: ['Some leftover paragraph.']);
      expect(importUnclassifiedRatio(draft), 1);
    });

    test('is the character ratio of unclassified vs. classified+unclassified content', () {
      // classified chars: 'Engineer' (8) + 'Acme' (4) + 'Did it.' (7) = 19
      final draft = ParsedResumeDraft(
        experience: [experience(role: 'Engineer', company: 'Acme', bullets: const ['Did it.'])],
        unclassifiedText: const ['0123456789'], // 10 unclassified chars
      );
      // total = 29; ratio = 10/29
      expect(importUnclassifiedRatio(draft), closeTo(10 / 29, 0.0001));
    });

    test('excludes contact info (fullName/email/phone/location/links) from both sides', () {
      final draft = ParsedResumeDraft(
        fullName: 'A Very Long Full Name That Would Skew The Ratio If Counted',
        email: 'jane@example.com',
        experience: [experience(role: 'AB', company: 'CD')], // 4 classified chars
        unclassifiedText: const ['XY'], // 2 unclassified chars
      );
      expect(importUnclassifiedRatio(draft), closeTo(2 / 6, 0.0001));
    });
  });

  group('shouldOfferImportSecondPass', () {
    test('false when there is no unclassified text at all', () {
      final draft = ParsedResumeDraft(experience: [experience(role: 'Engineer', company: 'Acme')]);
      expect(shouldOfferImportSecondPass(draft), isFalse);
    });

    test('false when the unclassified ratio is at or below the threshold', () {
      final draft = ParsedResumeDraft(
        experience: [
          experience(
            role: 'A very long role title used to keep the ratio low',
            company: 'A very long company name used the same way',
          ),
        ],
        unclassifiedText: const ['short'],
      );
      expect(importUnclassifiedRatio(draft), lessThanOrEqualTo(kImportSecondPassRatioThreshold));
      expect(shouldOfferImportSecondPass(draft), isFalse);
    });

    test('true when the unclassified ratio exceeds the threshold', () {
      final draft = ParsedResumeDraft(
        experience: [experience(role: 'Eng', company: 'Co')],
        unclassifiedText: const [
          'A long leftover paragraph that the deterministic parser could not classify at all.',
        ],
      );
      expect(importUnclassifiedRatio(draft), greaterThan(kImportSecondPassRatioThreshold));
      expect(shouldOfferImportSecondPass(draft), isTrue);
    });
  });

  group('mergeImportSecondPass', () {
    test('appends second-pass entries after first-pass entries, never replacing or reordering them', () {
      final firstPassEntry = experience(role: 'First', company: 'FirstCo');
      final secondPassEntry = experience(role: 'Second', company: 'SecondCo');

      final original = ParsedResumeDraft(
        fullName: 'Jane Doe',
        experience: [firstPassEntry],
        unclassifiedText: const ['leftover'],
      );
      final secondPass = ParsedResumeDraft(experience: [secondPassEntry]);

      final merged = mergeImportSecondPass(original, secondPass);

      expect(merged.experience, [firstPassEntry, secondPassEntry]);
    });

    test('replaces unclassifiedText with whatever the second pass still could not classify', () {
      const original = ParsedResumeDraft(unclassifiedText: ['a', 'b', 'c']);
      final secondPass = ParsedResumeDraft(
        skills: [SkillEntry(id: null, name: 'Dart', category: SkillCategory.technical, createdAt: now)],
        unclassifiedText: const ['c'],
      );

      final merged = mergeImportSecondPass(original, secondPass);

      expect(merged.unclassifiedText, ['c']);
    });

    test('preserves contact info and warnings from the original, never the second pass', () {
      const original = ParsedResumeDraft(
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        warnings: ['Original warning.'],
      );
      const secondPass = ParsedResumeDraft(warnings: ['Second-pass warning that must be discarded.']);

      final merged = mergeImportSecondPass(original, secondPass);

      expect(merged.fullName, 'Jane Doe');
      expect(merged.email, 'jane@example.com');
      expect(merged.warnings, ['Original warning.']);
    });
  });
}
