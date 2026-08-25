import 'resume_import_parser.dart';

/// docs/v3/01-prd.md §10 (Milestone 4): "when the deterministic parser's
/// `unclassifiedText` ratio for a document exceeds a defined threshold
/// (recommendation: unclassified text exceeding 30% of total non-preamble
/// content - tune during implementation, not a blocking decision)..." - the
/// PRD explicitly leaves the exact number to implementation tuning; its own
/// stated recommendation is used as-is, with no observed need to deviate.
const double kImportSecondPassRatioThreshold = 0.30;

/// The character-count ratio of [draft]'s still-unclassified text against
/// everything the deterministic parser was able to structure plus what it
/// couldn't - "non-preamble content" per the PRD. Contact info
/// (`fullName`/`email`/`phone`/`location`/`links`) is deliberately excluded
/// from both sides of the ratio, since that content was never at risk of
/// the kind of section-content misclassification this threshold exists to
/// catch.
double importUnclassifiedRatio(ParsedResumeDraft draft) {
  final unclassifiedChars = draft.unclassifiedText.fold<int>(0, (sum, s) => sum + s.length);
  final classifiedChars = _classifiedCharCount(draft);
  final total = unclassifiedChars + classifiedChars;
  if (total == 0) return 0;
  return unclassifiedChars / total;
}

int _classifiedCharCount(ParsedResumeDraft draft) {
  var total = 0;
  for (final e in draft.experience) {
    total += e.role.length + e.company.length;
    for (final b in e.bullets) {
      total += b.length;
    }
  }
  for (final e in draft.education) {
    total += e.institution.length + e.degree.length + (e.fieldOfStudy?.length ?? 0);
    for (final d in e.details) {
      total += d.length;
    }
  }
  for (final p in draft.projects) {
    total += p.name.length;
    for (final b in p.bullets) {
      total += b.length;
    }
  }
  for (final c in draft.certifications) {
    total += c.name.length + c.issuer.length;
  }
  for (final s in draft.skills) {
    total += s.name.length;
  }
  return total;
}

/// Whether the import review screen should offer the optional LLM-assisted
/// second pass at all - both "there is enough unclassified text to be worth
/// it" ([kImportSecondPassRatioThreshold]) and "there is actually something
/// for a second pass to work on".
bool shouldOfferImportSecondPass(ParsedResumeDraft draft) {
  if (draft.unclassifiedText.isEmpty) return false;
  return importUnclassifiedRatio(draft) > kImportSecondPassRatioThreshold;
}

/// Merges [secondPass] (the result of re-running [ResumeImportParser] over
/// the LLM's reorganized version of [original]'s leftover unclassified
/// text - see `GenerateImportSecondPassUseCase`) into [original].
///
/// Deterministic first-pass entries are the trust anchor and are never
/// replaced or reordered - newly-structured entries from the second pass
/// are only ever appended after them. [original]'s `unclassifiedText` is
/// replaced with whatever [secondPass] still couldn't classify (never
/// grows: the second pass only ever re-examines what was already
/// unclassified). Contact info and `warnings` always come from [original]
/// - a second pass over leftover section content must never overwrite
/// identity fields the first, more reliable pass already determined.
ParsedResumeDraft mergeImportSecondPass(ParsedResumeDraft original, ParsedResumeDraft secondPass) {
  return original.copyWith(
    experience: [...original.experience, ...secondPass.experience],
    education: [...original.education, ...secondPass.education],
    projects: [...original.projects, ...secondPass.projects],
    certifications: [...original.certifications, ...secondPass.certifications],
    skills: [...original.skills, ...secondPass.skills],
    unclassifiedText: secondPass.unclassifiedText,
  );
}
