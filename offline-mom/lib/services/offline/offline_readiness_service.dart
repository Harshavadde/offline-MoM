import '../../models/installed_model.dart';
import '../../repositories/installed_model_repository.dart';
import '../ai/model_lifecycle_manager.dart' show ModelKind;

/// One line of an [OfflineReadinessReport] - a single, independently
/// checkable fact about whether the app can function with no network
/// connection right now.
class OfflineReadinessCheck {
  const OfflineReadinessCheck({
    required this.label,
    required this.passed,
    required this.detail,
    this.required = true,
  });

  final String label;
  final bool passed;

  /// Explains *why* - either what's already true ("Qwen 1.5B is active
  /// and verified") or exactly what to do ("Download and activate a
  /// speech-to-text model in Model Manager") - never a bare pass/fail
  /// with no actionable context.
  final String detail;

  /// Whether this check counts toward [OfflineReadinessReport.isReady]/
  /// [OfflineReadinessReport.failingChecks] - `true` for every check that
  /// existed before P0-7. OCR (P0-7) is the first *optional* check: it's a
  /// real, disclosed fact about this device's offline capability, but not
  /// downloading the OCR model must never make the app "not offline
  /// ready" the way skipping the LLM/embedding/speech-to-text models does
  /// - most users never scan a document, mirroring the second (Enhanced)
  /// LLM tier's own "never required" precedent (`AiModelSpec.isDefault`).
  final bool required;
}

/// Whether this app can be used with no network connection right now -
/// reliability-overhaul pass, Phase 15/16 ("the app must work in
/// airplane/flight mode after required models are downloaded... the user
/// should know before entering airplane mode"). Built entirely from
/// already-real, already-persisted facts ([InstalledModelRepository]'s
/// `isActive` rows - the same source of truth the AI Model Manager itself
/// uses, never a fresh guess) plus a small set of static, source-audited
/// claims about this codebase's own network usage (see
/// [OfflineReadinessService.evaluate]'s doc comment for exactly what was
/// audited and how). This is a **capability check**, not a live
/// connectivity probe - it answers "are the offline-usable pieces in
/// place", not "is there a network connection to this device right now"
/// (a separate, pre-existing concern - `hasInternetConnection()`,
/// `lib/core/utils/connectivity_check.dart`).
class OfflineReadinessReport {
  const OfflineReadinessReport({required this.checks});

  final List<OfflineReadinessCheck> checks;

  bool get isReady => checks.where((c) => c.required).every((c) => c.passed);

  List<OfflineReadinessCheck> get failingChecks =>
      checks.where((c) => c.required && !c.passed).toList();
}

/// Builds an [OfflineReadinessReport] - see that class's own doc comment
/// for what this does and doesn't claim to check.
class OfflineReadinessService {
  const OfflineReadinessService();

  /// The three model kinds this app's core offline features actually
  /// depend on: an LLM (summaries/chat/resume tailoring), an embedding
  /// model (semantic search/JD matching), and a speech-to-text model
  /// (transcription). OCR/Vision/Translation are not yet real features
  /// (`ModelDownloadController.start` itself rejects
  /// [ModelKind.vision]/[ModelKind.translation], "not available yet") and
  /// are deliberately excluded from readiness entirely - a report that
  /// demanded models for features that don't exist yet would never be
  /// satisfiable and would misrepresent what's actually required.
  /// [ModelKind.ocr] became a real feature in P0-7 but is intentionally
  /// *not* here - see [_optionalKinds].
  static const _requiredKinds = [ModelKind.llm, ModelKind.embedding, ModelKind.speechToText];

  /// Real, checkable, but never blocking [OfflineReadinessReport.isReady] -
  /// see [OfflineReadinessCheck.required]'s own doc comment for why OCR
  /// specifically belongs here rather than in [_requiredKinds].
  static const _optionalKinds = [ModelKind.ocr];

  String _labelFor(ModelKind kind) => switch (kind) {
        ModelKind.llm => 'AI language model',
        ModelKind.embedding => 'Embedding model (semantic search)',
        ModelKind.speechToText => 'Speech-to-text model',
        ModelKind.ocr => 'OCR model',
        ModelKind.vision => 'Vision model',
        ModelKind.translation => 'Translation model',
      };

  Future<OfflineReadinessReport> evaluate(InstalledModelRepository repository) async {
    final checks = <OfflineReadinessCheck>[];

    for (final kind in _requiredKinds) {
      final InstalledModel? active = await repository.getActiveForKind(kind);
      final label = _labelFor(kind);
      if (active == null) {
        checks.add(
          OfflineReadinessCheck(
            label: label,
            passed: false,
            detail: 'Not installed. Download and activate one in Model Manager.',
          ),
        );
        continue;
      }
      checks.add(
        OfflineReadinessCheck(
          label: label,
          passed: true,
          detail: '${active.modelId} is installed and active.',
        ),
      );
    }

    for (final kind in _optionalKinds) {
      final InstalledModel? active = await repository.getActiveForKind(kind);
      final label = _labelFor(kind);
      checks.add(
        OfflineReadinessCheck(
          label: label,
          passed: active != null,
          required: false,
          detail: active != null
              ? '${active.modelId} is installed and active.'
              : 'Not installed - only needed if you use Scan/Images to PDF\'s '
                  '"Searchable PDF" option or View PDF\'s "Run OCR." Every '
                  'other feature works without it.',
        ),
      );
    }

    // The following are not per-device runtime checks (there is nothing
    // to probe - a Sqflite database file and the bundled native
    // libraries are either present, because the app is running at all,
    // or the app would already have failed to start) - they are static
    // facts about this codebase's own architecture, directly backed by
    // the Phase 16 network audit ([docs/v3/implementation/03-decisions.md]):
    // no `http`/`dio` package dependency, no Firebase/analytics SDK
    // anywhere in `pubspec.yaml`, and the only real network-capable code
    // in `lib/` is `HttpModelDownloadService`/the `llamadart` package's
    // own downloader - both used exclusively for one-time model
    // downloads, never called from any transcription/summarization/
    // resume/search/OCR code path. P0-7's OCR pipeline
    // (`flutter_tesseract_ocr`, `SearchablePdfBuilderService`) was
    // re-audited the same way for this release: zero network-capable
    // imports in any new production file - the OCR *model* is fetched
    // over HTTP once via the same `ModelDownloadService`, but recognizing
    // text and building the searchable PDF never touches the network.
    checks.add(
      const OfflineReadinessCheck(
        label: 'Local database available',
        passed: true,
        detail: 'On-device SQLite - no network round-trip for any read or write.',
      ),
    );
    checks.add(
      const OfflineReadinessCheck(
        label: 'AI inference runs entirely on-device',
        passed: true,
        detail: 'llama.cpp (LLM/embedding) and whisper.cpp (speech-to-text) run locally - '
            'no cloud inference API is used.',
      ),
    );
    checks.add(
      const OfflineReadinessCheck(
        label: 'No network required for inference, search, OCR, or PDF generation',
        passed: true,
        detail: 'Network is used only for one-time model downloads.',
      ),
    );

    return OfflineReadinessReport(checks: checks);
  }
}
