import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/widgets/tinted_icon.dart';
import 'terms_screen.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  // Phase 9.2 (Product Identity): matches the icon used
                  // everywhere else in the app to mean "the whole
                  // workspace" since Phase 8B.5 (splash, onboarding intro)
                  // - a microphone here was the one remaining screen still
                  // implying "meeting recorder" first.
                  child: Icon(Icons.workspaces_outline, size: 36, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 12),
                Text(AppConstants.appName, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Version ${AppConstants.appVersion}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                Text(AppConstants.appTagline, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Phase 9.2 (Product Identity): previously described only the
          // meeting pipeline (record/transcribe/summarize) - the app's
          // actual scope since V2 also includes documents, an AI chat
          // that answers from your own content, and an offline
          // Productivity Toolkit, none of which this screen mentioned.
          const Text(
            '${AppConstants.appName} is a private, fully offline AI '
            'workspace. Record or import meetings and documents, and '
            'they\'re transcribed, summarized, and made searchable '
            'entirely on-device. Chat with your own content, or use the '
            'built-in Productivity Toolkit to scan, compress, and organize '
            'files - all with an on-device AI model, and nothing ever '
            'leaves this phone.',
          ),
          const SizedBox(height: 12),
          const Text(
            'All processing and storage happens entirely on your device - '
            'no cloud, no accounts, no analytics.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const TintedIcon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const TintedIcon(Icons.badge_outlined),
                  title: const Text('Open-source licenses'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppConstants.appName,
                    applicationVersion: AppConstants.appVersion,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
