import 'role_category.dart';
import 'role_category_catalog.dart';

/// Maps free text (a searched role name, or a short pasted job title) to
/// the closest [RoleCategory] - purely deterministic (exact/alias match,
/// then substring, then whole-word overlap), mirroring
/// `ResumeJdAnalyzer`'s own "no AI needed for a confident local match"
/// style. Never returns null and never throws:
/// [RoleCategoryCatalog.generalFresher] is the explicit fallback so an
/// unrecognized role can never fail the Beginner Resume flow (R-10's own
/// requirement).
class RoleCategoryMatcher {
  const RoleCategoryMatcher();

  RoleCategory match(String freeText) {
    final normalized = _normalize(freeText);
    if (normalized.isEmpty) return RoleCategoryCatalog.generalFresher;

    // 1. Exact match against a category's own display name or one of its
    // aliases - the common case for the searchable picker and for a
    // cleanly-pasted short title ("Sales Executive", "bde").
    for (final category in RoleCategoryCatalog.all) {
      if (_normalize(category.displayName) == normalized) return category;
      if (category.aliases.contains(normalized)) return category;
    }

    // 2. Substring match either direction - handles real-world noise
    // around a short pasted title ("Urgent hiring: Data Entry Operator",
    // "Sales Executive - Fresher").
    for (final category in RoleCategoryCatalog.all) {
      final candidates = {_normalize(category.displayName), ...category.aliases};
      for (final candidate in candidates) {
        if (candidate.length < 4) continue; // too short to substring-match reliably
        if (normalized.contains(candidate) || candidate.contains(normalized)) {
          return category;
        }
      }
    }

    // 3. Whole-word overlap - the category sharing the most real words
    // with the input wins, as long as at least one word actually matched
    // (never picks a category on zero real signal).
    final inputTokens = _tokens(normalized);
    RoleCategory? best;
    var bestScore = 0;
    for (final category in RoleCategoryCatalog.all) {
      final candidateTokens = <String>{
        ..._tokens(_normalize(category.displayName)),
        for (final alias in category.aliases) ..._tokens(alias),
      };
      final overlap = inputTokens.intersection(candidateTokens).length;
      if (overlap > bestScore) {
        bestScore = overlap;
        best = category;
      }
    }
    if (best != null && bestScore > 0) return best;

    return RoleCategoryCatalog.generalFresher;
  }

  Set<String> _tokens(String normalized) =>
      normalized.split(' ').where((t) => t.length > 2).toSet();

  String _normalize(String text) => text
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
