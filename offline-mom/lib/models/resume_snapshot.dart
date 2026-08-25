import 'experience_block.dart' show ExperienceSubProject;
import 'project_block.dart' show ProjectBlockStatus;
import 'resume_link.dart';
import 'skill_entry.dart';

/// The fully-resolved, order-materialized content of a [Resume] at compile
/// time - not a database entity, the single most important new shape in
/// Milestone 1. Produced once by `ResumeCompilerService.compile()`, frozen
/// into `ResumeVersion.compiledSnapshot`, and read by nothing else: every
/// export format and the live Preview flow are pure functions of this one
/// DTO, never the live tables. All five lists are pre-ordered by
/// `ResumeBlockRef.sortOrder` at compile time. A plain class (not
/// `@freezed`), matching every other Milestone 1 model.
class ResumeSnapshot {
  const ResumeSnapshot({
    required this.resumeId,
    required this.compiledAt,
    required this.profile,
    this.experience = const [],
    this.education = const [],
    this.projects = const [],
    this.certifications = const [],
    this.skills = const [],
    this.customSections = const [],
  });

  /// The source [Resume]'s id - reference only, never re-queried once
  /// frozen.
  final int resumeId;

  final DateTime compiledAt;
  final ResumeSnapshotProfile profile;
  final List<ResolvedExperienceEntry> experience;
  final List<ResolvedEducationEntry> education;
  final List<ResolvedProjectEntry> projects;
  final List<ResolvedCertificationEntry> certifications;
  final List<ResolvedSkillEntry> skills;

  /// Generic, custom-titled sections this snapshot carries - beta
  /// data-fidelity requirement (docs/v3/implementation/03-decisions.md):
  /// an imported section this app has no dedicated typed field for (Awards,
  /// Publications, Volunteer Experience, ...) still survives compile,
  /// rendering, and re-opening rather than being silently dropped. Empty
  /// for every resume that has none - never populated with a placeholder.
  final List<ResolvedCustomSectionEntry> customSections;

  ResumeSnapshot copyWith({
    ResumeSnapshotProfile? profile,
    List<ResolvedExperienceEntry>? experience,
    List<ResolvedEducationEntry>? education,
    List<ResolvedProjectEntry>? projects,
    List<ResolvedCertificationEntry>? certifications,
    List<ResolvedSkillEntry>? skills,
    List<ResolvedCustomSectionEntry>? customSections,
  }) {
    return ResumeSnapshot(
      resumeId: resumeId,
      compiledAt: compiledAt,
      profile: profile ?? this.profile,
      experience: experience ?? this.experience,
      education: education ?? this.education,
      projects: projects ?? this.projects,
      certifications: certifications ?? this.certifications,
      skills: skills ?? this.skills,
      customSections: customSections ?? this.customSections,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'resume_id': resumeId,
      'compiled_at': compiledAt.toIso8601String(),
      'profile': profile.toMap(),
      'experience': experience.map((e) => e.toMap()).toList(),
      'education': education.map((e) => e.toMap()).toList(),
      'projects': projects.map((e) => e.toMap()).toList(),
      'certifications': certifications.map((e) => e.toMap()).toList(),
      'skills': skills.map((e) => e.toMap()).toList(),
      'custom_sections': customSections.map((e) => e.toMap()).toList(),
    };
  }

