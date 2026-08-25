import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/experience_block.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late ResumeBlockRepository repository;
  late ResumeRepository resumeRepository;
  late ExperienceBlockRepository experienceRepository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteResumeBlockRepository(db);
    resumeRepository = SqfliteResumeRepository(db);
    experienceRepository = SqfliteExperienceBlockRepository(db);
  });

  tearDown(() => db.close());

  Future<int> createResume({String title = 'Backend-Focused'}) {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: title, fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  Future<int> createExperienceBlock({String role = 'Engineer'}) {
    final now = DateTime(2026, 1, 1);
    return experienceRepository.insert(ExperienceBlock(
      id: null,
      role: role,
      company: 'Acme',
      startDate: '2022-01',
      bullets: const ['Did the thing'],
      createdAt: now,
      updatedAt: now,
    ));
  }

  group('attach', () {
    test('attaching a block to a resume creates a row retrievable via getForResume', () async {
      final resumeId = await createResume();
      final blockId = await createExperienceBlock();

      await repository.attach(resumeId, ResumeBlockType.experience, blockId);

      final refs = await repository.getForResume(resumeId);
      expect(refs, hasLength(1));
      expect(refs.single.blockType, ResumeBlockType.experience);
      expect(refs.single.blockId, blockId);
      expect(refs.single.resumeId, resumeId);
    });

    test('successive attaches append at the end - sort_order increases monotonically', () async {
      final resumeId = await createResume();
      final blockA = await createExperienceBlock(role: 'A');
      final blockB = await createExperienceBlock(role: 'B');
      final blockC = await createExperienceBlock(role: 'C');

      await repository.attach(resumeId, ResumeBlockType.experience, blockA);
      await repository.attach(resumeId, ResumeBlockType.experience, blockB);
      await repository.attach(resumeId, ResumeBlockType.experience, blockC);

      final refs = await repository.getForResume(resumeId);
      expect(refs.map((r) => r.blockId).toList(), [blockA, blockB, blockC]);
      expect(refs.map((r) => r.sortOrder).toList(), [0, 1, 2]);
    });
  });

  group('detach', () {
    test('detaching removes only the matching block from the composition', () async {
      final resumeId = await createResume();
      final blockA = await createExperienceBlock(role: 'A');
      final blockB = await createExperienceBlock(role: 'B');
      await repository.attach(resumeId, ResumeBlockType.experience, blockA);
      await repository.attach(resumeId, ResumeBlockType.experience, blockB);

      await repository.detach(resumeId, ResumeBlockType.experience, blockA);

      final refs = await repository.getForResume(resumeId);
      expect(refs, hasLength(1));
      expect(refs.single.blockId, blockB);
    });

    test('detach never deletes the underlying library block itself', () async {
      final resumeId = await createResume();
      final blockId = await createExperienceBlock();
      await repository.attach(resumeId, ResumeBlockType.experience, blockId);

      await repository.detach(resumeId, ResumeBlockType.experience, blockId);

      expect(await experienceRepository.getById(blockId), isNotNull);
    });
  });

  group('getForResume ordering', () {
    test('rows are returned ordered by sort_order, not insertion or id order', () async {
      final resumeId = await createResume();
      final blockA = await createExperienceBlock(role: 'A');
      final blockB = await createExperienceBlock(role: 'B');
      final blockC = await createExperienceBlock(role: 'C');
      await repository.attach(resumeId, ResumeBlockType.experience, blockA);
      await repository.attach(resumeId, ResumeBlockType.experience, blockB);
      await repository.attach(resumeId, ResumeBlockType.experience, blockC);

      final refs = await repository.getForResume(resumeId);
      final reordered = [refs[2], refs[0], refs[1]];
      await repository.reorder(resumeId, reordered);

      final afterReorder = await repository.getForResume(resumeId);
      expect(afterReorder.map((r) => r.blockId).toList(), [blockC, blockA, blockB]);
    });
  });

  group('reorder', () {
    test('persists a new sort_order for every row in the list, in the given order', () async {
      final resumeId = await createResume();
      final blockA = await createExperienceBlock(role: 'A');
      final blockB = await createExperienceBlock(role: 'B');
      await repository.attach(resumeId, ResumeBlockType.experience, blockA);
      await repository.attach(resumeId, ResumeBlockType.experience, blockB);
      final refs = await repository.getForResume(resumeId);

      // Reverse the order.
      await repository.reorder(resumeId, [refs[1], refs[0]]);

      final afterReorder = await repository.getForResume(resumeId);
      expect(afterReorder[0].blockId, blockB);
      expect(afterReorder[0].sortOrder, 0);
      expect(afterReorder[1].blockId, blockA);
      expect(afterReorder[1].sortOrder, 1);
    });

    test('reorder does not affect another resume\'s blocks', () async {
      final resumeIdA = await createResume(title: 'Resume A');
      final resumeIdB = await createResume(title: 'Resume B');
      final blockA1 = await createExperienceBlock(role: 'A1');
      final blockA2 = await createExperienceBlock(role: 'A2');
      final blockB1 = await createExperienceBlock(role: 'B1');
      await repository.attach(resumeIdA, ResumeBlockType.experience, blockA1);
      await repository.attach(resumeIdA, ResumeBlockType.experience, blockA2);
      await repository.attach(resumeIdB, ResumeBlockType.experience, blockB1);

      final refsA = await repository.getForResume(resumeIdA);
      await repository.reorder(resumeIdA, [refsA[1], refsA[0]]);

      final refsB = await repository.getForResume(resumeIdB);
      expect(refsB, hasLength(1));
      expect(refsB.single.blockId, blockB1);
      expect(refsB.single.sortOrder, 0);
    });

    test('reorder runs as a single transaction - the full write either lands completely or not '
        'at all, never a partial rewrite of some rows and not others', () async {
      final resumeId = await createResume();
      final blockIds = <int>[];
      for (var i = 0; i < 4; i++) {
        blockIds.add(await createExperienceBlock(role: 'Role $i'));
      }
      for (final blockId in blockIds) {
        await repository.attach(resumeId, ResumeBlockType.experience, blockId);
      }
      final refs = await repository.getForResume(resumeId);
      final reversed = refs.reversed.toList();

      await repository.reorder(resumeId, reversed);

      // If the transaction had committed only part of the rewrite, this
      // list would show a mix of old and new sort_order values instead of
      // a clean, fully-applied reversal.
      final afterReorder = await repository.getForResume(resumeId);
      expect(afterReorder.map((r) => r.blockId).toList(), reversed.map((r) => r.blockId).toList());
      expect(afterReorder.map((r) => r.sortOrder).toList(), [0, 1, 2, 3]);
    });
  });

  group('setOverride', () {
    test('sets override_json without touching the shared library block', () async {
      final resumeId = await createResume();
      final blockId = await createExperienceBlock();
      await repository.attach(resumeId, ResumeBlockType.experience, blockId);

      await repository.setOverride(
        resumeId,
        ResumeBlockType.experience,
        blockId,
        '["Trimmed bullet"]',
      );

      final refs = await repository.getForResume(resumeId);
      expect(refs.single.overrideJson, '["Trimmed bullet"]');

      final block = await experienceRepository.getById(blockId);
      expect(block!.bullets, ['Did the thing'], reason: 'the shared library block itself must be untouched');
    });

    test('passing null clears a previously-set override', () async {
      final resumeId = await createResume();
      final blockId = await createExperienceBlock();
      await repository.attach(resumeId, ResumeBlockType.experience, blockId);
      await repository.setOverride(resumeId, ResumeBlockType.experience, blockId, '["x"]');

      await repository.setOverride(resumeId, ResumeBlockType.experience, blockId, null);

      final refs = await repository.getForResume(resumeId);
      expect(refs.single.overrideJson, isNull);
    });
  });

  group('getReferencingResumeIds', () {
    test('returns an empty list for a block nothing references', () async {
      final blockId = await createExperienceBlock();
      expect(await repository.getReferencingResumeIds(ResumeBlockType.experience, blockId), isEmpty);
    });

    test('returns every resume id that references the block', () async {
      final blockId = await createExperienceBlock();
      final resumeIdA = await createResume(title: 'Resume A');
      final resumeIdB = await createResume(title: 'Resume B');
      await repository.attach(resumeIdA, ResumeBlockType.experience, blockId);
      await repository.attach(resumeIdB, ResumeBlockType.experience, blockId);

      final referencingIds =
          await repository.getReferencingResumeIds(ResumeBlockType.experience, blockId);

      expect(referencingIds, containsAll([resumeIdA, resumeIdB]));
      expect(referencingIds, hasLength(2));
    });

    test('a block detached from every resume that used it no longer shows as referenced', () async {
      final blockId = await createExperienceBlock();
      final resumeId = await createResume();
      await repository.attach(resumeId, ResumeBlockType.experience, blockId);
      await repository.detach(resumeId, ResumeBlockType.experience, blockId);

      expect(await repository.getReferencingResumeIds(ResumeBlockType.experience, blockId), isEmpty);
    });

    test('does not confuse a certification block and an experience block that happen to share '
        'the same numeric id', () async {
      // block_type + block_id together identify a block - block_id alone
      // is only unique within its own library table, so two blocks of
      // different types can validly share the same id.
      final resumeId = await createResume();
      final experienceBlockId = await createExperienceBlock();
      await repository.attach(resumeId, ResumeBlockType.experience, experienceBlockId);

      final referencingForCertification =
          await repository.getReferencingResumeIds(ResumeBlockType.certification, experienceBlockId);

      expect(referencingForCertification, isEmpty);
    });
  });
}
