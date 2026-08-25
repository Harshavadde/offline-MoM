/// A user-created folder for organizing documents (V2.2 Production
/// Hardening, Priority 2). A plain, hand-written class - not `@freezed` -
/// mirrors [Note]'s exact reasoning: a simple, user-renameable value type
/// with a small `copyWith`, no benefit from code generation for a shape
/// this small.
class Folder {
  const Folder({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  Folder copyWith({String? title, DateTime? updatedAt}) {
    return Folder(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Folder.fromMap(Map<String, Object?> map) {
    return Folder(
      id: map['id'] as int?,
      title: map['title'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
