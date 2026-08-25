import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/suggested_edit.dart';
import 'package:offline_mom/repositories/suggested_edit_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late SuggestedEditRepository repository;

  setUp(() async {
    db = await openTestDatabase();
    repository = SqfliteSuggestedEditRepository(db);
  });

  tearDown(() => db.close());

  SuggestedEdit buildEdit({
    int resumeId = 1,
    ResumeBlockType? targetBlockType = ResumeBlockType.experience,
    int? targetBlockId = 7,
    SuggestedEditStatus status = SuggestedEditStatus.pending,
    DateTime? createdAt,
  }) {
    return SuggestedEdit(
      id: null,
      resumeId: resumeId,
      targetBlockType: targetBlockType,
      targetBlockId: targetBlockId,
      fieldName: 'bullets',
      originalValue: 'Worked on Kubernetes deployments',
      suggestedValue: 'Led Kubernetes deployment automation',
      sourceRequirement: 'Kubernetes',
      status: status,
      createdAt: createdAt ?? DateTime(2026, 1, 1),
    );
  }

  test('insert then getById returns the same suggestion, pending by default', () async {
    final id = await repository.insert(buildEdit());

    final fetched = await repository.getById(id);

    expect(fetched, isNotNull);
    expect(fetched!.status, SuggestedEditStatus.pending);
    expect(fetched.originalValue, 'Worked on Kubernetes deployments');
    expect(fetched.suggestedValue, 'Led Kubernetes deployment automation');
    expect(fetched.sourceRequirement, 'Kubernetes');
    expect(fetched.targetBlockType, ResumeBlockType.experience);
    expect(fetched.targetBlockId, 7);
    expect(fetched.resolvedAt, isNull);
  });

  test('insert accepts a profile-level suggestion with null target fields', () async {
    final id = await repository.insert(
      buildEdit(targetBlockType: null, targetBlockId: null),
    );

    final fetched = await repository.getById(id);

    expect(fetched!.targetBlockType, isNull);
    expect(fetched.targetBlockId, isNull);
  });

  test('getById returns null for an id that does not exist', () async {
    expect(await repository.getById(999), isNull);
  });

  test('resolve moves a suggestion to accepted and stamps resolvedAt', () async {
    final id = await repository.insert(buildEdit());
    final resolvedAt = DateTime(2026, 1, 2, 10);

    await repository.resolve(id, SuggestedEditStatus.accepted, resolvedAt);

    final fetched = await repository.getById(id);
    expect(fetched!.status, SuggestedEditStatus.accepted);
    expect(fetched.resolvedAt, resolvedAt);
    // resolve never touches the suggested text itself.
    expect(fetched.suggestedValue, 'Led Kubernetes deployment automation');
  });

  test('resolve to rejected leaves originalValue untouched', () async {
    final id = await repository.insert(buildEdit());

    await repository.resolve(id, SuggestedEditStatus.rejected, DateTime(2026, 1, 2));

    final fetched = await repository.getById(id);
    expect(fetched!.status, SuggestedEditStatus.rejected);
    expect(fetched.originalValue, 'Worked on Kubernetes deployments');
  });

  test('delete removes the row', () async {
    final id = await repository.insert(buildEdit());

    await repository.delete(id);

    expect(await repository.getById(id), isNull);
  });

  test('getForResume returns only that resume\'s suggestions, most recent first', () async {
    await repository.insert(buildEdit(resumeId: 1, createdAt: DateTime(2026, 1, 1)));
    final secondId = await repository.insert(
      buildEdit(resumeId: 1, createdAt: DateTime(2026, 1, 2)),
    );
    await repository.insert(buildEdit(resumeId: 2, createdAt: DateTime(2026, 1, 1)));

    final forResumeOne = await repository.getForResume(1);

    expect(forResumeOne, hasLength(2));
    expect(forResumeOne.first.id, secondId);
    expect(forResumeOne.every((e) => e.resumeId == 1), isTrue);
  });

  test('getPendingForResume excludes resolved suggestions', () async {
    final pendingId = await repository.insert(buildEdit(resumeId: 1));
    final acceptedId = await repository.insert(buildEdit(resumeId: 1));
    await repository.resolve(acceptedId, SuggestedEditStatus.accepted, DateTime(2026, 1, 2));

    final pending = await repository.getPendingForResume(1);

    expect(pending.map((e) => e.id), [pendingId]);
  });

  test('getPendingForResume returns an empty list once every suggestion is resolved', () async {
    final id = await repository.insert(buildEdit(resumeId: 1));
    await repository.resolve(id, SuggestedEditStatus.rejected, DateTime(2026, 1, 2));

    expect(await repository.getPendingForResume(1), isEmpty);
  });
}
