import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../models/resume.dart';
import '../../../../../providers/app_providers.dart';

/// Creates a new, minimal Resume identity (a title and an empty Profile) -
/// mirrors `createFolder`'s exact shape
/// (lib/features/documents/presentation/providers/folder_providers.dart): a
/// single-repository insert plus a list invalidation needs no use-case
/// orchestration or controller of its own. Returns the new Resume's id so
/// the caller can navigate straight into its Editor.
Future<int> createResume(WidgetRef ref, String title) async {
  final now = DateTime.now();
  final id = await ref.read(resumeRepositoryProvider).insert(
        Resume(id: null, title: title, fullName: '', createdAt: now, updatedAt: now),
      );
  ref.invalidate(resumeListProvider);
  return id;
}

/// Every Resume, most recently updated first - mirrors
/// `meetingListProvider`'s exact shape and reasoning
/// (lib/features/meetings/presentation/providers/meeting_providers.dart): a
/// plain [FutureProvider] is enough for now (read-only in this phase) -
/// once the Editor/List screens can create, edit, or delete a Resume
/// (Batch 5), those mutating actions will call
/// `ref.invalidate(resumeListProvider)` to refresh the list.
///
/// Includes the "My Profile" resume (if one exists) alongside every
/// job-specific resume - `ResumeListScreen` itself splits it out for
/// presentation (a distinct pinned section, never mixed anonymously into
/// the regular list), but this provider stays the one source of truth for
/// "every Resume row" the same way it always has, rather than growing a
/// second, filtered variant.
final resumeListProvider = FutureProvider<List<Resume>>((ref) {
  return ref.watch(resumeRepositoryProvider).getAll();
});

/// "My Profile" (Product Validation phase) - the single resume with
/// `is_profile = 1`, or `null` if the user hasn't set one up yet. A plain
/// [FutureProvider], not `.autoDispose`, mirroring [resumeListProvider]'s
/// own "app-wide, cheap to keep warm" reasoning - both the list screen's
/// pinned section and the "Create Resume from Profile" entry point watch
/// this.
final profileResumeProvider = FutureProvider<Resume?>((ref) {
  return ref.watch(resumeRepositoryProvider).getProfile();
});

/// Opens the user's existing "My Profile", or creates one on first use and
/// opens that - mirrors [createResume]'s shape exactly, except the title
/// is fixed ("My Profile", never user-entered - unlike a job-specific
/// resume, there's only ever one and it doesn't need naming) and
/// `isProfile: true` is set before the very first insert, then
/// [ResumeRepository.setAsProfile] is called to satisfy that method's own
/// "designates and unsets any previous" contract even on first creation
/// (a no-op in that case, but keeps exactly one code path responsible for
/// the "at most one profile" invariant rather than trusting `insert`
/// alone to get a boolean right).
Future<int> openOrCreateProfile(WidgetRef ref) async {
  final existing = await ref.read(resumeRepositoryProvider).getProfile();
  if (existing != null) return existing.id!;

  final now = DateTime.now();
  final id = await ref.read(resumeRepositoryProvider).insert(
        Resume(id: null, title: 'My Profile', fullName: '', isProfile: true, createdAt: now, updatedAt: now),
      );
  await ref.read(resumeRepositoryProvider).setAsProfile(id);
  ref.invalidate(resumeListProvider);
  ref.invalidate(profileResumeProvider);
  return id;
}

/// `autoDispose` (Phase 4B convention - see `meetingByIdProvider`'s doc
/// comment for the full reasoning) - a plain `.family` provider without it
/// caches one entry per unique id forever, for the life of the process. The
/// only consumer will be the Resume Editor screen, watching this for as
/// long as it's on screen and no longer.
final resumeByIdProvider =
    FutureProvider.autoDispose.family<Resume?, int>((ref, id) {
  return ref.watch(resumeRepositoryProvider).getById(id);
});
