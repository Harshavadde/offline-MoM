/// Grouping for [SkillEntry.category] - technical/tool/soft, used to
/// cluster the skill picker (§06.4 of the Milestone 1 plan). Mirrors
/// [ProfessionProfile]'s "closed enum, not free text" reasoning: every
/// skill belongs to exactly one of these three buckets.
enum SkillCategory {
  technical,
  tool,
  soft,
}

/// One reusable skill in the flat skills library - app-scoped, not
/// resume-scoped, attached to resumes the same way [ExperienceBlock] is
/// (via [ResumeBlockRef] with `blockType = skill`). No `updatedAt`: a skill
/// is a short name plus a category, never edited in place after creation -
/// only added, attached/detached, or deleted. A plain class (not
/// `@freezed`), matching [Folder]/[Note].
class SkillEntry {
  const SkillEntry({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
  });

  final int? id;
  final String name;
  final SkillCategory category;
  final DateTime createdAt;

  SkillEntry copyWith({String? name, SkillCategory? category}) {
    return SkillEntry(
      id: id,
      name: name ?? this.name,
      category: category ?? this.category,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory SkillEntry.fromMap(Map<String, Object?> map) {
    return SkillEntry(
      id: map['id'] as int?,
      name: map['name'] as String,
      category: SkillCategory.values.byName(map['category'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

}
