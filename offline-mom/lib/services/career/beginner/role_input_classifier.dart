/// Decides whether pasted text in the Beginner Resume flow's "I have the
/// Job Description" step is a short job title ("Sales Executive", "Data
/// Entry Operator") or genuine JD text - R-10's explicit requirement: a
/// short title must go through [RoleCategoryMatcher], never be forced
/// through the full JD parser (which would just come back nearly empty).
///
/// Deliberately a simple, explainable heuristic (word count + no newlines +
/// no typical JD structure marker), not a model call - this decision has to
/// work with zero AI installed, same as the rest of this flow.
bool looksLikeJobTitle(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.contains('\n')) return false;
  if (trimmed.length > 60) return false;

  final wordCount = trimmed.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (wordCount > 6) return false;

  // A real JD, even a short-looking one, almost always names at least one
  // structural cue a bare title never does.
  const jdMarkers = [
    'responsibilit',
    'requirement',
    'qualification',
    'experience required',
    'skills required',
    'job description',
    'about the role',
    'about the company',
    'ctc',
    'salary',
    'apply',
  ];
  final lower = trimmed.toLowerCase();
  if (jdMarkers.any(lower.contains)) return false;

  return true;
}
