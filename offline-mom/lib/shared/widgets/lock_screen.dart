import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';

/// Shown instead of the app's content whenever [appLockControllerProvider]
/// is locked - on cold start (if the setting is on) and whenever the app
/// is resumed from the background. Unlocking uses the device's own PIN/
/// pattern/password/biometric prompt, never an app-specific credential.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  bool _isAuthenticating = false;
  bool _lastAttemptFailed = false;

  @override
  void initState() {
    super.initState();
    // Prompt immediately rather than waiting for a tap, so resuming the app
    // goes straight into the device's own auth UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _lastAttemptFailed = false;
    });

    final success =
        await ref.read(appLockControllerProvider.notifier).tryUnlock();

    if (!mounted) return;
    setState(() {
      _isAuthenticating = false;
      _lastAttemptFailed = !success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 36, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 20),
              Text(
                AppConstants.appName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _lastAttemptFailed
                    ? 'Authentication failed - try again.'
                    : 'Unlock to see your meetings.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isAuthenticating ? null : _unlock,
                icon: _isAuthenticating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