  factory ResumeSnapshot.fromMap(Map<String, Object?> map) {
    return ResumeSnapshot(
      resumeId: map['resume_id'] as int,
      compiledAt: DateTime.parse(map['compiled_at'] as String),
      profile: ResumeSnapshotProfile.fromMap(
        map['profile'] as Map<String, Object?>,
      ),
      experience: (map['experience'] as List)
          .cast<Map<String, Object?>>()
          .map(ResolvedExperienceEntry.fromMap)
          .toList(),
      education: (map['education'] as List)
          .cast<Map<String, Object?>>()
          .map(ResolvedEducationEntry.fromMap)
          .toList(),
      projects: (map['projects'] as List)
          .cast<Map<String, Object?>>()
          .map(ResolvedProjectEntry.fromMap)
          .toList(),
      certifications: (map['certifications'] as List)
          .cast<Map<String, Object?>>()
          .map(ResolvedCertificationEntry.fromMap)
          .toList(),
      skills: (map['skills'] as List)
          .cast<Map<String, Object?>>()
          .map(ResolvedSkillEntry.fromMap)
          .toList(),
      // Absent on any snapshot frozen before this field existed (a version
      // saved pre-beta) - defaults to empty, never throws.
      customSections: (map['custom_sections'] as List?)
              ?.cast<Map<String, Object?>>()
              .map(ResolvedCustomSectionEntry.fromMap)
              .toList() ??
          const [],
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResumeSnapshot.fromJson(Map<String, Object?> json) =>
      ResumeSnapshot.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResumeSnapshot &&
        other.resumeId == resumeId &&
        other.compiledAt == compiledAt &&
        other.profile == profile &&
        _listEquals(other.experience, experience) &&
        _listEquals(other.education, education) &&
        _listEquals(other.projects, projects) &&
        _listEquals(other.certifications, certifications) &&
        _listEquals(other.skills, skills) &&
        _listEquals(other.customSections, customSections);
  }

  @override
  int get hashCode => Object.hash(
        resumeId,
        compiledAt,
        profile,
        Object.hashAll(experience),
        Object.hashAll(education),
        Object.hashAll(projects),
        Object.hashAll(certifications),
        Object.hashAll(skills),
        Object.hashAll(customSections),
      );
}

/// The Profile section of a [ResumeSnapshot] - resolved from [Resume]'s
/// own Profile fields at compile time.
class ResumeSnapshotProfile {
  const ResumeSnapshotProfile({
    required this.fullName,
    this.email,
    this.phone,
    this.location,
    this.links = const [],
    this.roleTagline,
  });

  final String fullName;
  final String? email;
  final String? phone;
  final String? location;
  final List<ResumeLink> links;

  /// The user's own typed `Resume.targetRole` text, carried through
  /// unmodified - **product visual-audit pass**. Real, user-authored
  /// content (not AI-generated, not inferred), reserved before this pass
  /// for M2's JD-matching context only and never rendered; now also
  /// available to the header layout as an optional role/headline line.
  /// Null when the user never set it - the header omits the line entirely
  /// rather than rendering a placeholder.
  final String? roleTagline;

  ResumeSnapshotProfile copyWith({
    String? fullName,
    String? email,
    String? phone,
    String? location,
    List<ResumeLink>? links,
    String? roleTagline,
  }) {
    return ResumeSnapshotProfile(
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      links: links ?? this.links,
      roleTagline: roleTagline ?? this.roleTagline,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'location': location,
      'links': links.map((l) => l.toMap()).toList(),
      'role_tagline': roleTagline,
    };
  }

  factory ResumeSnapshotProfile.fromMap(Map<String, Object?> map) {
    return ResumeSnapshotProfile(
      fullName: map['full_name'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      location: map['location'] as String?,
      links: (map['links'] as List)
          .cast<Map<String, Object?>>()
          .map(ResumeLink.fromMap)
          .toList(),
      roleTagline: map['role_tagline'] as String?,
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResumeSnapshotProfile.fromJson(Map<String, Object?> json) =>
      ResumeSnapshotProfile.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResumeSnapshotProfile &&
        other.fullName == fullName &&
        other.email == email &&
        other.phone == phone &&
        other.location == location &&
        other.roleTagline == roleTagline &&
        _resumeLinksEqual(other.links, links);
  }

  @override
  int get hashCode => Object.hash(
        fullName,
        email,
        phone,
        location,
        roleTagline,
        Object.hashAll(links.map((l) => Object.hash(l.label, l.url))),
      );
}

/// [ResumeLink] has no `==`/`hashCode` of its own (it follows [Folder]/
/// [Note]'s plain-model convention, which deliberately omits them) - so
/// [ResumeSnapshotProfile]'s own equality, which the DTO family does need,
/// compares each link by its actual field values here rather than relying
/// on [ResumeLink]'s default identity equality.
bool _resumeLinksEqual(List<ResumeLink> a, List<ResumeLink> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].label != b[i].label || a[i].url != b[i].url) return false;
  }
  return true;
}

