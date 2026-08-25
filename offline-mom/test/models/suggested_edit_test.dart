import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_block_type.dart';
import 'package:offline_mom/models/suggested_edit.dart';

void main() {
  SuggestedEdit buildEdit({
    ResumeBlockType? targetBlockType,
    int? targetBlockId,
    SuggestedEditStatus status = SuggestedEditStatus.pending,
    DateTime? resolvedAt,
  }) {
    return SuggestedEdit(
      id: null,
      resumeId: 1,
      targetBlockType: targetBlockType,
      targetBlockId: targetBlockId,
      fieldName: 'bullets',
      originalValue: 'Worked on Kubernetes deployments',
      suggestedValue: 'Led Kubernetes deployment automation',
      sourceRequirement: 'Kubernetes',
      status: status,
      createdAt: DateTime(2026, 1, 1),
      resolvedAt: resolvedAt,
    );
  }

  test('toMap/fromMap round-trips a block-targeted suggestion', () {
    final edit = buildEdit(targetBlockType: ResumeBlockType.experience, targetBlockId: 7);

    final restored = SuggestedEdit.fromMap(edit.toMap());

    expect(restored.resumeId, 1);
    expect(restored.targetBlockType, ResumeBlockType.experience);
    expect(restored.targetBlockId, 7);
    expect(restored.fieldName, 'bullets');
    expect(restored.originalValue, edit.originalValue);
    expect(restored.suggestedValue, edit.suggestedValue);
    expect(restored.sourceRequirement, 'Kubernetes');
    expect(restored.status, SuggestedEditStatus.pending);
    expect(restored.resolvedAt, isNull);
  });

  test('a profile-level suggestion round-trips with both target fields null', () {
    final edit = buildEdit();

    final restored = SuggestedEdit.fromMap(edit.toMap());

    expect(restored.targetBlockType, isNull);
    expect(restored.targetBlockId, isNull);
  });

  test('sourceRequirement is nullable and round-trips as null', () {
    final edit = SuggestedEdit(
      id: null,
      resumeId: 1,
      fieldName: 'summary',
      originalValue: 'a',
      suggestedValue: 'b',
      createdAt: DateTime(2026, 1, 1),
    );

    final restored = SuggestedEdit.fromMap(edit.toMap());

    expect(restored.sourceRequirement, isNull);
  });

  test('every SuggestedEditStatus value round-trips through toMap/fromMap', () {
    for (final status in SuggestedEditStatus.values) {
      final restored = SuggestedEdit.fromMap(buildEdit(status: status).toMap());
      expect(restored.status, status, reason: 'status $status did not round-trip');
    }
  });

  test('resolvedAt round-trips when set', () {
    final edit = buildEdit(status: SuggestedEditStatus.accepted, resolvedAt: DateTime(2026, 1, 2, 9));

    final restored = SuggestedEdit.fromMap(edit.toMap());

    expect(restored.resolvedAt, DateTime(2026, 1, 2, 9));
  });

  test('copyWith updates status and resolvedAt without touching other fields', () {
    final edit = buildEdit();

    final resolved = edit.copyWith(status: SuggestedEditStatus.rejected, resolvedAt: DateTime(2026, 1, 3));

    expect(resolved.status, SuggestedEditStatus.rejected);
    expect(resolved.resolvedAt, DateTime(2026, 1, 3));
    expect(resolved.originalValue, edit.originalValue);
    expect(resolved.suggestedValue, edit.suggestedValue);
    expect(resolved.id, edit.id);
    expect(resolved.resumeId, edit.resumeId);
  });

  test('copyWith(clearResolvedAt: true) clears an already-set resolvedAt', () {
    final edit = buildEdit(status: SuggestedEditStatus.accepted, resolvedAt: DateTime(2026, 1, 2));

    final cleared = edit.copyWith(clearResolvedAt: true);

    expect(cleared.resolvedAt, isNull);
  });
}
