import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/hero_icon.dart';

/// First-run screen: asks for a name to personalize the Home greeting.
/// Purely cosmetic (see [AppSettings.displayName]'s doc comment) and
/// skippable - unlike the model download step that follows, there's no
/// reason to block anyone who'd rather not give a name.
class WelcomeNameScreen extends ConsumerStatefulWidget {
  const WelcomeNameScreen({super.key});

  @override
  ConsumerState<WelcomeNameScreen> createState() => _WelcomeNameScreenState();
}

class _WelcomeNameScreenState extends ConsumerState<WelcomeNameScreen> {
  final _controller = TextEditingController();
  bool _isContinuing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    setState(() => _isContinuing = true);
    final name = _controller.text.trim();
    if (name.isNotEmpty) {
      await ref.read(settingsControllerProvider.notifier).setDisplayName(name);
    }
    if (!mounted) return;
    context.go(RoutePaths.onboardingSetup);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: HeroIcon(icon: Icons.waving_hand_rounded, iconSize: 34),
              ),
              const SizedBox(height: 24),
              Text(
                'What should we call you?',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'We\'ll use this for a friendly hello on Home — nothing else.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_isContinuing,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continue(),
                decoration: const InputDecoration(labelText: 'Your name'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isContinuing ? null : _continue,
                child: _isContinuing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _isContinuing ? null : _continue,
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
