import '../../models/job_description.dart';

enum _SectionKind { responsibilities, requirements, education, experience, certifications }

final Map<_SectionKind, Set<String>> _sectionKeywords = {
  _SectionKind.responsibilities: {
    'responsibilities',
    'duties',
    'key responsibilities',
    'job duties',
    'essential duties',
    'what you will do',
    "what you'll do",
    'role overview',
    'day to day',
  },
  _SectionKind.requirements: {
    'requirements',
    'qualifications',
    'required skills',
    'required qualifications',
    'skills',
    'technical skills',
    'minimum qualifications',
    'must have',
    'what we are looking for',
    "what we're looking for",
    'preferred qualifications',
    'preferred skills',
    'nice to have',
    'bonus points',
  },
  _SectionKind.education: {
    'education',
    'education requirements',
    'educational requirements',
    'education qualifications',
  },
  _SectionKind.experience: {
    'experience',
    'experience requirements',
    'required experience',
  },
  _SectionKind.certifications: {
    'certifications',
    'certification requirements',
    'required certifications',
    'licenses',
    'licenses and certifications',
  },
};

final _bulletPattern = RegExp(r'^[-*•▪●‣>]\s+|^\d+[.)]\s+');
final _titleLabelPattern = RegExp(r'^(?:job\s*title|position|role)\s*:\s*(.+)$', caseSensitive: false);
final _companyLabelPattern = RegExp(r'^(?:company|organization|employer)\s*:\s*(.+)$', caseSensitive: false);

/// A range ("2-4 years", "2 to 4 years") - tried before the open-ended
/// pattern below so "2-4 years" isn't misread as just "4 years".
final _experienceRangePattern =
    RegExp(r'(\d{1,2})\s*(?:-|–|to)\s*(\d{1,2})\+?\s*years?', caseSensitive: false);

/// An open-ended or single-number requirement ("3+ years", "5 years",
/// "minimum 2 years", "at least 3 years").
final _experienceMinPattern = RegExp(
  r'(?:minimum\s+(?:of\s+)?|at\s+least\s+|min\.?\s+)?(\d{1,2})\+?\s*years?',
  caseSensitive: false,
);

/// Turns raw, already-extracted plain text (from any of the four Batch
/// 7-supported formats) into a [ParsedJobDescription] - mirrors
/// `ResumeImportParser`'s exact reasoning and shape
/// (lib/services/resume/resume_import_parser.dart): a pure,
/// single-pass, deterministic, keyword/regex heuristic with no I/O and no
/// AI model of any kind, so it cannot fabricate a requirement the JD text
/// doesn't actually contain.
///
/// Each requirement/responsibility line is preserved **verbatim**, never
/// split or reworded - splitting a bulleted line like "CI/CD" on its own
/// separators would corrupt genuine compound terms, and this app's own
/// "conservative matching, no speculative synonym dictionary" rule
/// (Batch 8) extends naturally to "don't guess at how to break up a
/// requirement either."
class JdParser {
  const JdParser();

