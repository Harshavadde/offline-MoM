import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/friendly_error.dart';
import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/resume_writing_heuristics.dart';
import '../../../../../services/resume/suggestion_fabrication_guard.dart';
import '../../../../../shared/widgets/ai_disclaimer.dart';

enum _TierTwoStatus { idle, running, succeeded, failed }

/// A bullets/details text field with both tiers of writing assistance
/// (docs/v3/01-prd.md §12, FR3-17):
///
/// - **Tier 1** (always on, no model): after the user pauses typing,
///   [ResumeWritingHeuristics] re-analyzes every non-empty line and shows
///   any weak-verb/no-measurable-detail hints as plain advisory text -
///   never auto-inserted into the field.
/// - **Tier 2** (explicit, on demand): once the same pause has elapsed,
///   an "Improve with AI" button becomes enabled. Tapping it runs
///   `GenerateBulletRewriteUseCase` (bounded, JD-agnostic, reuses the
///   Milestone 3 prompt builder/engine/queue) and shows the result as an
///   inline before/after preview with Accept/Reject actions - accepting
///   only replaces this field's own text, exactly as if the user had
///   retyped it; nothing is written to any block/database row until the
///   surrounding screen's own pre-existing "Save" action runs. See
///   `GenerateBulletRewriteUseCase`'s own doc comment for why this
///   deliberately does not go through the Milestone 3 `SuggestedEdit`/
///   accept pipeline.
///
/// Both tiers are debounced to the same pause (never re-computed on every
/// keystroke, per FR3-17's own wording) via [debounceDuration].
class BulletSuggestionField extends ConsumerStatefulWidget {
  const BulletSuggestionField({
    super.key,
    required this.controller,
    required this.entryContextLabel,
    this.labelText = 'Bullets',
    this.helperText = 'One per line',
  });

  final TextEditingController controller;

  /// A short, human-readable label for whichever entry this field belongs
  /// to (e.g. "Backend Engineer at Acme Corp") - passed straight through
  /// to the Tier-2 prompt as grounding context, the same role
  /// `entryContextLabel` plays in Milestone 3's own prompt builder.
  final String entryContextLabel;

  final String labelText;
  final String? helperText;

  /// How long the field must sit unchanged before Tier 1 hints refresh
  /// and the Tier 2 trigger becomes enabled - exposed as a constant so
  /// `bullet_suggestion_field_test.dart` can assert on real elapsed time
  /// without hard-coding a duplicate magic number.
  static const debounceDuration = Duration(milliseconds: 600);

  @override
  ConsumerState<BulletSuggestionField> createState() => _BulletSuggestionFieldState();
}

class _BulletSuggestionFieldState extends ConsumerState<BulletSuggestionField> {
  static const _heuristics = ResumeWritingHeuristics();
  static const _guard = SuggestionFabricationGuard();

  Timer? _debounceTimer;
  List<WritingHint> _hints = const [];
  bool _settled = false;

  _TierTwoStatus _status = _TierTwoStatus.idle;
  String? _suggestion;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _recomputeHints();
    _settled = true;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    // Any further edit invalidates a pending/shown Tier-2 suggestion -
    // it was generated from text that no longer matches the field.
    if (_status != _TierTwoStatus.idle) {
      setState(() {
        _status = _TierTwoStatus.idle;
        _suggestion = null;
        _error = null;
      });
    }
    if (_settled) setState(() => _settled = false);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(BulletSuggestionField.debounceDuration, () {
      if (!mounted) return;
      setState(() {
        _settled = true;
        _recomputeHints();
      });
    });
  }

  void _recomputeHints() {
    final seenKinds = <WritingHintKind>{};
    final hints = <WritingHint>[];
    for (final line in widget.controller.text.split('\n')) {
      for (final hint in _heuristics.analyze(line)) {
        if (seenKinds.add(hint.kind)) hints.add(hint);
      }
    }
    _hints = hints;
  }

  Future<void> _triggerTierTwo() async {
    setState(() {
      _status = _TierTwoStatus.running;
      _error = null;
    });
    try {
      final result = await ref.read(generateBulletRewriteUseCaseProvider)(
        entryContextLabel: widget.entryContextLabel,
        originalText: widget.controller.text,
      );
      if (!mounted) return;
      if (result == null) {
        setState(() {
          _status = _TierTwoStatus.failed;
          _error = "Couldn't generate a suggestion for this text right now.";
        });
      } else {
        setState(() {
          _status = _TierTwoStatus.succeeded;
          _suggestion = result;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _TierTwoStatus.failed;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  void _acceptSuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    widget.controller.text = suggestion;
    setState(() {
      _status = _TierTwoStatus.idle;
      _suggestion = null;
    });
  }

  void _rejectSuggestion() {
    setState(() {
      _status = _TierTwoStatus.idle;
      _suggestion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRunning = _status == _TierTwoStatus.running;
    final canTriggerTierTwo = _settled && !isRunning && widget.controller.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: 6,
          minLines: 3,
          decoration: InputDecoration(labelText: widget.labelText, helperText: widget.helperText),
        ),
        const SizedBox(height: 6),
        if (_hints.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final hint in _hints)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hint.message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canTriggerTierTwo ? _triggerTierTwo : null,
            icon: isRunning
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_outlined, size: 18),
            label: Text(isRunning ? 'Improving…' : 'Improve with AI'),
          ),
        ),
        if (_status == _TierTwoStatus.failed && _error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
        if (_status == _TierTwoStatus.succeeded && _suggestion != null) _buildPreview(context, scheme),
      ],
    );
  }

  Widget _buildPreview(BuildContext context, ColorScheme scheme) {
    final check = _guard.check(originalText: widget.controller.text, suggestedText: _suggestion!);

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: 'Suggested rewrite',
            child: Text(
              'Suggested',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.primary),
            ),
          ),
          const SizedBox(height: 4),
          Text(_suggestion!),
          const SizedBox(height: 6),
          const AiDisclaimer.resume(),
          if (!check.isSafe) ...[
            const SizedBox(height: 8),
            Text(
              'Review carefully - mentions details not found in your original text: '
              '${[...check.newProperNouns, ...check.newNumbers].join(', ')}.',
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _rejectSuggestion, child: const Text('Reject')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _acceptSuggestion, child: const Text('Accept')),
            ],
          ),
        ],
      ),
    );
  }
}