/// One resolved Experience entry inside a [ResumeSnapshot]. [bullets] has
/// `override_json` already applied if the source [ResumeBlockRef] carried
/// one; falls back to the library block's own bullets otherwise.
class ResolvedExperienceEntry {
  const ResolvedExperienceEntry({
    required this.sourceBlockId,
    required this.role,
    required this.company,
    this.location,
    required this.startDate,
    this.endDate,
    this.bullets = const [],
    this.subProjects = const [],
  });

  /// The originating `ExperienceBlock.id` - reference only.
  final int sourceBlockId;

  final String role;
  final String company;
  final String? location;
  final String startDate;
  final String? endDate;
  final List<String> bullets;

  /// Distinct named sub-projects nested under this role (migration v20) -
  /// see [ExperienceSubProject]'s own doc comment. Empty for the
  /// overwhelming majority of entries.
  final List<ExperienceSubProject> subProjects;

  ResolvedExperienceEntry copyWith({
    String? role,
    String? company,
    String? location,
    String? startDate,
    String? endDate,
    List<String>? bullets,
    List<ExperienceSubProject>? subProjects,
  }) {
    return ResolvedExperienceEntry(
      sourceBlockId: sourceBlockId,
      role: role ?? this.role,
      company: company ?? this.company,
      location: location ?? this.location,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      bullets: bullets ?? this.bullets,
      subProjects: subProjects ?? this.subProjects,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'role': role,
      'company': company,
      'location': location,
      'start_date': startDate,
      'end_date': endDate,
      'bullets': bullets,
      'sub_projects': subProjects.map((p) => p.toMap()).toList(),
    };
  }

  factory ResolvedExperienceEntry.fromMap(Map<String, Object?> map) {
    final subProjectsRaw = map['sub_projects'] as List?;
    return ResolvedExperienceEntry(
      sourceBlockId: map['source_block_id'] as int,
      role: map['role'] as String,
      company: map['company'] as String,
      location: map['location'] as String?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String?,
      bullets: (map['bullets'] as List).cast<String>(),
      // Absent on any snapshot frozen before this field existed - defaults
      // to empty, never throws (matches ResumeSnapshot.customSections'
      // identical backward-compatibility handling).
      subProjects: subProjectsRaw == null
          ? const []
          : subProjectsRaw.cast<Map<String, Object?>>().map(ExperienceSubProject.fromMap).toList(),
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedExperienceEntry.fromJson(Map<String, Object?> json) =>
      ResolvedExperienceEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedExperienceEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.role == role &&
        other.company == company &&
        other.location == location &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        _listEquals(other.bullets, bullets) &&
        _listEquals(other.subProjects, subProjects);
  }

  @override
  int get hashCode => Object.hash(
        sourceBlockId,
        role,
        company,
        location,
        startDate,
        endDate,
        Object.hashAll(bullets),
        Object.hashAll(subProjects),
      );
}

/// One resolved Education entry inside a [ResumeSnapshot]. [details] has
/// `override_json` already applied if present; empty if the source block
/// has no `details_json`.
class ResolvedEducationEntry {
  const ResolvedEducationEntry({
    required this.sourceBlockId,
    required this.institution,
    required this.degree,
    this.fieldOfStudy,
    required this.startDate,
    this.endDate,
    this.details = const [],
  });

  /// The originating `EducationBlock.id` - reference only.
  final int sourceBlockId;

  final String institution;
  final String degree;
  final String? fieldOfStudy;
  final String startDate;
  final String? endDate;
  final List<String> details;

