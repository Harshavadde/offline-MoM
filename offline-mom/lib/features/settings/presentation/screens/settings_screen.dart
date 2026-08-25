import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../providers/app_providers.dart';
import '../../../../shared/widgets/tinted_icon.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _onAppLockChanged(
    BuildContext context,
    WidgetRef ref,
    bool enable,
  ) async {
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final lockController = ref.read(appLockControllerProvider.notifier);

    if (!enable) {
      await settingsController.setAppLockEnabled(false);
      lockController.forceUnlock();
      return;
    }

    final lockService = ref.read(appLockServiceProvider);
    if (!await lockService.isSupported()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set up a screen lock (PIN, pattern, password, or fingerprint) '
            'on your device first.',
          ),
        ),
      );
      return;
    }

    // Confirm the device's auth actually works before turning this on -
    // otherwise a misconfigured setup could lock the user out with no way
    // back in.
    final confirmed =
        await lockService.authenticate('Confirm to enable app lock');
    if (!confirmed) return;

    await settingsController.setAppLockEnabled(true);
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'Match system',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Phase 8B.4, Priority 1/9: every other section on this screen has
          // a heading above its card - this was the one exception, reading
          // as an unfinished/inconsistent first impression on a screen
          // that's otherwise cleanly grouped.
          Text('General', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const TintedIcon(Icons.palette_outlined),
                  title: const Text('Appearance'),
                  subtitle: Text(_themeModeLabel(settings.themeMode)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.appearance),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('AI & Data', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const TintedIcon(Icons.psychology_outlined),
                  title: const Text('AI Models'),
                  subtitle: const Text('Voice transcription and AI writing tools'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.aiModels),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.flight_rounded),
                  title: const Text('Use Offline'),
                  subtitle: const Text('Check before turning on airplane mode'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.offlineReadiness),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.mic_outlined),
                  title: const Text('Recording'),
                  subtitle: const Text('Audio quality'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.recordingPreferences),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.translate_rounded),
                  title: const Text('Language'),
                  subtitle: const Text('Transcription language'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.language),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.folder_outlined),
                  title: const Text('Storage'),
                  subtitle: const Text('See what\'s using space on this device'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.storage),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.backup_outlined),
                  title: const Text('Export data'),
                  subtitle: const Text('Save a text-data archive; restore is unavailable'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.backup),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Security', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              secondary: const TintedIcon(Icons.lock_outline_rounded),
              title: const Text('App lock'),
              subtitle: const Text(
                'Require your device PIN/pattern/password or fingerprint '
                'to open the app.',
              ),
              value: settings.isAppLockEnabled,
              onChanged: (enable) => _onAppLockChanged(context, ref, enable),
            ),
          ),
          const SizedBox(height: 24),
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const TintedIcon(Icons.info_outline_rounded),
                  title: const Text('About OfflineMoMAI'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.about),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.privacy),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.help_outline_rounded),
                  title: const Text('Help'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => context.push(RoutePaths.help),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
