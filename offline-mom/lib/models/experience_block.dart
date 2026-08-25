import 'dart:convert';

/// One distinct sub-project nested under a single [ExperienceBlock] entry
/// (migration v20, reliability-overhaul pass) - the real-device finding
/// this exists to fix: a resume commonly lists several named sub-projects
/// under one role ("SciLab", "ByHeart", "Crossword" under one "Software
/// Engineer" entry), each with its own bullets, structurally distinct
/// from the role's own top-level accomplishments and from each other.
/// Before this existed, [ExperienceImportParser]/[ExperienceBlock] had
/// nowhere to put that structure, so every sub-project's name and bullets
/// flattened into the parent entry's own [ExperienceBlock.bullets] list,
/// indistinguishable from the role's own bullets.
///
/// Deliberately has no `id`/independent lifecycle - a sub-project cannot
/// exist without its parent [ExperienceBlock], is never referenced from
/// anywhere else, and is never independently created/deleted outside its
/// parent's own edit flow - so it is a plain value type persisted inline
/// as part of [ExperienceBlock.subProjectsJson], not a new database
/// table.
class ExperienceSubProject {
  const ExperienceSubProject({required this.name, this.bullets = const []});

  /// The sub-project's own name/header line, exactly as found in the
  /// source (e.g. "SciLab (Web & Android) — Godot, GDScript, AWS S3,
  /// Google Play Console") - never re-parsed into further fields, since
  /// the tech-stack suffix has no reliably-delimited boundary across real
  /// resumes and re-splitting it risks losing real content.
  final String name;

  final List<String> bullets;

  ExperienceSubProject copyWith({String? name, List<String>? bullets}) {
    return ExperienceSubProject(
      name: name ?? this.name,
      bullets: bullets ?? this.bullets,
    );
  }

  Map<String, Object?> toMap() => {'name': name, 'bullets': bullets};

  factory ExperienceSubProject.fromMap(Map<String, Object?> map) {
    return ExperienceSubProject(
      name: map['name'] as String,
      bullets: (map['bullets'] as List).cast<String>(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExperienceSubProject &&
        other.name == name &&
        other.bullets.length == bullets.length &&
        other.bullets.every((b) => bullets.contains(b));
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(bullets));
}

/// One reusable work-experience entry in the block library - app-scoped,
/// not resume-scoped: editing it here updates every [Resume] that
/// references it via a [ResumeBlockRef], since a resume only ever holds a
/// reference, never a copy. A plain class (not `@freezed`), matching
/// [Folder]/[Note]'s exact shape.
class ExperienceBlock {
  const ExperienceBlock({
    required this.id,
    required this.role,
    required this.company,
    this.location,
    required this.startDate,
    this.endDate,
    this.bullets = const [],
    this.subProjects = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String role;
  final String company;
  final String? location;

  /// "YYYY-MM" - matches the schema's own column note; not a full
  /// [DateTime], since a resume entry only ever needs month-and-year
  /// precision.
  final String startDate;

  /// Null means "Present."
  final String? endDate;

  final List<String> bullets;

  /// Distinct named sub-projects nested under this role - see
  /// [ExperienceSubProject]'s own doc comment. Empty for the overwhelming
  /// majority of entries (a normal role with no internally-distinguished
  /// sub-projects) - never populated with a placeholder.
  final List<ExperienceSubProject> subProjects;

  final DateTime createdAt;
  final DateTime updatedAt;

  ExperienceBlock copyWith({
    String? role,
    String? company,
    String? location,
    String? startDate,
    String? endDate,
    List<String>? bullets,
    List<ExperienceSubProject>? subProjects,
    DateTime? updatedAt,
  }) {
    return ExperienceBlock(
      id: id,
      role: role ?? this.role,
      company: company ?? this.company,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      bullets: bullets ?? this.bullets,
      subProjects: subProjects ?? this.subProjects,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'role': role,
      'company': company,
      'location': location,
      'start_date': startDate,
      'end_date': endDate,
      'bullets_json': jsonEncode(bullets),
      'sub_projects_json': subProjects.isEmpty ? null : jsonEncode(subProjects.map((p) => p.toMap()).toList()),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ExperienceBlock.fromMap(Map<String, Object?> map) {
    final subProjectsRaw = map['sub_projects_json'] as String?;
    return ExperienceBlock(
      id: map['id'] as int?,
      role: map['role'] as String,
      company: map['company'] as String,
      location: map['location'] as String?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String?,
      bullets: List<String>.from(jsonDecode(map['bullets_json'] as String) as List),
      subProjects: subProjectsRaw == null || subProjectsRaw.isEmpty
          ? const []
          : (jsonDecode(subProjectsRaw) as List)
              .cast<Map<String, Object?>>()
              .map(ExperienceSubProject.fromMap)
              .toList(),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}
