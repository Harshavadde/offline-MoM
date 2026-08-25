import 'resume_block_type.dart';

/// One row of a [Resume]'s *live, editable* composition - which library
/// block it includes, in what order, with what per-resume override. This
/// is the polymorphic join row `ResumeBlockRepository` reads/writes on
/// every Editor interaction; [blockType] + [blockId] resolve to whichever
/// library table [blockType] names (`ExperienceBlock`, `EducationBlock`,
/// `ProjectBlock`, `CertificationBlock`, or `SkillEntry`) - the same
/// "cannot be a real FK across multiple possible parent tables" shape
/// [KnowledgeChunk] already has for `content_type` + `source_id`. A plain
/// class (not `@freezed`), mirroring [KnowledgeChunk]'s own reasoning: an
/// internal join row with no user-facing `copyWith` need beyond the two
/// fields that are ever updated in place.
class ResumeBlockRef {
  const ResumeBlockRef({
    required this.id,
    required this.resumeId,
    required this.blockType,
    required this.blockId,
    required this.sortOrder,
    this.overrideJson,
    required this.createdAt,
  });

  final int? id;
  final int resumeId;
  final ResumeBlockType blockType;

  /// The id within [blockType]'s own library table - never the owning
  /// [resumeId].
  final int blockId;

  final int sortOrder;

  /// A per-resume trim (e.g. a subset of bullets), never touching the
  /// shared library block. Only ever set for `experience`/`project`/
  /// `education` block types - see `ResolvedCertificationEntry`/
  /// `ResolvedSkillEntry` in resume_snapshot.dart for why the other two
  /// types never carry one.
  final String? overrideJson;

  final DateTime createdAt;

  /// [sortOrder] and [overrideJson] are the only two fields ever updated
  /// in place, via `ResumeBlockRepository.reorder`/`setOverride` - which
  /// library block a row points to is never mutated, only detached and a
  /// new row attached.
  ResumeBlockRef copyWith({int? sortOrder, String? overrideJson}) {
    return ResumeBlockRef(
      id: id,
      resumeId: resumeId,
      blockType: blockType,
      blockId: blockId,
      sortOrder: sortOrder ?? this.sortOrder,
      overrideJson: overrideJson ?? this.overrideJson,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'resume_id': resumeId,
      'block_type': blockType.name,
      'block_id': blockId,
      'sort_order': sortOrder,
      'override_json': overrideJson,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ResumeBlockRef.fromMap(Map<String, Object?> map) {
    return ResumeBlockRef(
      id: map['id'] as int?,
      resumeId: map['resume_id'] as int,
      blockType: ResumeBlockType.values.byName(map['block_type'] as String),
      blockId: map['block_id'] as int,
      sortOrder: map['sort_order'] as int,
      overrideJson: map['override_json'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

}
