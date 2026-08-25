import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../models/ai_model_spec.dart';
import '../../../../models/profession_profile.dart';
import '../../../../services/ai/model_catalog.dart';
import '../../../../services/ai/profession_recommendations.dart';
import '../../../../shared/utils/format_utils.dart';
import '../providers/model_download_providers.dart';
import '../providers/profession_setup_providers.dart';

/// One-tap Recommended Setup (Phase 6A objectives 11-13): pick a
/// profession, see exactly what it recommends and why, then download and
/// activate all three in one tap.
class ProfessionSetupScreen extends ConsumerStatefulWidget {
  const ProfessionSetupScreen({super.key});

  @override
  ConsumerState<ProfessionSetupScreen> createState() => _ProfessionSetupScreenState();
}

class _ProfessionSetupScreenState extends ConsumerState<ProfessionSetupScreen> {
  ProfessionProfile? _selected;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(selectedProfessionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final setupState = ref.watch(professionSetupControllerProvider);
    final selected = _selected;
    final recommendation = selected == null ? null : ProfessionRecommendations.forProfession(selected);

    return Scaffold(
      appBar: AppBar(title: const Text('Recommended for you')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('What best describes you?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final profession in ProfessionProfile.values)
                ChoiceChip(
                  label: Text(profession.label),
                  selected: selected == profession,
                  onSelected: (_) => setState(() => _selected = profession),
                ),
            ],
          ),
          if (recommendation != null) ...[
            const SizedBox(height: 24),
            _RecommendationCard(recommendation: recommendation),
            const SizedBox(height: 24),
            if (setupState.isLoading)
              _SetupProgress(recommendation: recommendation)
            else ...[
              // V2.2 Production Hardening, Priority 4 (real-device QA
              // finding): explains *why* this needs a connection before
              // the user taps the button, not only after something fails.
              Text(
                'Needs an internet connection once, to download these '
                'models - everything runs fully offline after that.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(professionSetupControllerProvider.notifier).applyRecommendedSetup(selected!),
                child: const Text('Set up these models'),
              ),
            ],
            if (setupState.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  // V2.2 Production Hardening, Priority 6: `setupState
                  // .error` is a `ModelSetupException`, whose `toString()`
                  // is already plain, user-appropriate text (see its own
                  // doc comment) - not re-wrapped through
                  // `friendlyErrorMessage` here, which would only degrade
                  // it to a generic fallback (that function recognizes
                  // *raw* exception patterns, not already-friendly text).
                  'Could not finish setting up your models: ${setupState.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (setupState.hasValue && !setupState.isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Your recommended models are set up.'),
              ),
          ],
        ],
      ),
    );
  }
}

/// Replaces a bare spinner with real, per-model feedback while
/// [ProfessionSetupController.applyRecommendedSetup] is running (V2.2
/// Production Hardening, Priority 4 - real-device QA finding: "after
/// selecting a recommended model and pressing Setup, there is almost no
/// feedback"). Reads [modelDownloadControllerProvider]'s existing
/// per-model state map directly - that data was always there, this screen
/// just never watched it, unlike `model_setup_screen.dart`'s onboarding
/// download view, which already showed this same kind of detail for the
/// LLM/Whisper downloads it drives. No new download engine, no new
/// states: every label below maps directly from [ModelDownloadState]'s
/// existing variants.
class _SetupProgress extends ConsumerWidget {
  const _SetupProgress({required this.recommendation});

  final ProfessionRecommendation recommendation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadStates = ref.watch(modelDownloadControllerProvider);
    final specs = [
      ModelCatalog.byId(recommendation.recommendedLlmModelId),
      ModelCatalog.byId(recommendation.recommendedEmbeddingModelId),
      ModelCatalog.byId(recommendation.recommendedWhisperModelId),
    ].whereType<AiModelSpec>().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final spec in specs) ...[
          _ModelSetupRow(spec: spec, state: downloadStates[spec.id] ?? const ModelDownloadIdle()),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          onPressed: () => ref.read(professionSetupControllerProvider.notifier).cancel(),
          icon: const Icon(Icons.close_rounded),
          label: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ModelSetupRow extends StatelessWidget {
  const _ModelSetupRow({required this.spec, required this.state});

  final AiModelSpec spec;
  final ModelDownloadState state;

  /// Every label here maps directly from an existing [ModelDownloadState]
  /// variant - no new download-lifecycle states were added for this.
  String _statusLabel() => switch (state) {
        ModelDownloadIdle() => 'Preparing…',
        ModelDownloadInProgress(:final fraction) =>
          fraction == null ? 'Downloading…' : 'Downloading… ${(fraction * 100).round()}%',
        ModelDownloadVerifying() => 'Verifying…',
        ModelDownloadPaused() => 'Paused',
        // Already user-appropriate text by construction - see
        // ModelDownloadController's two failure paths (friendlyErrorMessage
        // for LLM/embedding, ModelDownloadException's own hand-authored
        // wording for Whisper).
        ModelDownloadFailed(:final message) => message,
        ModelDownloadDone() => 'Installed',
      };

  double? get _fraction => switch (state) {
        ModelDownloadInProgress(:final fraction) => fraction,
        ModelDownloadVerifying() => null,
        ModelDownloadDone() => 1.0,
        _ => 0.0,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFailed = state is ModelDownloadFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                '${spec.displayName} · ${formatFileSize(spec.sizeBytesApprox)}',
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _statusLabel(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isFailed ? scheme.error : scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: isFailed ? 0 : _fraction),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.recommendation});

  final ProfessionRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('We recommend:', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text('• Standard Chat Model'),
            const Text('• Search Tool'),
            Text(
              '• Voice transcription: '
              '${ModelCatalog.byId(recommendation.recommendedWhisperModelId)?.displayName ?? recommendation.recommendedWhisperModelId}',
            ),
            const SizedBox(height: 12),
            Text(recommendation.rationale, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