  ParsedJobDescription parse(String rawText) {
    final lines = rawText.split(RegExp(r'\r\n|\r|\n'));

    final preamble = <String>[];
    final sectionLines = <_SectionKind, List<String>>{};
    _SectionKind? current;

    for (final rawLine in lines) {
      final kind = _matchHeader(rawLine);
      if (kind != null) {
        current = kind;
        continue;
      }
      if (current == null) {
        preamble.add(rawLine);
      } else {
        sectionLines.putIfAbsent(current, () => []).add(rawLine);
      }
    }

    final warnings = <String>[];
    final unclassified = <String>[];

    final title = _detectTitle(preamble);
    final company = _detectCompany(preamble);

    final requirements = _nonBlankBullets(sectionLines[_SectionKind.requirements]);
    final responsibilities = _nonBlankBullets(sectionLines[_SectionKind.responsibilities]);
    final educationRequirements = _nonBlankBullets(sectionLines[_SectionKind.education]);
    final certificationRequirements = _nonBlankBullets(sectionLines[_SectionKind.certifications]);

    final experienceRequirement = _detectExperienceRequirement(rawText);
    if (experienceRequirement == null) {
      warnings.add(
        'No specific years-of-experience requirement was detected in this '
        'job description.',
      );
    }

    final experienceSectionLines = sectionLines[_SectionKind.experience];
    if (experienceSectionLines != null) {
      for (final line in _nonBlank(experienceSectionLines)) {
        // Only content the experience-requirement regex didn't already
        // capture is kept for review - avoids showing the same sentence
        // twice (once as the structured requirement, once as leftover
        // text).
        if (experienceRequirement == null || !experienceRequirement.rawText.contains(line)) {
          unclassified.add(line);
        }
      }
    }

    if (requirements.isEmpty && responsibilities.isEmpty && educationRequirements.isEmpty) {
      warnings.add(
        'No requirements or responsibilities sections could be confidently '
        'detected in this document.',
      );
    }

    for (final line in preamble) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == title) continue;
      if (_titleLabelPattern.hasMatch(trimmed) || _companyLabelPattern.hasMatch(trimmed)) continue;
      unclassified.add(trimmed);
    }

    return ParsedJobDescription(
      rawText: rawText,
      title: title,
      company: company,
      requirements: requirements,
      responsibilities: responsibilities,
      educationRequirements: educationRequirements,
      certificationRequirements: certificationRequirements,
      experienceRequirement: experienceRequirement,
      unclassifiedText: unclassified,
      warnings: warnings,
    );
  }

  _SectionKind? _matchHeader(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.length > 50) return null;
    if (_bulletPattern.hasMatch(trimmed)) return null;
    final normalized =
        trimmed.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    for (final entry in _sectionKeywords.entries) {
      if (entry.value.contains(normalized)) return entry.key;
    }
    return null;
  }

  String? _detectTitle(List<String> preamble) {
    for (final line in preamble) {
      final labelMatch = _titleLabelPattern.firstMatch(line.trim());
      if (labelMatch != null) return labelMatch.group(1)!.trim();
    }
    // No explicit "Job Title:" label - fall back to the first short,
    // non-sentence-looking preamble line. Never guessed if the first line
    // reads like a sentence (ends in a period) or is unusually long.
    for (final line in preamble) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (_companyLabelPattern.hasMatch(trimmed)) continue;
      if (trimmed.endsWith('.') || trimmed.split(RegExp(r'\s+')).length > 10) return null;
      return trimmed;
    }
    return null;
  }

  String? _detectCompany(List<String> preamble) {
    for (final line in preamble) {
      final labelMatch = _companyLabelPattern.firstMatch(line.trim());
      if (labelMatch != null) return labelMatch.group(1)!.trim();
    }
    // Deliberately no fallback beyond an explicit label - without one,
    // there is no reliable way to distinguish a company name from a job
    // title or any other short top-of-document line, so this stays
    // unknown rather than guessed.
    return null;
  }

  JdExperienceRequirement? _detectExperienceRequirement(String rawText) {
    for (final line in rawText.split(RegExp(r'\r\n|\r|\n'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final rangeMatch = _experienceRangePattern.firstMatch(trimmed);
      if (rangeMatch != null) {
        return JdExperienceRequirement(
          minYears: int.parse(rangeMatch.group(1)!),
          maxYears: int.parse(rangeMatch.group(2)!),
          rawText: trimmed,
        );
      }

      final minMatch = _experienceMinPattern.firstMatch(trimmed);
      if (minMatch != null) {
        return JdExperienceRequirement(
          minYears: int.parse(minMatch.group(1)!),
          rawText: trimmed,
        );
      }
    }
    return null;
  }

  List<String> _nonBlank(List<String> lines) =>
      lines.map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  List<String> _nonBlankBullets(List<String>? lines) {
    if (lines == null) return const [];
    return _nonBlank(lines).map((l) => l.replaceFirst(_bulletPattern, '').trim()).where((l) => l.isNotEmpty).toList();
  }
}
