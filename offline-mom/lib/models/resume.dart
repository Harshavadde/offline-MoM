import 'dart:convert';

import 'resume_link.dart';

/// A Resume identity - the container a user names and returns to,
/// independent of any particular saved version. Owns the Profile fields
/// (name/contact/links) inline, 1:1, rather than a separate table - the
/// same "small, fixed shape, no reason to split out" reasoning [Folder]
/// already applies to its own fields. A plain class (not `@freezed`),
/// matching [Folder]/[Note]'s exact shape: a simple `copyWith`, no benefit
/// from code generation for a shape this small.
///
/// [targetRole] is reserved for M2's Job-Description-matching context - no
/// Editor field reads or writes it in Milestone 1; wired into the Editor's
/// Profile card starting V3 Milestone 0 (docs/v3/01-prd.md §7).
class Resume {
  const Resume({
    required this.id,
    required this.title,
    this.targetRole,
    required this.fullName,
    this.email,
    this.phone,
    this.location,
    this.links = const [],
    this.achievements = const [],
    this.templateId,
    this.isProfile = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String? targetRole;
  final String fullName;
  final String? email;
  final String? phone;
  final String? location;
  final List<ResumeLink> links;

  /// Short, non-relational achievement bullets (migration v17, V3
  /// Milestone 0, docs/v3/01-prd.md §7) - a lightweight JSON-encoded string
  /// list on this table directly, mirroring [links]'s own convention,
  /// rather than a reusable block-library table: achievements have no
  /// reuse-across-resumes need the way experience/education/etc. blocks
  /// do.
  final List<String> achievements;

  /// Which template last rendered this resume's draft (migration v17, V3
  /// Milestone 0) - purely descriptive; `null` until the Milestone 1
  /// template engine assigns it. No Milestone 0 code sets this to a
  /// non-null value.
  final String? templateId;

  /// Marks this resume as the user's "My Profile" - their complete career
  /// source of truth, never a job-specific resume (migration v19, Product
  /// Validation phase, docs/v3/implementation/03-decisions.md). At most one
  /// resume has this set at a time - enforced by
  /// `ResumeRepository.setAsProfile`, the same "one designated row, unset
  /// the previous one first" pattern `InstalledModelRepository.setActive`
  /// already uses for the active-model-per-kind invariant. Reuses the
  /// entire `Resume`/`ResumeBlockRef` shape unchanged - a profile is
  /// structurally just a resume; this flag only changes how it's
  /// presented and gates it out of JD-tailoring mutation (see
  /// `GenerateResumeSuggestionsUseCase`/`AcceptSuggestedEditUseCase`'s own
  /// doc comments).
  final bool isProfile;

  final DateTime createdAt;
  final DateTime updatedAt;

  Resume copyWith({
    String? title,
    String? targetRole,
    String? fullName,
    String? email,
    String? phone,
    String? location,
    List<ResumeLink>? links,
    List<String>? achievements,
    String? templateId,
    bool? isProfile,
    DateTime? updatedAt,
  }) {
    return Resume(
      id: id,
      title: title ?? this.title,
      targetRole: targetRole ?? this.targetRole,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      links: links ?? this.links,
      achievements: achievements ?? this.achievements,
      templateId: templateId ?? this.templateId,
      isProfile: isProfile ?? this.isProfile,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'target_role': targetRole,
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'location': location,
      'links_json': ResumeLink.encodeList(links),
      'achievements_json': _encodeStringList(achievements),
      'template_id': templateId,
      'is_profile': isProfile ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Resume.fromMap(Map<String, Object?> map) {
    return Resume(
      id: map['id'] as int?,
      title: map['title'] as String,
      targetRole: map['target_role'] as String?,
      fullName: map['full_name'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      location: map['location'] as String?,
      links: ResumeLink.decodeList(map['links_json'] as String?),
      achievements: _decodeStringList(map['achievements_json'] as String?),
      templateId: map['template_id'] as String?,
      // Absent on any row inserted before this column existed - defaults
      // to false/not-a-profile, never throws.
      isProfile: (map['is_profile'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}

/// Serializes a plain string list into the form stored in
/// [Resume.achievements]'s TEXT column - null for an empty list rather than
/// `'[]'`, mirroring [ResumeLink.encodeList]'s "null for none" convention.
String? _encodeStringList(List<String> values) {
  if (values.isEmpty) return null;
  return jsonEncode(values);
}

/// Inverse of [_encodeStringList]. Null/empty input decodes to an empty
/// list, mirroring [ResumeLink.decodeList].
List<String> _decodeStringList(String? json) {
  if (json == null || json.isEmpty) return const [];
  return (jsonDecode(json) as List).cast<String>();
}
