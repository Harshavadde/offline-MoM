import 'dart:convert';

import 'resume_snapshot.dart';

/// One immutable, frozen snapshot of a [Resume] - never edited once
/// created, only created, listed, renamed (metadata only), or deleted. The
/// append-only spirit of `ChatMessage` extended to versions: a correction
/// produces a new version, it never rewrites an old one. [compiledSnapshot]
/// is what guarantees this - once written, it is never re-derived from the
/// live block library, so a later edit or deletion of a source block can
/// never retroactively change what a version means. A plain class (not
/// `@freezed`), matching every other Milestone 1 model.
class ResumeVersion {
  const ResumeVersion({
    required this.id,
    required this.resumeId,
    required this.versionLabel,
    required this.compiledSnapshot,
    this.exportedPdfPath,
    this.templateId,
    this.tailoredForJdTitle,
    this.tailoredForJdCompany,
    required this.createdAt,
  });

  final int? id;
  final int resumeId;
  final String versionLabel;

  /// Frozen at save time by `ResumeCompilerService.compile()`. Never
  /// mutated after construction - [copyWith] deliberately does not expose
  /// this field, mirroring `renameLabel`'s "the one permitted metadata
  /// edit" contract at the repository layer.
  final ResumeSnapshot compiledSnapshot;

  /// Null until the optional PDF export step completes; a failed export
  /// never blocks the version itself from persisting.
  final String? exportedPdfPath;

  /// Which template rendered this frozen snapshot (migration v17, V3
  /// Milestone 0) - descriptive metadata, `null` for any version saved
  /// before the Milestone 1 template engine exists.
  final String? templateId;

  /// Label-only JD-tailoring metadata (migration v17, V3 Milestone 0,
  /// docs/v3/01-prd.md §14/§16) - the JD's title/company, never its full
  /// text: JD content stays session-only. Both null for a version not tied
  /// to any JD.
  final String? tailoredForJdTitle;
  final String? tailoredForJdCompany;

  final DateTime createdAt;

  ResumeVersion copyWith({String? versionLabel, String? exportedPdfPath}) {
    return ResumeVersion(
      id: id,
      resumeId: resumeId,
      versionLabel: versionLabel ?? this.versionLabel,
      compiledSnapshot: compiledSnapshot,
      exportedPdfPath: exportedPdfPath ?? this.exportedPdfPath,
      templateId: templateId,
      tailoredForJdTitle: tailoredForJdTitle,
      tailoredForJdCompany: tailoredForJdCompany,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'resume_id': resumeId,
      'version_label': versionLabel,
      'compiled_snapshot': jsonEncode(compiledSnapshot.toMap()),
      'exported_pdf_path': exportedPdfPath,
      'template_id': templateId,
      'tailored_for_jd_title': tailoredForJdTitle,
      'tailored_for_jd_company': tailoredForJdCompany,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory ResumeVersion.fromMap(Map<String, Object?> map) {
    return ResumeVersion(
      id: map['id'] as int?,
      resumeId: map['resume_id'] as int,
      versionLabel: map['version_label'] as String,
      compiledSnapshot: ResumeSnapshot.fromMap(
        jsonDecode(map['compiled_snapshot'] as String) as Map<String, Object?>,
      ),
      exportedPdfPath: map['exported_pdf_path'] as String?,
      templateId: map['template_id'] as String?,
      tailoredForJdTitle: map['tailored_for_jd_title'] as String?,
      tailoredForJdCompany: map['tailored_for_jd_company'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

}