  ResolvedEducationEntry copyWith({
    String? institution,
    String? degree,
    String? fieldOfStudy,
    String? startDate,
    String? endDate,
    List<String>? details,
  }) {
    return ResolvedEducationEntry(
      sourceBlockId: sourceBlockId,
      institution: institution ?? this.institution,
      degree: degree ?? this.degree,
      fieldOfStudy: fieldOfStudy ?? this.fieldOfStudy,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      details: details ?? this.details,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'institution': institution,
      'degree': degree,
      'field_of_study': fieldOfStudy,
      'start_date': startDate,
      'end_date': endDate,
      'details': details,
    };
  }

  factory ResolvedEducationEntry.fromMap(Map<String, Object?> map) {
    return ResolvedEducationEntry(
      sourceBlockId: map['source_block_id'] as int,
      institution: map['institution'] as String,
      degree: map['degree'] as String,
      fieldOfStudy: map['field_of_study'] as String?,
      startDate: map['start_date'] as String,
      endDate: map['end_date'] as String?,
      details: (map['details'] as List).cast<String>(),
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedEducationEntry.fromJson(Map<String, Object?> json) =>
      ResolvedEducationEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedEducationEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.institution == institution &&
        other.degree == degree &&
        other.fieldOfStudy == fieldOfStudy &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        _listEquals(other.details, details);
  }

  @override
  int get hashCode => Object.hash(
        sourceBlockId,
        institution,
        degree,
        fieldOfStudy,
        startDate,
        endDate,
        Object.hashAll(details),
      );
}

/// One resolved Project entry inside a [ResumeSnapshot]. [bullets] has
/// `override_json` already applied if present.
class ResolvedProjectEntry {
  const ResolvedProjectEntry({
    required this.sourceBlockId,
    required this.name,
    this.link,
    this.bullets = const [],
    this.status,
  });

  /// The originating `ProjectBlock.id` - reference only.
  final int sourceBlockId;

  final String name;
  final String? link;
  final List<String> bullets;

  /// Threaded straight through from `ProjectBlock.status` (migration v22) -
  /// null for any project with no planned/completed opinion. No template
  /// renderer currently reads this; it's available for a future "Planned"
  /// badge without a further migration.
  final ProjectBlockStatus? status;

  ResolvedProjectEntry copyWith({
    String? name,
    String? link,
    List<String>? bullets,
    ProjectBlockStatus? status,
  }) {
    return ResolvedProjectEntry(
      sourceBlockId: sourceBlockId,
      name: name ?? this.name,
      link: link ?? this.link,
      bullets: bullets ?? this.bullets,
      status: status ?? this.status,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'name': name,
      'link': link,
      'bullets': bullets,
      'status': status?.name,
    };
  }

  factory ResolvedProjectEntry.fromMap(Map<String, Object?> map) {
    return ResolvedProjectEntry(
      sourceBlockId: map['source_block_id'] as int,
      name: map['name'] as String,
      link: map['link'] as String?,
      bullets: (map['bullets'] as List).cast<String>(),
      status: ProjectBlockStatus.fromName(map['status'] as String?),
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedProjectEntry.fromJson(Map<String, Object?> json) =>
      ResolvedProjectEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedProjectEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.name == name &&
        other.link == link &&
        other.status == status &&
        _listEquals(other.bullets, bullets);
  }

  @override
  int get hashCode =>
      Object.hash(sourceBlockId, name, link, status, Object.hashAll(bullets));
}

/// One resolved Certification entry inside a [ResumeSnapshot].
/// `override_json` is never applied here: certifications have no
/// orderable/trimmable sub-content for an override to act on.
class ResolvedCertificationEntry {
  const ResolvedCertificationEntry({
    required this.sourceBlockId,
    required this.name,
    required this.issuer,
    this.issuedDate,
    this.credentialUrl,
  });

  /// The originating `CertificationBlock.id` - reference only.
  final int sourceBlockId;

  final String name;
  final String issuer;
  final String? issuedDate;
  final String? credentialUrl;

