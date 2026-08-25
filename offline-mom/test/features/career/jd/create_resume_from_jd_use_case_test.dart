// Tests CreateResumeFromJdUseCase
// (lib/features/career/jd/create_resume_from_jd_use_case.dart) - R-7 §3
// ("Create resume from a Job Description"). Real Sqflite repositories
// against a throwaway in-memory database, no mocks - mirrors
// create_resume_from_profile_use_case_test.dart's own style, since this use
// case is a thin composition on top of that one.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/jd/create_resume_from_jd_use_case.dart';
import 'package:offline_mom/features/career/resume/create_resume_from_profile_use_case.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/job_description.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late ExperienceBlockRepository experienceRepository;
  late CreateResumeFromJdUseCase useCase;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    experienceRepository = SqfliteExperienceBlockRepository(db);
    useCase = CreateResumeFromJdUseCase(
      resumeRepository: resumeRepository,
      resumeBlockRepository: resumeBlockRepository,
      createResumeFromProfileUseCase: CreateResumeFromProfileUseCase(
        resumeRepository: resumeRepository,
        resumeBlockRepository: resumeBlockRepository,
      ),
    );
  });

  tearDown(() => db.close());

  Future<int> setUpProfileWithContent() async {
    final now = DateTime(2026, 1, 1);
    final profileId = await resumeRepository.insert(Resume(
      id: null,
      title: 'My Profile',
      fullName: 'Jane Doe',
      isProfile: true,
      createdAt: now,
      updatedAt: now,
    ));
    await resumeRepository.setAsProfile(profileId);

    for (var i = 1; i <= 3; i++) {
      final expId = await experienceRepository.insert(ExperienceBlock(
        id: null,
        role: 'Role $i',
        company: 'Company $i',
        startDate: '2020-01',
        bullets: const ['Did the thing'],
        createdAt: now,
        updatedAt: now,
      ));
      await resumeBlockRepository.attach(profileId, ResumeBlockType.experience, expId);
    }
    return profileId;
  }

  const jd = ParsedJobDescription(
    rawText: 'We need a backend engineer with Kubernetes experience.',
    title: 'Backend Engineer',
    company: 'Acme Corp',
    requirements: ['Kubernetes', 'Python'],
  );

  test('throws NoProfileException when no profile has been set up yet', () async {
    await expectLater(useCase(jd), throwsA(isA<NoProfileException>()));
  });

  test('creates a new, non-profile resume titled from the JD title and company', () async {
    await setUpProfileWithContent();

    final newId = await useCase(jd);
    final newResume = (await resumeRepository.getById(newId))!;

    expect(newResume.isProfile, isFalse);
    expect(newResume.title, 'Backend Engineer at Acme Corp');
    expect(newResume.fullName, 'Jane Doe');
  });

  test('falls back to a generic title when the JD has no title/company', () async {
    await setUpProfileWithContent();
    const bareJd = ParsedJobDescription(rawText: 'Some job posting with no clear title.');

    final newId = await useCase(bareJd);
    final newResume = (await resumeRepository.getById(newId))!;

    expect(newResume.title, 'Tailored Resume');
  });

  test('includes every one of the profile\'s blocks - never fabricates content '
      'beyond what the profile already has', () async {
    final profileId = await setUpProfileWithContent();

    final newId = await useCase(jd);
    final newRefs = await resumeBlockRepository.getForResume(newId);

    expect(newRefs, hasLength(3));
    expect(newRefs.every((r) => r.blockType == ResumeBlockType.experience), isTrue);

    // Same underlying blocks, not duplicated copies.
    final profileRefs = await resumeBlockRepository.getForResume(profileId);
    final profileBlockIds = profileRefs.map((r) => r.blockId).toSet();
    final newBlockIds = newRefs.map((r) => r.blockId).toSet();
    expect(newBlockIds, profileBlockIds);
    expect(await experienceRepository.getAll(), hasLength(3));
  });
}
