import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_link.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/models/skill_entry.dart';

void main() {
  ResumeSnapshot fullSnapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1, 12, 30),
      profile: const ResumeSnapshotProfile(
        fullName: 'Jane Doe',
        email: 'jane@example.com',
        phone: '555-1234',
        location: 'Remote',
        links: [ResumeLink(label: 'Portfolio', url: 'https://example.com')],
      ),
      experience: const [
        ResolvedExperienceEntry(
          sourceBlockId: 1,
          role: 'Senior Engineer',
          company: 'Acme Corp',
          location: 'Remote',
          startDate: '2022-01',
          endDate: null,
          bullets: ['Shipped the thing', 'Fixed the other thing'],
        ),
        ResolvedExperienceEntry(
          sourceBlockId: 2,
          role: 'Engineer',
          company: 'Beta Inc',
          startDate: '2019-01',
          endDate: '2022-01',
          bullets: ['Built the first thing'],
        ),
      ],
      education: const [
        ResolvedEducationEntry(
          sourceBlockId: 10,
          institution: 'State University',
          degree: 'B.Sc Computer Science',
          fieldOfStudy: 'Computer Science',
          startDate: '2015-09',
          endDate: '2019-06',
          details: ['Magna Cum Laude'],
        ),
      ],
      projects: const [
        ResolvedProjectEntry(
          sourceBlockId: 20,
          name: 'Resume Builder',
          link: 'https://github.com/example/project',
          bullets: ['Built X', 'Deployed Y'],
        ),
      ],
      certifications: const [
        ResolvedCertificationEntry(
          sourceBlockId: 30,
          name: 'AWS Solutions Architect',
          issuer: 'Amazon',
          issuedDate: '2024-05',
          credentialUrl: 'https://example.com/cred/123',
        ),
      ],
      skills: const [
        ResolvedSkillEntry(sourceBlockId: 40, name: 'Flutter', category: SkillCategory.technical),
        ResolvedSkillEntry(sourceBlockId: 41, name: 'Communication', category: SkillCategory.soft),
      ],
    );
  }

  group('complete round trip', () {
    test('toMap then fromMap reproduces an equal snapshot, field for field', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped, snapshot);
    });

    test('profile equality compares links by value, not by instance identity', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.profile, snapshot.profile);
      expect(roundTripped.profile.hashCode, snapshot.profile.hashCode);
    });

    test('toJson/fromJson round-trips identically to toMap/fromMap', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromJson(snapshot.toJson());

      expect(roundTripped, snapshot);
    });

    test('every experience entry, in order, survives the round trip with its bullets intact', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.experience, hasLength(2));
      expect(roundTripped.experience[0].role, 'Senior Engineer');
      expect(roundTripped.experience[0].bullets, ['Shipped the thing', 'Fixed the other thing']);
      expect(roundTripped.experience[1].role, 'Engineer');
      expect(roundTripped.experience[1].endDate, '2022-01');
    });

    test('nested profile links survive the round trip', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.profile.links, hasLength(1));
      expect(roundTripped.profile.links.single.label, 'Portfolio');
      expect(roundTripped.profile.links.single.url, 'https://example.com');
    });

    test('education, project, certification, and skill entries all survive the round trip', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.education.single.institution, 'State University');
      expect(roundTripped.education.single.details, ['Magna Cum Laude']);
      expect(roundTripped.projects.single.name, 'Resume Builder');
      expect(roundTripped.projects.single.bullets, ['Built X', 'Deployed Y']);
      expect(roundTripped.certifications.single.name, 'AWS Solutions Architect');
      expect(roundTripped.skills.map((s) => s.name).toList(), ['Flutter', 'Communication']);
      expect(roundTripped.skills[0].category, SkillCategory.technical);
      expect(roundTripped.skills[1].category, SkillCategory.soft);
    });
  });

  group('nullable fields', () {
    test('every optional Profile field round-trips as null when never set', () {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      );

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.profile.email, isNull);
      expect(roundTripped.profile.phone, isNull);
      expect(roundTripped.profile.location, isNull);
      expect(roundTripped.profile.links, isEmpty);
    });

    test('endDate null (meaning "Present") round-trips as null, not lost or coerced', () {
      const entry = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Engineer',
        company: 'Acme',
        startDate: '2022-01',
        endDate: null,
      );

      final roundTripped = ResolvedExperienceEntry.fromMap(entry.toMap());

      expect(roundTripped.endDate, isNull);
    });

    test('optional Education fields (fieldOfStudy, endDate) round-trip as null when unset', () {
      const entry = ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'B.Sc',
        startDate: '2015-09',
      );

      final roundTripped = ResolvedEducationEntry.fromMap(entry.toMap());

      expect(roundTripped.fieldOfStudy, isNull);
      expect(roundTripped.endDate, isNull);
    });

    test('optional Project field (link) round-trips as null when unset', () {
      const entry = ResolvedProjectEntry(sourceBlockId: 1, name: 'Project');

      final roundTripped = ResolvedProjectEntry.fromMap(entry.toMap());

      expect(roundTripped.link, isNull);
    });

    test('optional Certification fields (issuedDate, credentialUrl) round-trip as null when unset',
        () {
      const entry = ResolvedCertificationEntry(sourceBlockId: 1, name: 'Cert', issuer: 'Issuer');

      final roundTripped = ResolvedCertificationEntry.fromMap(entry.toMap());

      expect(roundTripped.issuedDate, isNull);
      expect(roundTripped.credentialUrl, isNull);
    });
  });

  group('empty lists', () {
    test('a snapshot with no blocks in any section round-trips with every list empty, not null',
        () {
      final snapshot = ResumeSnapshot(
        resumeId: 1,
        compiledAt: DateTime(2026, 1, 1),
        profile: const ResumeSnapshotProfile(fullName: 'Jane Doe'),
      );

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.experience, isEmpty);
      expect(roundTripped.education, isEmpty);
      expect(roundTripped.projects, isEmpty);
      expect(roundTripped.certifications, isEmpty);
      expect(roundTripped.skills, isEmpty);
    });

    test('an experience entry with no bullets round-trips with an empty bullets list', () {
      const entry = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Engineer',
        company: 'Acme',
        startDate: '2022-01',
      );

      final roundTripped = ResolvedExperienceEntry.fromMap(entry.toMap());

      expect(roundTripped.bullets, isEmpty);
    });
  });

  group('override_json applicability', () {
    test('an override-trimmed bullets list on an Experience entry round-trips exactly as given - '
        'the compiler is responsible for applying the trim before constructing this entry, this '
        'DTO just needs to preserve whatever list it is handed', () {
      const trimmedEntry = ResolvedExperienceEntry(
        sourceBlockId: 1,
        role: 'Engineer',
        company: 'Acme',
        startDate: '2022-01',
        bullets: ['Only this one bullet survived the override'],
      );

      final roundTripped = ResolvedExperienceEntry.fromMap(trimmedEntry.toMap());

      expect(roundTripped.bullets, ['Only this one bullet survived the override']);
    });

    test('an override-trimmed details list on an Education entry round-trips exactly as given', () {
      const trimmedEntry = ResolvedEducationEntry(
        sourceBlockId: 1,
        institution: 'State University',
        degree: 'B.Sc',
        startDate: '2015-09',
        details: ['Only the trimmed detail'],
      );

      final roundTripped = ResolvedEducationEntry.fromMap(trimmedEntry.toMap());

      expect(roundTripped.details, ['Only the trimmed detail']);
    });

    test('an override-trimmed bullets list on a Project entry round-trips exactly as given', () {
      const trimmedEntry = ResolvedProjectEntry(
        sourceBlockId: 1,
        name: 'Project',
        bullets: ['Only the trimmed bullet'],
      );

      final roundTripped = ResolvedProjectEntry.fromMap(trimmedEntry.toMap());

      expect(roundTripped.bullets, ['Only the trimmed bullet']);
    });

    test('ResolvedCertificationEntry has no override-capable list field - its serialized map '
        'contains exactly its five documented keys and nothing resembling bullets/details/override',
        () {
      const entry = ResolvedCertificationEntry(sourceBlockId: 1, name: 'Cert', issuer: 'Issuer');

      final map = entry.toMap();

      expect(
        map.keys.toSet(),
        {'source_block_id', 'name', 'issuer', 'issued_date', 'credential_url'},
        reason: 'adding an override-capable field here, even for symmetry with Experience/'
            'Project/Education, would silently violate the frozen contract',
      );
    });

    test('ResolvedSkillEntry has no override-capable list field - its serialized map contains '
        'exactly its three documented keys and nothing resembling bullets/details/override', () {
      const entry = ResolvedSkillEntry(sourceBlockId: 1, name: 'Flutter', category: SkillCategory.technical);

      final map = entry.toMap();

      expect(
        map.keys.toSet(),
        {'source_block_id', 'name', 'category'},
        reason: 'a skill has nothing to trim - this DTO structurally cannot carry an override',
      );
    });
  });

  group('no loss of nested data', () {
    test('multiple entries of every type, with distinct field values, all survive independently -'
        ' no entry is dropped, duplicated, or merged with another', () {
      final snapshot = fullSnapshot();

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.experience.map((e) => e.sourceBlockId).toList(), [1, 2]);
      expect(roundTripped.skills.map((s) => s.sourceBlockId).toList(), [40, 41]);
    });

    test('a compiledAt timestamp with sub-second-irrelevant precision survives the round trip', () {
      final snapshot = ResumeSnapshot(
        resumeId: 7,
        compiledAt: DateTime(2026, 3, 15, 9, 5, 42),
        profile: const ResumeSnapshotProfile(fullName: 'X'),
      );

      final roundTripped = ResumeSnapshot.fromMap(snapshot.toMap());

      expect(roundTripped.compiledAt, snapshot.compiledAt);
      expect(roundTripped.resumeId, 7);
    });
  });
}
