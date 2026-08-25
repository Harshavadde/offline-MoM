import '../../../models/skill_entry.dart';

/// One deterministic skill suggestion for a [RoleCategory] - a name plus
/// which [SkillCategory] bucket it belongs in once attached (matching
/// [SkillEntry]'s own schema, so a suggestion the user accepts becomes a
/// real [SkillEntry] with zero translation step).
///
/// A suggestion is exactly that - a name a role commonly involves, never a
/// claim the user has it. [CreateBeginnerResumeUseCase] only ever attaches
/// a [SuggestedSkill] the caller explicitly passed as confirmed
/// (`confirmedSkillNames`); nothing here is ever attached automatically.
class SuggestedSkill {
  const SuggestedSkill(this.name, this.category);

  final String name;
  final SkillCategory category;
}

/// One curated, entry-level job category - the Beginner Resume flow's
/// deterministic alternative to full JD parsing (R-10). Every field here is
/// static, hand-authored data (no AI, no network, no database) - see
/// [RoleCategoryCatalog]'s own doc comment for why this stays a small,
/// fixed list rather than a growing database.
///
/// [summaryFocus] is deliberately just a short, neutral phrase describing
/// what the *role* is about (e.g. "sales and customer relationship
/// -building") - never a sentence claiming the user already has any
/// ability. It's the only piece of role data that reaches
/// [CreateBeginnerResumeUseCase]'s generated professional-summary text;
/// [suggestedSkills] are shown separately, as suggestions, and only ever
/// become part of the resume if the user explicitly confirms them.
class RoleCategory {
  const RoleCategory({
    required this.id,
    required this.displayName,
    required this.aliases,
    required this.summaryFocus,
    required this.suggestedSkills,
  });

  final String id;
  final String displayName;

  /// Lowercase alternate names/abbreviations a user might type when
  /// searching or pasting a short job title (e.g. "bde", "call center") -
  /// matched by [RoleCategoryMatcher], never shown to the user directly.
  final Set<String> aliases;

  final String summaryFocus;
  final List<SuggestedSkill> suggestedSkills;
}
