import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../ai_models/presentation/providers/profession_setup_providers.dart';
import '../../../chat/presentation/providers/chat_providers.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../documents/presentation/widgets/document_list_tile.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../../shared/widgets/entrance_fade.dart';
import '../../../../shared/widgets/inline_error_text.dart';
import '../../../../shared/widgets/section_heading.dart';
import '../../../../shared/widgets/skeleton_loader.dart';
import '../../../../shared/widgets/text_input_dialog.dart';
import '../providers/meeting_providers.dart';
import '../widgets/meeting_list_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  Future<void> _editDisplayName(BuildContext context, WidgetRef ref, String current) async {
    final name = await showTextInputDialog(
      context,
      title: 'Your name',
      labelText: 'Name',
      helperText: "Just for the greeting - there's no account or login, "
          'this never leaves your device.',
      initialValue: current,
    );
    if (name == null) return;
    await ref.read(settingsControllerProvider.notifier).setDisplayName(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingsAsync = ref.watch(meetingListProvider);
    final documentsAsync = ref.watch(documentListProvider);
    final chatsAsync = ref.watch(chatSessionListProvider);
    final displayName = ref.watch(settingsControllerProvider).displayName;
    final hasProfessionRecommendation = ref.watch(selectedProfessionProvider) != null;
    final scheme = Theme.of(context).colorScheme;

    // Phase 9.2 (Home redesign, Priority 3): Quick Actions now leads the
    // page instead of trailing it - Phase 8B.2 deliberately put "pick up
    // what you already have" first because Quick Actions was 3 identical
    // -weight tiles competing with real content. Revisited here because
    // the actual problem was Quick Actions being *underweight* and
    // undiscoverable (no AI entry point existed on Home at all - Priority
    // 4), not that it was in the wrong position - a "what can I do right
    // now" anchor belongs above a first-time user's empty "Recent
    // Meetings" state, not below it (Google Drive/Notion pattern: create
    // -new above recents). Built as a list of sections, each either empty
    // (nothing to show) or a widget list, joined by one consistent gap -
    // only between sections that actually rendered, so an empty optional
    // section (no chats yet, no documents yet) never leaves a doubled-up
    // gap behind it.
    final sections = <Widget>[];
    void addSection(List<Widget> widgets) {
      if (widgets.isEmpty) return;
      if (sections.isNotEmpty) sections.add(const SizedBox(height: 28));
      sections.addAll(widgets);
    }

    addSection([
      const SectionHeading('Quick Actions'),
      const SizedBox(height: 8),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
        children: [
          _QuickActionCard(
            icon: Icons.mic_none_rounded,
            label: 'Record meeting',
            subtitle: 'Capture a conversation',
            onTap: () => context.push(RoutePaths.record),
          ),
          _QuickActionCard(
            icon: Icons.description_outlined,
            label: 'Import files',
            subtitle: 'Audio, video, or documents',
            onTap: () => context.push(RoutePaths.documents),
          ),
          _QuickActionCard(
            icon: Icons.forum_outlined,
            label: 'Chat',
            subtitle: 'Ask about your files, offline',
            onTap: () => context.push(RoutePaths.chat),
          ),
          // Phase 9.2 (Priority 3): the Productivity Toolkit gets its own
          // tonal treatment (tertiary container, not the primary container
          // every other Quick Action uses) - the brief was "make it feel
          // like a flagship feature," not "make its icon bigger," so the
          // change is a distinct accent color other apps use to mark a
          // module as its own destination (e.g. a colored app-drawer tile),
          // not a size change.
          _QuickActionCard(
            icon: Icons.auto_fix_high_rounded,
            label: 'Productivity tools',
            subtitle: 'Images, scans & PDFs',
            onTap: () => context.push(RoutePaths.studentToolkit),
            iconBackground: scheme.tertiaryContainer,
            iconForeground: scheme.onTertiaryContainer,
          ),
          // V3 Milestone 1 (Batch 5): the Resume Builder's minimum
          // required entry point from Home - a sixth tile would round out
          // the grid, but there is only one Career feature so far, so this
          // simply wraps onto its own row rather than being padded with a
          // placeholder tile.
          _QuickActionCard(
            icon: Icons.badge_outlined,
            label: 'Resumes',
            subtitle: 'Build from reusable blocks',
            onTap: () => context.push(RoutePaths.resumeList),
          ),
        ],
      ),
    ]);

    // R-11 P1 fix: R-6 added a prominent Offline Readiness card here to fix
    // discoverability, but real-device feedback found it dominated normal
    // Home content with configuration/status information instead of the
    // user's actual actions (record, resume, chat, documents). Offline
    // Readiness is reachable from Settings (`settings_screen.dart`, already
    // wired, unchanged) - the same "status/settings lives in Settings, Home
    // is for doing things" split every other part of this screen already
    // follows. No second entry point was added elsewhere; this one simply
    // isn't duplicated here anymore.

    // Phase 9.2 (Priority 4): AI model recommendations were only ever
    // reachable via Settings > AI Models > "Get recommended models" - a
    // real capability with zero visibility from the app's own front door.
    // Reuses the exact same `selectedProfessionProvider`/route the AI
    // Model Manager's own "Recommended for you" card already uses (see
    // `ai_model_manager_screen.dart`'s `_RecommendedCard`), just surfaced
    // here too - no new provider, no new screen. Self-declutters: once a
    // profession is chosen, this card stops rendering on its own.
    addSection(
      hasProfessionRecommendation
          ? const []
          : [_RecommendedModelsCard(onTap: () => context.push(RoutePaths.aiModelSetup))],
    );

    addSection(
      chatsAsync.maybeWhen(
        data: (sessions) => sessions.isEmpty
            ? const <Widget>[]
            : [
                const SectionHeading('Continue Working'),
                const SizedBox(height: 8),
                _ContinueChatCard(
                  title: sessions.first.title,
                  onTap: () => context.push(
                    RoutePaths.chat,
                    extra: ChatLaunchArgs(sessionId: sessions.first.id),
                  ),
                ),
              ],
        orElse: () => const <Widget>[],
      ),
    );

    addSection([
      meetingsAsync.when(
        loading: () => const SkeletonCardList(count: 2),
        error: (err, _) => InlineErrorText(err),
        data: (meetings) {
          if (meetings.isEmpty) {
            // No fixed height here: EmptyState's Column already sizes
            // itself to its content (`mainAxisSize: min`), and a hard cap
            // previously used here clipped/overflowed once the message
            // text wrapped to more lines on narrower phones.
            //
            // No action button here (unlike other empty states) - "Record
            // meeting" is already a Quick Action below, and the bottom-nav
            // shortcut is one tap away on every screen; a third "record"
            // button here was real, reported redundancy.
            // R-6: this section is titled "Recent Meetings" specifically,
            // so its own empty state stays meeting-scoped (not a broader
            // "workspace ready" message that would misrepresent what this
            // section is about) - but reworded away from "no meetings yet"
            // reading as a gap/problem, toward the same "ready, not empty"
            // framing this pass applied elsewhere, and pointing out the
            // other Quick Actions above rather than only describing what's
            // missing here.
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading('Recent Meetings'),
                SizedBox(height: 8),
                EmptyState(
                  icon: Icons.mic_none_rounded,
                  title: 'Ready when you are',
                  message: 'Record a meeting or import an existing '
                      'audio/video file above and it\'ll show up here — '
                      'everything stays on this device.',
                ),
              ],
            );
          }

          final recent = meetings.take(5).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading('Recent Meetings', onAction: () => context.go(RoutePaths.history)),
              const SizedBox(height: 8),
              for (final (index, meeting) in recent.indexed) ...[
                EntranceFade(
                  delay: Duration(milliseconds: 30 * index),
                  child: MeetingListTile(
                    meeting: meeting,
                    onTap: () => context.push(
                      RoutePaths.meetingDetailsPath(meeting.id!),
                    ),
                    onDelete: () async {
                      await ref.read(deleteMeetingUseCaseProvider)(meeting.id!);
                      ref.invalidate(meetingListProvider);
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    ]);

    addSection(
      documentsAsync.maybeWhen(
        data: (documents) => documents.isEmpty
            ? const <Widget>[]
            : [
                SectionHeading(
                  'Recent Documents',
                  onAction: () => context.push(RoutePaths.documents),
                ),
                const SizedBox(height: 8),
                for (final (index, document) in documents.take(3).toList().indexed) ...[
                  EntranceFade(
                    delay: Duration(milliseconds: 30 * index),
                    child: DocumentListTile(
                      document: document,
                      onTap: () => context.push(RoutePaths.documentDetailsPath(document.id!)),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
        orElse: () => const <Widget>[],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Refreshes every dynamic section on this page, not just
            // meetings (Phase 8B.2 consistency fix) - previously a pull-to-
            // refresh here silently left Recent Documents/Continue Working
            // showing stale data.
            ref.invalidate(meetingListProvider);
            ref.invalidate(documentListProvider);
            ref.invalidate(chatSessionListProvider);
            await ref.read(meetingListProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isEmpty
                              ? '${_greeting()}! \u{1F44B}'
                              : '${_greeting()}, $displayName! \u{1F44B}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'What would you like to do today?',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Edit display name',
                    child: InkWell(
                      onTap: () => _editDisplayName(context, ref, displayName),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 24,
                        backgroundColor: scheme.primaryContainer,
                        child: displayName.isEmpty
                            ? Icon(Icons.person_outline_rounded, color: scheme.onPrimaryContainer)
                            : Text(
                                displayName.substring(0, 1).toUpperCase(),
                                style: TextStyle(
                                  color: scheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              ...sections,
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueChatCard extends StatelessWidget {
  const _ContinueChatCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.forum_outlined, color: scheme.onTertiaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue chat', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// One quick action tile in the Home screen's 2x2 Quick Actions grid
/// (Phase 9.2: was a 3-across row of icon-on-top cards - switched to a
/// horizontal icon+text layout, matching [_ContinueChatCard]'s already
/// -established pattern, since a 2-column grid cell is wider than it is
/// tall and a stacked layout wasted that shape). [iconBackground]/
/// [iconForeground] let one tile (Productivity Toolkit) carry a distinct
/// accent from the rest without changing this widget's shape - "flagship"
/// via color, not a bigger icon.
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.iconBackground,
    this.iconForeground,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final Color? iconBackground;
  final Color? iconForeground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconBackground ?? scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconForeground ?? scheme.onPrimaryContainer, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home's surfaced version of the AI Model Manager's "Get recommended
/// models" prompt (Phase 9.2, Priority 4) - shown only until the user has
/// picked a profession-based recommendation (`selectedProfessionProvider`,
/// the same provider the AI Model Manager screen already reads), then
/// naturally stops appearing on its own.
class _RecommendedModelsCard extends StatelessWidget {
  const _RecommendedModelsCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.onSecondaryContainer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Get AI models recommended for you',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'One question - we\'ll pick the right setup for your work',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}
