import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/ask_providers.dart';

/// "Ask my meetings": a plain-English question box that searches every
/// meeting stored on this device and has the on-device LLM answer using
/// only what it finds there - entirely offline, no cloud RAG service, no
/// vector database calling home. This is OfflineMoMAI's standout feature:
/// most meeting assistants that offer natural-language Q&A over your
/// meeting history do it by shipping your data to a server; this does the
/// same thing without your meetings ever leaving the phone.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _controller = TextEditingController();

  static const _suggestions = [
    'What did we decide last time?',
    'What action items are still open?',
    'What has come up most often across my meetings?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _controller.text;
    if (question.trim().isEmpty) return;
    ref.read(askControllerProvider.notifier).ask(question);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(askControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ask your meetings')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: switch (state) {
                  AskIdle() => Padding(
                      padding: const EdgeInsets.only(top: 24),
                      child: Column(
                        children: [
                          const EmptyState(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Ask anything about your meetings',
                            message: 'On-device AI reads across everything '
                                "you've recorded or imported and answers "
                                'using only that - nothing is sent '
                                'anywhere.',
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final suggestion in _suggestions)
                                ActionChip(
                                  label: Text(suggestion),
                                  onPressed: () {
                                    _controller.text = suggestion;
                                    _submit();
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  AskLoading(:final question) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuestionBubble(question: question),
                        const SizedBox(height: 16),
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Thinking, entirely on-device…'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  AskAnswered(:final question, :final answer) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuestionBubble(question: question),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(answer.answer),
                        ),
                        if (answer.sourceMeetings.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('From', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final meeting in answer.sourceMeetings)
                                ActionChip(
                                  avatar: const Icon(Icons.description_outlined, size: 16),
                                  label: Text(meeting.title),
                                  onPressed: () => context.push(
                                    RoutePaths.meetingDetailsPath(meeting.id!),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  AskFailed(:final question, :final message) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _QuestionBubble(question: question),
                        const SizedBox(height: 16),
                        EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: "Couldn't answer that",
                          message: message,
                        ),
                      ],
                    ),
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          hintText: 'Ask a question…',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: state is AskLoading ? null : _submit,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(question, style: TextStyle(color: scheme.onPrimaryContainer)),
      ),
    );
  }
}
