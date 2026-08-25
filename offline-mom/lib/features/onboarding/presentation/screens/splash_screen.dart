import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/hero_icon.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      final hasCompletedOnboarding =
          ref.read(settingsControllerProvider).hasCompletedOnboarding;
      context.go(hasCompletedOnboarding ? RoutePaths.home : RoutePaths.onboardingWhy);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phase 9.2: was a flat `primaryContainer` fill - the same hero
            // treatment (gradient + glow) the onboarding intro screen
            // already uses one step later, now applied to the very first
            // frame the app ever shows instead of only the second one, so
            // the "premium" first impression starts immediately rather
            // than one screen later.
            //
            // Phase 8B.5: `Icons.workspaces_outline` matches the icon
            // already used elsewhere in the app to mean "the whole
            // workspace" (the chat scope indicator's Workspace chip) - a
            // microphone here, on the very first screen a user ever sees,
            // said "meeting recorder" more than this app has meant since
            // Phase 8B.1.
            const HeroIcon(icon: Icons.workspaces_outline, size: 88, glow: true),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              AppConstants.appTagline,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
