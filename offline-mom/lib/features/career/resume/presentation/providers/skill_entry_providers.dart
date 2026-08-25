import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../models/skill_entry.dart';
import '../../../../../providers/app_providers.dart';

/// The whole skills library, for the picker - mirrors [resumeListProvider]'s
/// exact shape and reasoning: a plain, non-family [FutureProvider], since
/// skills are app-wide, not scoped to one resume. Read-only in this phase -
/// once the inline "+ New skill" action is wired to a controller (Batch 5),
/// it will call `ref.invalidate(skillEntryListProvider)` to refresh.
final skillEntryListProvider = FutureProvider<List<SkillEntry>>((ref) {
  return ref.watch(skillEntryRepositoryProvider).getAll();
});
