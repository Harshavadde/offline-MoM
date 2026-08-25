import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/route_paths.dart';
import '../providers/recording_providers.dart';

/// Entry point for starting a new live recording: pick a title, then start.
/// The actual live controls (timer, pause/resume/stop) live on
/// [RecordingScreen] once a session is underway.
class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  late final TextEditingController _titleController;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: 'Meeting ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _isStarting) return;

    setState(() => _isStarting = true);
    await ref.read(recordingControllerProvider.notifier).startRecording(title);
    if (!mounted) return;
    setState(() => _isStarting = false);

    final state = ref.read(recordingControllerProvider);
    if (state is RecordingFailed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(state.message)),
      );
      return;
    }
    if (state is RecordingInProgress) {
      context.push(RoutePaths.recording);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record meeting')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Meeting title',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'e.g. Sprint planning'),
            ),
            const SizedBox(height: 32),
            Icon(
              Icons.mic_none_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _isStarting ? null : _startRecording,
              icon: _isStarting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fiber_manual_record_rounded),
              label: const Text('Start recording'),
            ),
          ],
        ),
      ),
    );
  }
}
