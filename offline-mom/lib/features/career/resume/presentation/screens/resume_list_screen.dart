import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../models/resume.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../shared/widgets/confirm_dialog.dart';
import '../../../../../shared/widgets/empty_state.dart';
import '../../../../../shared/widgets/entrance_fade.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../../../../../shared/widgets/skeleton_loader.dart';
import '../../../../../shared/widgets/text_input_dialog.dart';
import '../providers/resume_providers.dart';
import 'resume_model_upgrade_prompt_screen.dart';

/// Every Resume, most recently updated first - the minimum reachability
/// screen this Milestone needs: Batch 5's own spec describes the Editor,
/// Block Editors and Versions screens in detail but assumes *some* list
/// entry point already exists, and none did before this batch. Mirrors
/// `DocumentsScreen`'s exact list/empty/FAB shape
/// (lib/features/documents/presentation/screens/documents_screen.dart).
///
/// **Milestone 4 (docs/v3/01-prd.md §13, FR3-15):** also the gate for the
/// one-time model-upgrade prompt - the first, and only, screen every path
/// into the Resume feature passes through (Home's Resume entry, and this
/// screen itself is the `/resume` route target), so it's the natural place
/// to show it once, on first entry, per [AppSettings.hasSeenResumeModelUpgradePrompt].
class ResumeListScreen extends ConsumerStatefulWidget {
  const ResumeListScreen({super.key});

  @override
  ConsumerState<ResumeListScreen> createState() => _ResumeListScreenState();
}