  ResolvedCertificationEntry copyWith({
    String? name,
    String? issuer,
    String? issuedDate,
    String? credentialUrl,
  }) {
    return ResolvedCertificationEntry(
      sourceBlockId: sourceBlockId,
      name: name ?? this.name,
      issuer: issuer ?? this.issuer,
      issuedDate: issuedDate ?? this.issuedDate,
      credentialUrl: credentialUrl ?? this.credentialUrl,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'name': name,
      'issuer': issuer,
      'issued_date': issuedDate,
      'credential_url': credentialUrl,
    };
  }

  factory ResolvedCertificationEntry.fromMap(Map<String, Object?> map) {
    return ResolvedCertificationEntry(
      sourceBlockId: map['source_block_id'] as int,
      name: map['name'] as String,
      issuer: map['issuer'] as String,
      issuedDate: map['issued_date'] as String?,
      credentialUrl: map['credential_url'] as String?,
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedCertificationEntry.fromJson(Map<String, Object?> json) =>
      ResolvedCertificationEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedCertificationEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.name == name &&
        other.issuer == issuer &&
        other.issuedDate == issuedDate &&
        other.credentialUrl == credentialUrl;
  }

  @override
  int get hashCode =>
      Object.hash(sourceBlockId, name, issuer, issuedDate, credentialUrl);
}

/// One resolved Skill entry inside a [ResumeSnapshot]. `override_json` is
/// never applied here: a skill has nothing to trim.
class ResolvedSkillEntry {
  const ResolvedSkillEntry({
    required this.sourceBlockId,
    required this.name,
    required this.category,
  });

  /// The originating `SkillEntry.id` - reference only.
  final int sourceBlockId;

  final String name;
  final SkillCategory category;

  ResolvedSkillEntry copyWith({String? name, SkillCategory? category}) {
    return ResolvedSkillEntry(
      sourceBlockId: sourceBlockId,
      name: name ?? this.name,
      category: category ?? this.category,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'name': name,
      'category': category.name,
    };
  }

  factory ResolvedSkillEntry.fromMap(Map<String, Object?> map) {
    return ResolvedSkillEntry(
      sourceBlockId: map['source_block_id'] as int,
      name: map['name'] as String,
      category: SkillCategory.values.byName(map['category'] as String),
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedSkillEntry.fromJson(Map<String, Object?> json) =>
      ResolvedSkillEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedSkillEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.name == name &&
        other.category == category;
  }

  @override
  int get hashCode => Object.hash(sourceBlockId, name, category);
}

/// One resolved generic/custom section inside a [ResumeSnapshot] - see
/// `CustomSectionBlock`'s own doc comment for why this exists. [title] is
/// carried through exactly as found/entered; [entries] is `override_json`
/// -unaffected (the same "no orderable/trimmable sub-content" reasoning
/// [ResolvedCertificationEntry] already documents - a generic section has
/// no override concept of its own).
class ResolvedCustomSectionEntry {
  const ResolvedCustomSectionEntry({
    required this.sourceBlockId,
    required this.title,
    this.entries = const [],
  });

  /// The originating `CustomSectionBlock.id` - reference only.
  final int sourceBlockId;

  final String title;
  final List<String> entries;

  ResolvedCustomSectionEntry copyWith({
    String? title,
    List<String>? entries,
  }) {
    return ResolvedCustomSectionEntry(
      sourceBlockId: sourceBlockId,
      title: title ?? this.title,
      entries: entries ?? this.entries,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'source_block_id': sourceBlockId,
      'title': title,
      'entries': entries,
    };
  }

  factory ResolvedCustomSectionEntry.fromMap(Map<String, Object?> map) {
    return ResolvedCustomSectionEntry(
      sourceBlockId: map['source_block_id'] as int,
      title: map['title'] as String,
      entries: (map['entries'] as List).cast<String>(),
    );
  }

  Map<String, Object?> toJson() => toMap();

  factory ResolvedCustomSectionEntry.fromJson(Map<String, Object?> json) =>
      ResolvedCustomSectionEntry.fromMap(json);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedCustomSectionEntry &&
        other.sourceBlockId == sourceBlockId &&
        other.title == title &&
        _listEquals(other.entries, entries);
  }

  @override
  int get hashCode => Object.hash(sourceBlockId, title, Object.hashAll(entries));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
