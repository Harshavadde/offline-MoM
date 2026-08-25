import 'dart:convert';

/// One reusable project entry in the block library - app-scoped, not
/// resume-scoped, mirroring [ExperienceBlock]'s exact shape and reasoning.
/// A plain class (not `@freezed`), matching [Folder]/[Note].
class ProjectBlock {
  const ProjectBlock({
    required this.id,
    required this.name,
    this.link,
    this.bullets = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? link;
  final List<String> bullets;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectBlock copyWith({
    String? name,
    String? link,
    List<String>? bullets,
    DateTime? updatedAt,
  }) {
    return ProjectBlock(
      id: id,
      name: name ?? this.name,
      link: link ?? this.link,
      bullets: bullets ?? this.bullets,
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
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}
