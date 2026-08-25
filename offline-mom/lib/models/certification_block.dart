/// One reusable certification entry in the block library - app-scoped, not
/// resume-scoped, mirroring [ExperienceBlock]'s exact shape and reasoning.
/// Unlike Experience/Education/Project, a certification has no
/// orderable/trimmable bullet content - see [ResolvedCertificationEntry]
/// in resume_snapshot.dart for why `override_json` never applies here. A
/// plain class (not `@freezed`), matching [Folder]/[Note].
class CertificationBlock {
  const CertificationBlock({
    required this.id,
    required this.name,
    required this.issuer,
    this.issuedDate,
    this.credentialUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String issuer;
  final String? issuedDate;
  final String? credentialUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  CertificationBlock copyWith({
    String? name,
    String? issuer,
    String? issuedDate,
    String? credentialUrl,
    DateTime? updatedAt,
  }) {
    return CertificationBlock(
      id: id,
      name: name ?? this.name,
      issuer: issuer ?? this.issuer,
      issuedDate: issuedDate ?? this.issuedDate,
      credentialUrl: credentialUrl ?? this.credentialUrl,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'issuer': issuer,
      'issued_date': issuedDate,
      'credential_url': credentialUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory CertificationBlock.fromMap(Map<String, Object?> map) {
    return CertificationBlock(
      id: map['id'] as int?,
      name: map['name'] as String,
      issuer: map['issuer'] as String,
      issuedDate: map['issued_date'] as String?,
      credentialUrl: map['credential_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

}
