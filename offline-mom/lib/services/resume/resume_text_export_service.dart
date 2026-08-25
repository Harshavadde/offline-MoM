import '../../models/resume_snapshot.dart';

/// Builds plain-text and Markdown representations of an already-compiled
/// [ResumeSnapshot] - the M1 "plain text / Markdown" export requirement,
/// mirroring [ChatExportService]'s exact shape
/// (lib/features/chat/presentation/providers/chat_export_service.dart): a
/// plain class with a `const` constructor, pure `StringBuffer` builders, no
/// repository access and no file I/O. A pure function of already-resolved
/// data, the same reasoning [ResumePdfExportService] already applies to its
/// own `render()` - this service never re-reads the database, it only
/// formats what [ResumeCompilerService] already resolved.
///
/// Kept separate from [ResumePdfExportService] rather than folded into it:
/// that service is DI-injected behind an abstract interface specifically
/// for the PDF renderer it wraps, while text/Markdown need neither - the
/// same "one clean responsibility per service" split this codebase already
/// applies to `PdfExportService` vs. the plain-text/Markdown half of
/// `ChatExportService`.
///
/// Section order and content are fixed to what [ResumeSnapshot] itself
/// represents - Profile, Experience, Education, Projects, Certifications,
/// Skills - in that order; a section with no entries is omitted entirely,
/// never printed as an empty heading. Nothing is invented: a null optional
/// field (location, end date, links, field of study, issued date,
/// credential URL) is simply left out of its line, never rendered as the
/// literal word "null".
class ResumeTextExportService {
  const ResumeTextExportService();

  String buildPlainText(ResumeSnapshot snapshot) {
    final profile = snapshot.profile;
    final buffer = StringBuffer()..writeln(profile.fullName);

    final contactLine = _contactLine(profile);
    if (contactLine != null) buffer.writeln(contactLine);
    final linksLine = _linksLine(profile);
    if (linksLine != null) buffer.writeln(linksLine);
    buffer.writeln();

    if (snapshot.experience.isNotEmpty) {
      buffer.writeln('EXPERIENCE');
      buffer.writeln();
      for (final e in snapshot.experience) {
        buffer.writeln('${e.role} - ${e.company}');
        buffer.writeln(_dateRangeLine(e.startDate, e.endDate, location: e.location));
        for (final bullet in e.bullets) {
          buffer.writeln('- $bullet');
        }
        buffer.writeln();
      }
    }

    if (snapshot.education.isNotEmpty) {
      buffer.writeln('EDUCATION');
      buffer.writeln();
      for (final ed in snapshot.education) {
        buffer.writeln(_degreeLine(ed.degree, ed.fieldOfStudy, ed.institution));
        buffer.writeln(_dateRangeLine(ed.startDate, ed.endDate));
        for (final detail in ed.details) {
          buffer.writeln('- $detail');
        }
        buffer.writeln();
      }
    }

    if (snapshot.projects.isNotEmpty) {
      buffer.writeln('PROJECTS');
      buffer.writeln();
      for (final p in snapshot.projects) {
        buffer.writeln(p.name);
        if (p.link != null) buffer.writeln(p.link);
        for (final bullet in p.bullets) {
          buffer.writeln('- $bullet');
        }
        buffer.writeln();
      }
    }

    if (snapshot.certifications.isNotEmpty) {
      buffer.writeln('CERTIFICATIONS');
      buffer.writeln();
      for (final c in snapshot.certifications) {
        buffer.writeln(_certificationLine(c));
        if (c.credentialUrl != null) buffer.writeln(c.credentialUrl);
      }
      buffer.writeln();
    }

    if (snapshot.skills.isNotEmpty) {
      buffer.writeln('SKILLS');
      buffer.writeln();
      buffer.writeln(snapshot.skills.map((s) => s.name).join(', '));
    }

    return buffer.toString().trimRight();
  }

  String buildMarkdown(ResumeSnapshot snapshot) {
    final profile = snapshot.profile;
    final buffer = StringBuffer()
      ..writeln('# ${profile.fullName}')
      ..writeln();

    final contactLine = _contactLine(profile);
    if (contactLine != null) {
      buffer.writeln(contactLine);
      buffer.writeln();
    }
    final linksLine = _linksLine(profile);
    if (linksLine != null) {
      buffer.writeln(linksLine);
      buffer.writeln();
    }

    if (snapshot.experience.isNotEmpty) {
      buffer.writeln('## Experience');
      buffer.writeln();
      for (final e in snapshot.experience) {
        buffer.writeln('**${e.role} - ${e.company}**');
        buffer.writeln();
        buffer.writeln(_dateRangeLine(e.startDate, e.endDate, location: e.location));
        buffer.writeln();
        for (final bullet in e.bullets) {
          buffer.writeln('- $bullet');
        }
        buffer.writeln();
      }
    }

    if (snapshot.education.isNotEmpty) {
      buffer.writeln('## Education');
      buffer.writeln();
      for (final ed in snapshot.education) {
        buffer.writeln('**${_degreeLine(ed.degree, ed.fieldOfStudy, ed.institution)}**');
        buffer.writeln();
        buffer.writeln(_dateRangeLine(ed.startDate, ed.endDate));
        buffer.writeln();
        for (final detail in ed.details) {
          buffer.writeln('- $detail');
        }
        buffer.writeln();
      }
    }

    if (snapshot.projects.isNotEmpty) {
      buffer.writeln('## Projects');
      buffer.writeln();
      for (final p in snapshot.projects) {
        buffer.writeln('**${p.name}**');
        if (p.link != null) {
          buffer.writeln();
          buffer.writeln(p.link);
        }
        buffer.writeln();
        for (final bullet in p.bullets) {
          buffer.writeln('- $bullet');
        }
        buffer.writeln();
      }
    }

    if (snapshot.certifications.isNotEmpty) {
      buffer.writeln('## Certifications');
      buffer.writeln();
      for (final c in snapshot.certifications) {
        buffer.writeln(_certificationLine(c));
        if (c.credentialUrl != null) buffer.writeln(c.credentialUrl);
        buffer.writeln();
      }
    }

    if (snapshot.skills.isNotEmpty) {
      buffer.writeln('## Skills');
      buffer.writeln();
      buffer.writeln(snapshot.skills.map((s) => s.name).join(', '));
    }

    return buffer.toString().trimRight();
  }

  /// Email/phone/location joined the same way [PwResumePdfExportService]
  /// already joins them - null entries silently excluded, never "null".
  String? _contactLine(ResumeSnapshotProfile profile) {
    final parts = [profile.email, profile.phone, profile.location]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' | ');
  }

  String? _linksLine(ResumeSnapshotProfile profile) {
    if (profile.links.isEmpty) return null;
    return profile.links.map((l) => '${l.label}: ${l.url}').join(' | ');
  }

  String _dateRangeLine(String startDate, String? endDate, {String? location}) {
    final range = '$startDate - ${endDate ?? 'Present'}';
    return location != null ? '$range | $location' : range;
  }

  String _degreeLine(String degree, String? fieldOfStudy, String institution) {
    final degreePart = fieldOfStudy != null ? '$degree, $fieldOfStudy' : degree;
    return '$degreePart - $institution';
  }

  String _certificationLine(ResolvedCertificationEntry c) {
    return '${c.name} - ${c.issuer}${c.issuedDate != null ? ' (${c.issuedDate})' : ''}';
  }
}
