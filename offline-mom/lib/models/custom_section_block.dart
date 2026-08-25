import 'dart:convert';

/// One reusable, generically-titled resume section in the block library -
/// app-scoped, not resume-scoped, mirroring [ProjectBlock]'s exact shape.
/// Exists specifically so an imported (or manually added) resume section
/// this app has no dedicated typed model for - "Awards & Recognition",
/// "Publications", "Volunteer Experience", "Languages", etc. - has
/// somewhere real to live instead of being discarded or silently merged
/// into an unrelated section (docs/v3/implementation/03-decisions.md, beta
/// data-fidelity requirement). [title] is the section heading exactly as
/// found/entered - never invented, never normalized into a fixed list of
/// known names. [entries] is an ordered list of plain-text lines (a
/// paragraph or a bulleted line each becomes one entry) - deliberately
/// just `List<String>`, not a further-typed sub-model, since a generic
/// section's content has no more structure than that to preserve.
class CustomSectionBlock {
  const CustomSectionBlock({
    required this.id,
    required this.title,
    this.entries = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final List<String> entries;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomSectionBlock copyWith({
    String? title,
    List<String>? entries,
    DateTime? updatedAt,
  }) {
    return CustomSectionBlock(
      id: id,
      title: title ?? this.title,
      entries: entries ?? this.entries,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'entries_json': jsonEncode(entries),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CustomSectionBlock.fromMap(Map<String, Object?> map) {
    return CustomSectionBlock(
      id: map['id'] as int?,
      title: map['title'] as String,
      entries: List<String>.from(jsonDecode(map['entries_json'] as String) as List),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
