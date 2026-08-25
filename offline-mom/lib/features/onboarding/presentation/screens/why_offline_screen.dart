import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../shared/widgets/hero_icon.dart';

/// First-run intro: what this app is and why it's different, shown once
/// right after install/launch - before asking for a name or starting the
/// model download. Previously this content (the "Why OfflineMoMAI?" four
/// feature highlights) only lived at the bottom of Home, which a new user
/// only sees after already recording/importing something; a first
/// impression is the more natural place for it.
class WhyOfflineScreen extends StatelessWidget {
  const WhyOfflineScreen({super.key});

  // Phase 9.2 (Product Identity): previously two of these four rows were
  // trust badges with no mention of what the app actually *does*
  // (Multi-Language, Made in India) - a first-time user could read every
  // line on this screen and still not know it handles documents or chat,
  // not just meetings. Reworked to lead with the three content pillars
  // (workspace, ask-anything, toolkit) plus the one non-negotiable trust
  // anchor (privacy/offline) everything else on this screen already
  // assumes. "Multi-Language"/"Made in India" aren't claims this app makes
  // anywhere else as a headline feature (the language picker lives in
  // Settings) - dropped here rather than crowding out what a new user
  // actually needs in the first 10 seconds.
  static const _items = [
    (
      icon: Icons.workspaces_outline,
      title: 'One Private AI Workspace',
      subtitle: 'Meetings, documents, and chat — all in one place',
    ),
    (
      icon: Icons.forum_outlined,
      title: 'Ask Anything',
      subtitle: 'Chat with your own meetings & files, on-device',
    ),
    (
      icon: Icons.auto_fix_high_rounded,
      title: 'Everyday Toolkit',
      subtitle: 'Scan, compress, and organize files too',
    ),
    (
      icon: Icons.wifi_off_rounded,
      title: '100% Offline & Private',
      subtitle: 'Your data never leaves this device',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // Phase 8B.5: was a microphone - this screen introduces the
              // whole app, not just recording, so it uses the same "whole
              // workspace" icon the splash screen and the chat scope
              // indicator already use for that meaning.
              const HeroIcon(icon: Icons.workspaces_outline, size: 88, glow: true),
              const SizedBox(height: 24),
              Text(
                'Welcome to ${AppConstants.appName}',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              // Phase 9.2: a one-line, concrete value prop ("what is this")
              // instead of the vaguer "Why OfflineMoMAI?" prompt - the goal
              // is that a first-time user understands the product from this
              // sentence alone, before reading a single feature row below.
              Text(
                'Your private, fully offline AI workspace for meetings, '
                'documents, and everyday files.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              for (final item in _items) ...[
                _FeatureRow(icon: item.icon, title: item.title, subtitle: item.subtitle),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'One-time setup needs an internet connection to '
                        'download the AI models (next step) - after that, '
                        'everything runs fully offline.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go(RoutePaths.onboardingName),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Get Started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: scheme.onPrimaryContainer, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
