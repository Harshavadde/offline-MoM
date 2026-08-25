import 'dart:convert';

/// Whether a [ProjectBlock] represents work the user has actually finished,
/// or a project idea they've chosen to add to their resume as something
/// they intend to build (AI-Tailored-Resume-from-JD feature, migration
/// v22). `null` (the default for every pre-existing row, and every project
/// added through the normal Project Block Editor) means no opinion either
/// way - this app never assumes a project is "completed" just because it
/// exists.
enum ProjectBlockStatus {
  planned,
  completed;

  static ProjectBlockStatus? fromName(String? name) {
    if (name == null) return null;
    for (final value in ProjectBlockStatus.values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// One reusable project entry in the block library - app-scoped, not
/// resume-scoped, mirroring [ExperienceBlock]'s exact shape and reasoning.
/// A plain class (not `@freezed`), matching [Folder]/[Note].
class ProjectBlock {
  const ProjectBlock({
    required this.id,
    required this.name,
    this.link,
    this.bullets = const [],
    this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? link;
  final List<String> bullets;

  /// Null for every pre-existing project and every project added through
  /// the normal Project Block Editor - see [ProjectBlockStatus]'s own doc
  /// comment.
  final ProjectBlockStatus? status;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectBlock copyWith({
    String? name,
    String? link,
    List<String>? bullets,
    ProjectBlockStatus? status,
    DateTime? updatedAt,
  }) {
    return ProjectBlock(
      id: id,
      name: name ?? this.name,
      link: link ?? this.link,
      bullets: bullets ?? this.bullets,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'link': link,
      'bullets_json': jsonEncode(bullets),
      'status': status?.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ProjectBlock.fromMap(Map<String, Object?> map) {
    return ProjectBlock(
      id: map['id'] as int?,
      name: map['name'] as String,
      link: map['link'] as String?,
      bullets: List<String>.from(jsonDecode(map['bullets_json'] as String) as List),
      // Absent on any row inserted before migration v22 - defaults to
      // null ("no opinion"), never throws.
      status: ProjectBlockStatus.fromName(map['status'] as String?),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}
