// Tests ResumeImportController (features/career/resume/presentation/
// providers/resume_import_providers.dart) through a ProviderContainer with
// every leaf repository provider it transitively reads overridden to a
// throwaway in-memory database - mirrors resume_editor_controller_test.dart's
// exact pattern. The file picker is overridden with
// FakeResumeImportFilePickerService (this feature's own documented fake,
// mirroring FakeToolkitFilePickerService's precedent) pointed at a real
// temp file, since extraction still does real file I/O against whatever
// path is "picked."
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/providers/resume_import_providers.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/custom_section_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/resume/resume_import_file_picker_service.dart';
import 'package:offline_mom/features/career/resume/generate_import_second_pass_use_case.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/fake_ai_engines.dart';
import '../../../../../test_helpers/test_database.dart';

void main() {
  late Database db;
  late Directory tempDir;
  late ResumeRepository resumeRepository;
  late ResumeBlockRepository resumeBlockRepository;
  late FakeResumeImportFilePickerService picker;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    tempDir = await Directory.systemTemp.createTemp('resume_import_controller_test_');
    resumeRepository = SqfliteResumeRepository(db);
    resumeBlockRepository = SqfliteResumeBlockRepository(db);
    picker = FakeResumeImportFilePickerService();

    container = ProviderContainer(
      overrides: [
        resumeImportFilePickerServiceProvider.overrideWithValue(picker),
        resumeRepositoryProvider.overrideWithValue(resumeRepository),
        resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
        experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
        educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
        projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
        certificationBlockRepositoryProvider
            .overrideWithValue(SqfliteCertificationBlockRepository(db)),
        skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
        customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
        generateImportSecondPassUseCaseProvider.overrideWithValue(
          GenerateImportSecondPassUseCase(
            llmEngine: FakeLlmEngine(),
            llmRequestQueue: DefaultLlmRequestQueue(),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<PickedResumeImportFile> writePickedFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return PickedResumeImportFile(
      filePath: file.path,
      originalFilename: name,
      sourceType: DocumentSourceType.txt,
      fileSizeBytes: await file.length(),
    );
  }

  /// A second container sharing this test's db/picker but with a
  /// caller-controlled second-pass model answer - [llmEngine] can't be
  /// reconfigured per test since [FakeLlmEngine]'s fields are immutable, so
  /// the tests that need a specific model response build their own
  /// container via this helper instead of reusing the shared [container].
  ProviderContainer buildContainerWithSecondPassAnswer(String? answer) {
    return ProviderContainer(
      overrides: [
        resumeImportFilePickerServiceProvider.overrideWithValue(picker),
        resumeRepositoryProvider.overrideWithValue(resumeRepository),
        resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
        experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
        educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
        projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
        certificationBlockRepositoryProvider
            .overrideWithValue(SqfliteCertificationBlockRepository(db)),
        skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
        customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
        generateImportSecondPassUseCaseProvider.overrideWithValue(
          GenerateImportSecondPassUseCase(
            llmEngine: FakeLlmEngine(answer: answer),
            llmRequestQueue: DefaultLlmRequestQueue(),
          ),
        ),
      ],
    );
  }

  test('build() starts in ResumeImportIdle', () {
    expect(container.read(resumeImportControllerProvider), isA<ResumeImportIdle>());
  });

  test('pickAndParse() with a cancelled picker (null result) returns to Idle', () async {
    picker.result = null;
    await container.read(resumeImportControllerProvider.notifier).pickAndParse();
    expect(container.read(resumeImportControllerProvider), isA<ResumeImportIdle>());
  });

  test('pickAndParse() with a picked file transitions to Reviewing with a '
      'parsed draft and a filename-derived default title', () async {
    picker.result = await writePickedFile('jane_doe_resume.txt', 'Jane Doe\n\nSKILLS\n\nDart\n');

    await container.read(resumeImportControllerProvider.notifier).pickAndParse();

    final state = container.read(resumeImportControllerProvider);
    expect(state, isA<ResumeImportReviewing>());
    final reviewing = state as ResumeImportReviewing;
    expect(reviewing.title, 'jane_doe_resume');
    expect(reviewing.draft.skills, isNotEmpty);
  });

  test('pickAndParse() surfaces a picker failure as ResumeImportFailed with '
      'the exception\'s own message', () async {
    picker.errorToThrow = ResumeImportPickException('The selected file is empty.');

    await container.read(resumeImportControllerProvider.notifier).pickAndParse();

    final state = container.read(resumeImportControllerProvider);
    expect(state, isA<ResumeImportFailed>());
    expect((state as ResumeImportFailed).message, 'The selected file is empty.');
  });

  test('updateTitle() only applies while Reviewing', () async {
    picker.result = await writePickedFile('resume.txt', 'Jane Doe\n');
    final notifier = container.read(resumeImportControllerProvider.notifier);

    notifier.updateTitle('Should be ignored');
    expect(container.read(resumeImportControllerProvider), isA<ResumeImportIdle>());

    await notifier.pickAndParse();
    notifier.updateTitle('My Custom Title');
    expect((container.read(resumeImportControllerProvider) as ResumeImportReviewing).title,
        'My Custom Title');
  });

  test('confirmImport() persists the resume and transitions to Succeeded, '
      'invalidating the resume list', () async {
    picker.result = await writePickedFile(
      'resume.txt',
      'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
    );
    final notifier = container.read(resumeImportControllerProvider.notifier);
    await notifier.pickAndParse();

    await notifier.confirmImport();

    final state = container.read(resumeImportControllerProvider);
    expect(state, isA<ResumeImportSucceeded>());
    final resumeId = (state as ResumeImportSucceeded).resumeId;
    expect(await resumeRepository.getById(resumeId), isNotNull);
    expect(await resumeBlockRepository.getForResume(resumeId), isNotEmpty);
  });

  test('confirmImport() keeps the reviewed draft and surfaces an error on '
      'failure, rather than discarding what the user already reviewed', () async {
    picker.result = await writePickedFile('resume.txt', 'Jane Doe\n');
    final notifier = container.read(resumeImportControllerProvider.notifier);
    await notifier.pickAndParse();

    // A closed connection is a genuine, real failure - the same
    // forced-failure trick already used elsewhere in this test suite.
    await db.close();

    await notifier.confirmImport();

    final state = container.read(resumeImportControllerProvider);
    expect(state, isA<ResumeImportReviewing>());
    final reviewing = state as ResumeImportReviewing;
    expect(reviewing.isConfirming, isFalse);
    expect(reviewing.error, isNotNull);
    expect(reviewing.draft.fullName, 'Jane Doe');
  });

  group('updateDraft() (docs/v3/01-prd.md §10/§25 Milestone 4 - per-entry-editable review)', () {
    test('only applies while Reviewing, mirroring updateTitle()', () async {
      final notifier = container.read(resumeImportControllerProvider.notifier);

      notifier.updateDraft((d) => d.copyWith(skills: const []));
      expect(container.read(resumeImportControllerProvider), isA<ResumeImportIdle>());
    });

    test('correcting a misclassified Experience entry updates just that entry, in place', () async {
      picker.result = await writePickedFile(
        'resume.txt',
        'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
      );
      final notifier = container.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();
      final originalDraft =
          (container.read(resumeImportControllerProvider) as ResumeImportReviewing).draft;
      expect(originalDraft.experience, isNotEmpty);
      final original = originalDraft.experience.first;

      final corrected = original.copyWith(role: 'Senior Engineer', company: 'Acme Corp');
      notifier.updateDraft((d) {
        final list = [...d.experience];
        list[0] = corrected;
        return d.copyWith(experience: list);
      });

      final updatedDraft =
          (container.read(resumeImportControllerProvider) as ResumeImportReviewing).draft;
      expect(updatedDraft.experience.single.role, 'Senior Engineer');
      expect(updatedDraft.experience.single.company, 'Acme Corp');
      // Every other field survives the correction untouched.
      expect(updatedDraft.experience.single.bullets, original.bullets);
    });

    test('removing an entry takes it out of the draft entirely, not just hides it', () async {
      picker.result = await writePickedFile(
        'resume.txt',
        'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
      );
      final notifier = container.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();
      expect(
        (container.read(resumeImportControllerProvider) as ResumeImportReviewing).draft.experience,
        isNotEmpty,
      );

      notifier.updateDraft((d) => d.copyWith(experience: const []));

      expect(
        (container.read(resumeImportControllerProvider) as ResumeImportReviewing).draft.experience,
        isEmpty,
      );
    });

    test('confirmImport() persists the corrected entry, not the originally-parsed one', () async {
      picker.result = await writePickedFile(
        'resume.txt',
        'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
      );
      final notifier = container.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();

      notifier.updateDraft((d) {
        final list = [...d.experience];
        list[0] = list[0].copyWith(role: 'Corrected Role');
        return d.copyWith(experience: list);
      });
      await notifier.confirmImport();

      final resumeId =
          (container.read(resumeImportControllerProvider) as ResumeImportSucceeded).resumeId;
      final blockRefs = await resumeBlockRepository.getForResume(resumeId);
      final experienceRepo = SqfliteExperienceBlockRepository(db);
      final persisted = await experienceRepo.getById(blockRefs.single.blockId);
      expect(persisted!.role, 'Corrected Role');
    });

    test('removing every Experience entry before confirming persists none - the removal genuinely '
        'took effect, not just in the review UI', () async {
      picker.result = await writePickedFile(
        'resume.txt',
        'Jane Doe\n\nEXPERIENCE\n\nEngineer - Acme\n2020 - 2021\n- Did the thing.\n',
      );
      final notifier = container.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();

      notifier.updateDraft((d) => d.copyWith(experience: const <ExperienceBlock>[]));
      await notifier.confirmImport();

      final resumeId =
          (container.read(resumeImportControllerProvider) as ResumeImportSucceeded).resumeId;
      final blockRefs = await resumeBlockRepository.getForResume(resumeId);
      expect(blockRefs, isEmpty);
    });
  });

  group('runImportSecondPass() (docs/v3/01-prd.md §10/§25 Milestone 4 - optional LLM-assisted '
      'import second pass)', () {
    test('does nothing while not Reviewing', () async {
      final localContainer = buildContainerWithSecondPassAnswer('Skills\nDart');
      addTearDown(localContainer.dispose);
      final notifier = localContainer.read(resumeImportControllerProvider.notifier);

      await notifier.runImportSecondPass();

      expect(localContainer.read(resumeImportControllerProvider), isA<ResumeImportIdle>());
    });

    test('merges newly-structured entries into the draft and clears isRunningSecondPass', () async {
      final localContainer = buildContainerWithSecondPassAnswer('Skills\nDart, Flutter');
      addTearDown(localContainer.dispose);
      picker.result = await writePickedFile(
        'resume.txt',
        'Jane Doe\n\nDart, Flutter\n',
      );
      final notifier = localContainer.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();
      final beforeState =
          localContainer.read(resumeImportControllerProvider) as ResumeImportReviewing;
      expect(beforeState.draft.unclassifiedText, isNotEmpty);

      await notifier.runImportSecondPass();

      final afterState =
          localContainer.read(resumeImportControllerProvider) as ResumeImportReviewing;
      expect(afterState.isRunningSecondPass, isFalse);
      expect(afterState.draft.skills.map((s) => s.name), containsAll(['Dart', 'Flutter']));
    });

    test('leaves the draft unchanged when the model is unavailable, rather than throwing', () async {
      final localContainer = ProviderContainer(
        overrides: [
          resumeImportFilePickerServiceProvider.overrideWithValue(picker),
          resumeRepositoryProvider.overrideWithValue(resumeRepository),
          resumeBlockRepositoryProvider.overrideWithValue(resumeBlockRepository),
          experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
          educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
          projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
          certificationBlockRepositoryProvider
              .overrideWithValue(SqfliteCertificationBlockRepository(db)),
          skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
          customSectionBlockRepositoryProvider.overrideWithValue(SqfliteCustomSectionBlockRepository(db)),
          generateImportSecondPassUseCaseProvider.overrideWithValue(
            GenerateImportSecondPassUseCase(
              llmEngine: FakeLlmEngine(errorToThrow: StateError('model not downloaded')),
              llmRequestQueue: DefaultLlmRequestQueue(),
            ),
          ),
        ],
      );
      addTearDown(localContainer.dispose);
      picker.result = await writePickedFile('resume.txt', 'Jane Doe\n\nSome stray text.\n');
      final notifier = localContainer.read(resumeImportControllerProvider.notifier);
      await notifier.pickAndParse();
      final beforeDraft =
          (localContainer.read(resumeImportControllerProvider) as ResumeImportReviewing).draft;

      await notifier.runImportSecondPass();

      final afterDraft =
          (localContainer.read(resumeImportControllerProvider) as ResumeImportReviewing).draft;
      expect(afterDraft.unclassifiedText, beforeDraft.unclassifiedText);
    });
  });

  test('reset() returns to Idle from any state', () async {
    picker.result = await writePickedFile('resume.txt', 'Jane Doe\n');
    final notifier = container.read(resumeImportControllerProvider.notifier);
    await notifier.pickAndParse();
    expect(container.read(resumeImportControllerProvider), isA<ResumeImportReviewing>());

    notifier.reset();

    expect(container.read(resumeImportControllerProvider), isA<ResumeImportIdle>());
  });
}
