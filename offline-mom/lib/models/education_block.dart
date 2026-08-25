import 'dart:convert';

/// One reusable education entry in the block library - app-scoped, not
/// resume-scoped, mirroring [ExperienceBlock]'s exact shape and reasoning.
/// A plain class (not `@freezed`), matching [Folder]/[Note].
class EducationBlock {
  const EducationBlock({
    required this.id,
    required this.institution,
    required this.degree,
    this.fieldOfStudy,
    required this.startDate,
    this.endDate,
    this.details = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String institution;
  final String degree;
  final String? fieldOfStudy;

  /// "YYYY-MM" - see [ExperienceBlock.startDate].
  final String startDate;
  final String? endDate;

  /// Honors/GPA/coursework - an optional bullet list, distinct from
  /// [ExperienceBlock.bullets] in that a value here is genuinely optional
  /// (stored as `NULL`, not an empty array, when there's nothing to show).
  final List<String> details;

  final DateTime createdAt;
  final DateTime updatedAt;

  EducationBlock copyWith({
    String? institution,
    String? degree,
    String? fieldOfStudy,
    String? startDate,
    String? endDate,
    List<String>? details,
    DateTime? updatedAt,
  }) {
    return EducationBlock(
      id: id,
      institution: institution ?? this.institution,
      degree: degree ?? this.degree,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      details: details ?? this.details,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'institution': institution,
      'degree': degree,
      'field_of_study': fieldOfStudy,
      'start_date': startDate,
      'end_date': endDate,
      'details_json': details.isEmpty ? null : jsonEncode(details),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory EducationBlock.fromMap(Map<String, Object?> map) {
    final detailsJson = map['details_json'] as String?;
    return EducationBlock(
      id: map['id'] as int?,
      institution: map['institution'] as String,
      degree: map['degree'] as String,
      fieldOfStudy: map['field_of_study'] as String?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String?,
      details: detailsJson == null || detailsJson.isEmpty
          ? const []
          : List<String>.from(jsonDecode(detailsJson) as List),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}