class _ResumeListScreenState extends ConsumerState<ResumeListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowModelUpgradePrompt());
  }

  Future<void> _maybeShowModelUpgradePrompt() async {
    if (!mounted) return;
    if (ref.read(settingsControllerProvider).hasSeenResumeModelUpgradePrompt) return;
    await showResumeModelUpgradePromptDialog(context, ref);
  }

  Future<void> _createResume(BuildContext context, WidgetRef ref) async {
    final entered = await showTextInputDialog(
      context,
      title: 'New resume',
      labelText: 'Resume title',
      helperText: 'e.g. "Backend-Focused" or "Full-Stack"',
      confirmLabel: 'Create',
    );
    if (entered == null || entered.isEmpty) return;
    final id = await createResume(ref, entered);
    if (context.mounted) context.push(RoutePaths.resumeEditorPath(id));
  }

  Future<void> _openProfile(BuildContext context, WidgetRef ref) async {
    final id = await openOrCreateProfile(ref);
    if (context.mounted) context.push(RoutePaths.resumeEditorPath(id));
  }

  @override
  Widget build(BuildContext context) {
    final resumesAsync = ref.watch(resumeListProvider);
    final profileAsync = ref.watch(profileResumeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file_outlined),
            tooltip: 'Import resume',
            onPressed: () => context.push(RoutePaths.resumeImport),
          ),
          PopupMenuButton<void>(
            icon: const Icon(Icons.work_outline_rounded),
            tooltip: 'Job description tools',
            itemBuilder: (context) => [
              // R-7 §3: a clear, first-class entry for building a brand-new
              // resume from a JD - distinct from tailoring one that already
              // exists, not buried as a secondary option under it.
              PopupMenuItem(
                onTap: () => context.push(RoutePaths.jdToResume),
                child: const ListTile(
                  leading: Icon(Icons.auto_awesome_outlined),
                  title: Text('Create resume from a Job Description'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                onTap: () => context.push(RoutePaths.jdImport),
                child: const ListTile(
                  leading: Icon(Icons.fact_check_outlined),
                  title: Text('Tailor an existing resume to a Job Description'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _MyProfileCard(
            profileAsync: profileAsync,
            onTap: () => _openProfile(context, ref),
            onCreateResume: profileAsync.valueOrNull == null
                ? null
                : () => context.push(RoutePaths.resumeCreateFromProfile),
          ),
          // R-10: a clearly visible, first-class entry point - visually
          // comparable to the "My Profile" card above, not buried behind
          // an icon-only popup menu the way "Create resume from a Job
          // Description" (R-7) is (an R-8 audit finding this deliberately
          // avoids repeating).
          _BeginnerResumeCard(onTap: () => context.push(RoutePaths.resumeBeginner)),
          // AI-Tailored Resume from Job Description - same prominent,
          // full-width card treatment as _MyProfileCard/_BeginnerResumeCard
          // above, deliberately not buried in the "Job description tools"
          // popup menu (which stays untouched) - see this screen's own
          // R-8/R-10 comment on why that menu is a known discoverability
          // gap this new card avoids repeating.
          _JdTailoredResumeCard(onTap: () => context.push(RoutePaths.resumeJdTailored)),
          Expanded(
            child: resumesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: SkeletonCardList(),
              ),
              error: (err, _) => ErrorState(title: "Couldn't load your resumes", error: err),
              data: (allResumes) {
                // The profile resume already has its own pinned card above
                // - never listed twice.
                final resumes = allResumes.where((r) => !r.isProfile).toList();
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: resumes.isEmpty
                      ? EmptyState(
                          key: const ValueKey('resumes-empty'),
                          icon: Icons.description_outlined,
                          title: 'No resumes yet',
                          message: 'Create a resume, then build it up from reusable '
                              'experience, education, project and certification '
                              'blocks.',
                          actionLabel: 'New resume',
                          onAction: () => _createResume(context, ref),
                        )
                      : ListView.separated(
                          key: const ValueKey('resumes-list'),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                          itemCount: resumes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final resume = resumes[index];
                            return EntranceFade(
                              delay: Duration(milliseconds: 20 * index),
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.description_outlined),
                                  ),
                                  title: Text(resume.title),
                                  subtitle: Text(
                                    resume.fullName.isEmpty ? 'No name set yet' : resume.fullName,
                                  ),
                                  onTap: () =>
                                      context.push(RoutePaths.resumeEditorPath(resume.id!)),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded),
                                    tooltip: 'Delete resume',
                                    onPressed: () async {
                                      final confirmed = await showDestructiveConfirmDialog(
                                        context,
                                        title: 'Delete "${resume.title}"?',
                                        message: 'Every saved version and exported PDF for '
                                            'this resume is deleted too. Library blocks it '
                                            'uses are not affected.',
                                      );
                                      if (!confirmed) return;
                                      await ref.read(deleteResumeUseCaseProvider)(resume.id!);
                                      ref.invalidate(resumeListProvider);
                                    },
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createResume(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New resume'),
      ),
    );
  }
}

/// R-10: "Create a Beginner Resume" - for a user with little/no experience
/// or projects who wouldn't know where to start with the standard "New
/// resume" blank editor. Same card treatment/prominence as [_MyProfileCard]
/// directly above it (full-width, filled container, its own icon+subtitle),
/// deliberately not an AppBar icon or popup menu item.
class _BeginnerResumeCard extends StatelessWidget {
  const _BeginnerResumeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.tertiaryContainer,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.tertiary,
            child: Icon(Icons.emoji_objects_outlined, color: scheme.onTertiary),
          ),
          title: Text(
            'Create a Beginner Resume',
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer),
          ),
          subtitle: Text(
            'New to resumes? Answer a few simple questions and get a '
            'job-ready draft, even with no experience or projects.',
            style: TextStyle(color: scheme.onTertiaryContainer),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: scheme.onTertiaryContainer),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// "Create Resume for a Job" (AI-Tailored Resume from Job Description) -
/// fills basic details, pastes/imports a JD, then reviews an AI-proposed
/// summary/skills/project-ideas before any resume is created. Same card
/// treatment/prominence as [_BeginnerResumeCard] directly above it, its own
/// icon+color so the three stacked cards (Profile/Beginner/JD-tailored)
/// stay visually distinct from one another.
class _JdTailoredResumeCard extends StatelessWidget {
  const _JdTailoredResumeCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.secondaryContainer,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.secondary,
            child: Icon(Icons.work_history_outlined, color: scheme.onSecondary),
          ),
          title: Text(
            'Create Resume for a Job',
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
          ),
          subtitle: Text(
            "Enter a job description and we'll help tailor your resume for it.",
            style: TextStyle(color: scheme.onSecondaryContainer),
          ),
          trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSecondaryContainer),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// The pinned "My Profile" entry point (Product Validation phase) - always
/// the first thing on the Resume list, visually distinct from a
/// job-specific resume (filled surface, person icon) since it isn't one:
/// it's "the complete career source of truth" every resume gets created
/// from, never itself a resume the user applies with. Before the user has
/// set one up, this same card offers to create it - one entry point, not
/// two different states the user has to learn.
class _MyProfileCard extends StatelessWidget {
  const _MyProfileCard({required this.profileAsync, required this.onTap, this.onCreateResume});

  final AsyncValue<Resume?> profileAsync;
  final VoidCallback onTap;

  /// Null when no profile exists yet - "Create Resume from Profile" only
  /// makes sense once there's something to create it from.
  final VoidCallback? onCreateResume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = profileAsync.valueOrNull;
    final hasProfile = profile != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.primaryContainer,
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primary,
                child: Icon(Icons.badge_outlined, color: scheme.onPrimary),
              ),
              title: Text(
                'My Profile',
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
              ),
              subtitle: Text(
                hasProfile
                    ? 'Your complete career information - create resumes from it.'
                    : 'Set up your career source of truth once, reuse it for every resume.',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
              trailing: Icon(Icons.chevron_right_rounded, color: scheme.onPrimaryContainer),
              onTap: onTap,
            ),
            if (onCreateResume != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onCreateResume,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create Resume from Profile'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
