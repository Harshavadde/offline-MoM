import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'local_crash_logger.dart';

/// A minimal, dependency-free fallback UI shown when startup fails before
/// [OfflineMomApp] (`main.dart`) itself can be built - deliberately a bare
/// [MaterialApp] with no theme/database/Riverpod dependency of its own, so
/// this screen can never itself become the thing that fails to render. See
/// `main.dart`'s startup try/catch for where this is used.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.red, brightness: Brightness.dark),
      home: StartupFailureScreen(error: error, stackTrace: stackTrace),
    );
  }
}

/// The screen itself, split out from [StartupFailureApp] so it's directly
/// widget-testable without needing to pump a whole second [MaterialApp].
class StartupFailureScreen extends StatelessWidget {
  const StartupFailureScreen({super.key, required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  String get _fullText => 'Startup failed\n\nException:\n$error\n\nStack trace:\n$stackTrace';

  Future<void> _copyLog(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _fullText));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Crash log copied to clipboard.')),
    );
  }

  Future<void> _exportLog(BuildContext context) async {
    final path = LocalCrashLogger.logFilePath;
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No crash log file is available to export.')),
      );
      return;
    }
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], subject: 'OfflineMoMAI crash log'),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the share sheet for the crash log.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Startup failed')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The app could not start.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                'This has been saved to a local crash log on this device - '
                'nothing was sent anywhere. Use the buttons below to share it.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _fullText,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _exportLog(context),
                      child: const Text('Export crash log'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _copyLog(context),
                      child: const Text('Copy crash log'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
