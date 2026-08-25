import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../models/certification_block.dart';
import '../../../../../models/custom_section_block.dart';
import '../../../../../models/education_block.dart';
import '../../../../../models/experience_block.dart';
import '../../../../../models/project_block.dart';
import '../../../../../providers/app_providers.dart';

/// The four block-owning libraries (Experience/Education/Project/
/// Certification) - mirrors [resumeListProvider]'s exact shape: app-wide,
/// not resume-scoped, read-only lists for the "Add existing" pickers and
/// the Block Editor screens' own load step. Skills already have
/// `skillEntryListProvider` (Batch 4); these four complete the set Batch 5's
/// UI needs to render and pick from.
final experienceBlockListProvider = FutureProvider<List<ExperienceBlock>>((ref) {
  return ref.watch(experienceBlockRepositoryProvider).getAll();
});

final educationBlockListProvider = FutureProvider<List<EducationBlock>>((ref) {
  return ref.watch(educationBlockRepositoryProvider).getAll();
});

final projectBlockListProvider = FutureProvider<List<ProjectBlock>>((ref) {
  return ref.watch(projectBlockRepositoryProvider).getAll();
});

final certificationBlockListProvider = FutureProvider<List<CertificationBlock>>((ref) {
  return ref.watch(certificationBlockRepositoryProvider).getAll();
});

/// Beta data-fidelity addition (docs/v3/implementation/03-decisions.md) -
/// same shape as the four above, backing the Editor's generic/custom
/// section list.
final customSectionBlockListProvider = FutureProvider<List<CustomSectionBlock>>((ref) {
  return ref.watch(customSectionBlockRepositoryProvider).getAll();
});

/// `autoDispose` per-id reads (Phase 4B convention - see `meetingByIdProvider`'s
/// doc comment) - each one's only consumer is its own Block Editor screen in
/// "edit" mode, watching for as long as that screen is open and no longer.
final experienceBlockByIdProvider =
    FutureProvider.autoDispose.family<ExperienceBlock?, int>((ref, id) {
  return ref.watch(experienceBlockRepositoryProvider).getById(id);
});

final educationBlockByIdProvider =
    FutureProvider.autoDispose.family<EducationBlock?, int>((ref, id) {
  return ref.watch(educationBlockRepositoryProvider).getById(id);
});

final projectBlockByIdProvider =
    FutureProvider.autoDispose.family<ProjectBlock?, int>((ref, id) {
  return ref.watch(projectBlockRepositoryProvider).getById(id);
});

final certificationBlockByIdProvider =
    FutureProvider.autoDispose.family<CertificationBlock?, int>((ref, id) {
  return ref.watch(certificationBlockRepositoryProvider).getById(id);
});

final customSectionBlockByIdProvider =
    FutureProvider.autoDispose.family<CustomSectionBlock?, int>((ref, id) {
  return ref.watch(customSectionBlockRepositoryProvider).getById(id);
});
