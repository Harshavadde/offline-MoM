import 'resume_block_type.dart';

/// Lifecycle of one [SuggestedEdit] - the first-class state machine that
/// makes "the user reviews every meaningful AI change" concrete rather than
/// aspirational (docs/v3/01-prd.md §6, AC3-02). No code path may write a
/// model-generated rewrite directly into a resume block; it always becomes
/// a row here first, `pending` until the user acts on it.
enum SuggestedEditStatus {
  /// Generated, not yet reviewed.
  pending,

  /// The user accepted the suggestion's text exactly as generated - merged
  /// into the live draft the same way a manual edit would be.
  accepted,

  /// The user rejected the suggestion - the original content is left
  /// byte-identical. Retained (not deleted) for audit/undo purposes until
  /// the resume itself is deleted.
  rejected,

  /// The user accepted the suggestion but changed its wording before
  /// merging it - distinguished from [accepted] so a resume's suggestion
  /// history can show which accepted edits were taken verbatim.
  edited,
}

/// One proposed AI edit to a Resume's content - never applied automatically
/// (docs/v3/01-prd.md §6/§12/§22.3). Targets either a specific library
/// block ([targetBlockType] + [targetBlockId] both set) or a profile-level
/// field ([targetBlockType]/[targetBlockId] both null - there is no
/// `ResumeBlockType` value for "profile," so the pair is null together
/// rather than one being null and the other not).
class SuggestedEdit {
  const SuggestedEdit({
    required this.id,
    required this.resumeId,
    this.targetBlockType,
    this.targetBlockId,
    required this.fieldName,
    required this.originalValue,
    required this.suggestedValue,
    this.sourceRequirement,
    this.status = SuggestedEditStatus.pending,
    required this.createdAt,
    this.resolvedAt,
  });

  final int? id;
  final int resumeId;

  /// Null together with [targetBlockId] for a profile-level suggestion
  /// (e.g. a rewritten summary) - otherwise identifies which library table
  /// [targetBlockId] resolves against, mirroring [ResumeBlockType]'s
  /// existing polymorphic-reference role on `ResumeBlockRef`.
  final ResumeBlockType? targetBlockType;

  /// The id within [targetBlockType]'s own library table - null for a
  /// profile-level suggestion. Never the owning [resumeId].
  final int? targetBlockId;

  /// Which field on the target this suggestion rewrites, e.g. `'bullets'`,
  /// `'summary'` - free text rather than an enum, since the set of
  /// suggestible fields is expected to grow with later milestones without
  /// needing a schema change each time.
  final String fieldName;

  /// The user's own existing text, captured at generation time - the
  /// fabrication-guard and the review UI's diff both compare against this,
  /// never against whatever the live block currently holds (which may have
  /// changed since).
  final String originalValue;

  /// The model's proposed replacement text - never written anywhere else
  /// until [status] becomes [SuggestedEditStatus.accepted] or
  /// [SuggestedEditStatus.edited].
  final String suggestedValue;

  /// The JD requirement text this suggestion relates to, if any - null for
  /// a suggestion generated outside JD-tailoring context (e.g. a Tier-2
  /// "improve this bullet" request with no JD involved).
  final String? sourceRequirement;

  final SuggestedEditStatus status;

  final DateTime createdAt;

  /// Set the moment [status] moves away from [SuggestedEditStatus.pending] -
  /// null while still pending.
  final DateTime? resolvedAt;

  SuggestedEdit copyWith({
    SuggestedEditStatus? status,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
  }) {
    return SuggestedEdit(
      id: id,
      resumeId: resumeId,
      targetBlockType: targetBlockType,
      targetBlockId: targetBlockId,
      fieldName: fieldName,
      originalValue: originalValue,
      suggestedValue: suggestedValue,
      sourceRequirement: sourceRequirement,
      status: status ?? this.status,
      createdAt: createdAt,
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'resume_id': resumeId,
      'target_block_type': targetBlockType?.name,
      'target_block_id': targetBlockId,
      'field_name': fieldName,
      'original_value': originalValue,
      'suggested_value': suggestedValue,
      'source_requirement': sourceRequirement,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'resolved_at': resolvedAt?.toIso8601String(),
    };
  }

  factory SuggestedEdit.fromMap(Map<String, Object?> map) {
    return SuggestedEdit(
      id: map['id'] as int?,
      resumeId: map['resume_id'] as int,
      targetBlockType: map['target_block_type'] == null
          ? null
          : ResumeBlockType.values.byName(map['target_block_type'] as String),
      targetBlockId: map['target_block_id'] as int?,
      fieldName: map['field_name'] as String,
      originalValue: map['original_value'] as String,
      suggestedValue: map['suggested_value'] as String,
      sourceRequirement: map['source_requirement'] as String?,
      status: SuggestedEditStatus.values.byName(map['status'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      resolvedAt: map['resolved_at'] == null
          ? null
          : DateTime.parse(map['resolved_at'] as String),
    );
  }
}
