import '../services/ai/model_lifecycle_manager.dart' show ModelKind;

/// Coarse, user-facing speed expectation for a model - deliberately not a
/// number (tokens/sec varies wildly by device) so the UI can show something
/// honest without benchmarking hardware it has no access to.
enum ModelSpeedTier { fast, moderate, slow }

/// Coarse device-capability bucket a model is realistically comfortable on -
/// same "honest bucket, not a false-precision number" reasoning as
/// [ModelSpeedTier].
enum RecommendedDeviceTier {
  /// Any modern phone (roughly 4GB+ RAM) - the default assumption most of
  /// this app's models are built around, matching the Whisper `small` /
  /// Qwen2.5-1.5B choices already shipped in V1/Phase 0.
  anyModernPhone,

  /// A higher-RAM phone/tablet (roughly 6GB+) - flagged explicitly rather
  /// than silently letting a low-RAM device attempt a download that then
  /// fails or thrashes at inference time.
  highRamDevice,
}

/// A single downloadable AI model's static, catalog-level description -
/// everything about it that's true regardless of whether this device has
/// downloaded it. Deliberately a plain, hand-authored data class (mirrors
/// [PdfCompressPresetSpecs]'s "static specs, not a database table" pattern,
/// `lib/services/toolkit/pdf_compression_service.dart` - Phase 5B) rather
/// than something fetched from a remote catalog server: there is no server,
/// by design (docs/v2/17-privacy.md), and every entry here is a curated,
/// already-integration-tested model, not an open marketplace.
///
/// See ADR-036 (docs/v2/implementation/03-decisions.md) for why the catalog
/// deliberately contains exactly one real Chat LLM tier and one real
/// Embedding tier today (the same models Phase 0/Phase 1B already shipped
/// and tested) rather than multiple invented tiers with unverified
/// download sources - multi-tier LLM/embedding selection is Approved
/// Future Architecture (ADR-035), not fabricated here. [ModelKind.ocr],
/// [ModelKind.vision], and [ModelKind.translation] intentionally have zero
/// [AiModelSpec] entries in [ModelCatalog] today - see [ModelKind]'s own
/// doc comment.
class AiModelSpec {
  const AiModelSpec({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.description,
    required this.downloadSource,
    required this.sizeBytesApprox,
    this.quantization,
    required this.ramRequirementMb,
    required this.speedTier,
    required this.recommendedDeviceTier,
    required this.capabilities,
    required this.license,
    required this.version,
    this.isDefault = false,
  });

  /// Stable catalog identifier, e.g. `'llm-qwen2.5-1.5b-q4km'` or
  /// `'whisper-small'` - persisted in [InstalledModel.modelId] and
  /// `AppSettings.activeLlmModelId`/`.activeEmbeddingModelId`/
  /// `.whisperModelName`, so this must never change once shipped (renaming
  /// the id would orphan an already-installed model's on-disk record).
  final String id;

  final ModelKind kind;
  final String displayName;
  final String description;

  /// The exact source string the download layer resolves - an `hf://...`
  /// URI (`ModelSource.parse`, for the two `llamadart`-backed kinds) or an
  /// `https://...` URL (for Whisper, via [ModelDownloadService]). Never
  /// shown directly to the user - see [AiModelManagerScreen]'s copy, which
  /// treats the exact model identity as an internal implementation detail
  /// the same way `LlamaDartLlmEngine.modelDisplayName` already does.
  final String downloadSource;

  /// Approximate download/on-disk size, in bytes - "approximate" because
  /// the true byte count is only known once the download's HTTP response
  /// headers are read; this value is for upfront storage-planning UI only
  /// (Storage Usage screen's "Estimated Download Size"), never used to
  /// validate a completed download (see [InstalledModel.sizeBytes] for the
  /// actual measured size).
  final int sizeBytesApprox;

  /// e.g. `'Q4_K_M'`, `'Q8_0'` - null for Whisper's `ggml` models, which
  /// aren't published with a comparable quantization label.
  final String? quantization;

  /// Rough resident-memory footprint once loaded - a coarse planning
  /// figure (roughly file size plus context-buffer overhead), not a
  /// measured peak from real device profiling (no device is available in
  /// this implementation environment - same standing disclosure as
  /// R-04/R-18/R-19/R-31/R-32).
  final int ramRequirementMb;

  final ModelSpeedTier speedTier;
  final RecommendedDeviceTier recommendedDeviceTier;

  /// Short capability tags shown on the Model Details screen, e.g.
  /// `['Chat', 'Summarization']`, `['Semantic search']`,
  /// `['Speech-to-text', 'Translation']`.
  final List<String> capabilities;

  /// License the model weights are distributed under - shown verbatim so a
  /// user (or an enterprise procurement reviewer) can judge redistribution/
  /// commercial-use terms themselves, the same transparency this project
  /// already applies to its own OSS dependencies (ADR-016).
  final String license;

  /// Publisher-assigned model version/tag string, e.g. `'2.5'`, `'v3'` -
  /// distinct from [AiModelManagerScreen]'s own unrelated app version.
  final String version;

  /// Whether this is the catalog's default pick for its [kind] when a user
  /// has expressed no other preference - exactly one entry per [kind]
  /// should have this set to `true` (validated in
  /// `test/services/ai/model_catalog_test.dart`).
  final bool isDefault;
}
