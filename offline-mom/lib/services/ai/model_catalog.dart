import '../../models/ai_model_spec.dart';
import 'model_lifecycle_manager.dart' show ModelKind;

/// The curated, hand-authored catalog of every downloadable AI model this
/// app knows about - see [AiModelSpec]'s doc comment and ADR-036
/// (docs/v2/implementation/03-decisions.md) for why this is static Dart
/// data (mirrors `PdfCompressPresetSpecs`), not a remote-fetched list.
///
/// **What's real vs. what's reserved for later**, stated plainly so no
/// future reader mistakes one for the other:
/// - [ModelKind.llm]: two entries. `Qwen2.5-1.5B-Instruct` Q4_K_M remains
///   the required, default baseline - the same `hf://` source
///   `LlamaDartLlmEngine` has downloaded/tested since Phase 0, and every
///   core Resume feature (docs/v3/01-prd.md §13) must work on it alone.
///   `Qwen2.5-3B-Instruct` Q4_K_M is the second, stronger tier added in
///   V3 Milestone 4 (docs/v3/01-prd.md §13/§25, FR3-15/FR3-16) - an
///   explicit opt-in offered via a one-time prompt before first entering
///   the Resume feature, never required, never the default. Its exact
///   choice of model was left "TBD during implementation" by the PRD;
///   Qwen2.5's own next size up was chosen for the same reasons the 1.5B
///   baseline already was (Apache-2.0 licensed, GGUF-quantized, already
///   proven with this app's existing `llamadart` integration) - no new
///   model family, no new download mechanism.
/// - [ModelKind.embedding]: exactly one entry - `embeddinggemma-300M`
///   Q8_0, the same source `LlamaDartEmbeddingEngine` has used since Phase
///   1B (ADR-003).
/// - [ModelKind.speechToText]: all 6 real `WhisperModel` enum values the
///   `whisper_flutter_new` package supports (`tiny`/`base`/`small`/
///   `medium`/`largeV1`/`largeV2`) - only 3 of these were ever exposed in
///   the UI before Phase 6A (`model_setup_screen.dart`/`ai_models_screen
///   .dart`); this catalog is the single source of truth for all 6 going
///   forward, replacing those screens' locally-duplicated lists.
/// - [ModelKind.ocr] / [ModelKind.vision] / [ModelKind.translation]:
///   **zero entries, intentionally** - see [ModelKind]'s own doc comment.
///
/// Every size/RAM figure below is a publicly-documented approximation
/// (whisper.cpp's own model table for the Whisper entries; this app's
/// already-shipped model choices for the LLM/embedding entries) - not a
/// measured figure from a real device in this implementation environment.
class ModelCatalog {
  ModelCatalog._();

  static const llmQwen25_1_5b = AiModelSpec(
    id: 'llm-qwen2.5-1.5b-instruct-q4km',
    kind: ModelKind.llm,
    displayName: 'Standard Chat Model',
    description:
        'Balanced quality and speed for summaries, chat, and Q&A - the '
        'model this app has used since launch.',
    downloadSource:
        'hf://Qwen/Qwen2.5-1.5B-Instruct-GGUF/'
        'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    sizeBytesApprox: 1100 * 1024 * 1024,
    quantization: 'Q4_K_M',
    ramRequirementMb: 2200,
    speedTier: ModelSpeedTier.moderate,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['Chat', 'Summarization', 'Q&A'],
    license: 'Apache 2.0 (Qwen2.5 license)',
    version: '2.5',
    isDefault: true,
  );

  /// docs/v3/01-prd.md §13/§25 Milestone 4 - the optional, stronger second
  /// LLM tier. Not [AiModelSpec.isDefault]: [llmQwen25_1_5b] stays the
  /// model every fresh install already has and the one every core Resume
  /// feature must keep working on (FR3-16) - this is purely an opt-in
  /// upgrade, offered once via `showResumeModelUpgradePromptDialog`.
  static const llmQwen25_3b = AiModelSpec(
    id: 'llm-qwen2.5-3b-instruct-q4km',
    kind: ModelKind.llm,
    displayName: 'Enhanced Chat Model',
    description:
        'Noticeably better quality for resume rewrite suggestions, summaries, '
        'and chat than the standard model - a larger download best suited '
        'to higher-RAM devices.',
    downloadSource:
        'hf://Qwen/Qwen2.5-3B-Instruct-GGUF/'
        'qwen2.5-3b-instruct-q4_k_m.gguf',
    sizeBytesApprox: 1930 * 1024 * 1024,
    quantization: 'Q4_K_M',
    ramRequirementMb: 4000,
    speedTier: ModelSpeedTier.moderate,
    recommendedDeviceTier: RecommendedDeviceTier.highRamDevice,
    capabilities: ['Chat', 'Summarization', 'Q&A', 'Higher-quality resume suggestions'],
    license: 'Apache 2.0 (Qwen2.5 license)',
    version: '2.5',
  );

  static const embeddingGemma300m = AiModelSpec(
    id: 'embedding-gemma-300m-q8',
    kind: ModelKind.embedding,
    displayName: 'Standard Embedding Model',
    description:
        'Turns your documents and meetings into searchable vectors for '
        'Workspace Chat and semantic retrieval.',
    downloadSource: 'hf://ggml-org/embeddinggemma-300M-GGUF/embeddinggemma-300M-Q8_0.gguf',
    sizeBytesApprox: 300 * 1024 * 1024,
    quantization: 'Q8_0',
    ramRequirementMb: 600,
    speedTier: ModelSpeedTier.fast,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['Semantic search', 'Retrieval'],
    license: 'Gemma Terms of Use',
    version: '300M',
    isDefault: true,
  );

  static const whisperTiny = AiModelSpec(
    id: 'whisper-tiny',
    kind: ModelKind.speechToText,
    displayName: 'Tiny',
    description: 'Fastest, least accurate - good for quick drafts on older devices.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin',
    sizeBytesApprox: 75 * 1024 * 1024,
    ramRequirementMb: 390,
    speedTier: ModelSpeedTier.fast,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'tiny',
  );

  static const whisperBase = AiModelSpec(
    id: 'whisper-base',
    kind: ModelKind.speechToText,
    displayName: 'Base',
    description: 'Fast, modest accuracy - a reasonable default for short, clear recordings.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin',
    sizeBytesApprox: 142 * 1024 * 1024,
    ramRequirementMb: 500,
    speedTier: ModelSpeedTier.fast,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'base',
  );

  static const whisperSmall = AiModelSpec(
    id: 'whisper-small',
    kind: ModelKind.speechToText,
    displayName: 'Small',
    description:
        'Slower, more accurate - noticeably better for Indian-language recordings than '
        'Base. The default for new installs.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
    sizeBytesApprox: 466 * 1024 * 1024,
    ramRequirementMb: 1000,
    speedTier: ModelSpeedTier.moderate,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'small',
    isDefault: true,
  );

  static const whisperMedium = AiModelSpec(
    id: 'whisper-medium',
    kind: ModelKind.speechToText,
    displayName: 'Medium',
    description:
        'High accuracy for demanding transcripts (legal, medical, technical terms) - '
        'a large download and noticeably slower on modest hardware.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
    sizeBytesApprox: 1530 * 1024 * 1024,
    ramRequirementMb: 2600,
    speedTier: ModelSpeedTier.slow,
    recommendedDeviceTier: RecommendedDeviceTier.highRamDevice,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'medium',
  );

  static const whisperLargeV1 = AiModelSpec(
    id: 'whisper-large-v1',
    kind: ModelKind.speechToText,
    displayName: 'Large (v1)',
    description:
        'Highest accuracy available - a very large download, best reserved for '
        'higher-RAM devices and content where accuracy matters most.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v1.bin',
    sizeBytesApprox: 3094 * 1024 * 1024,
    ramRequirementMb: 3900,
    speedTier: ModelSpeedTier.slow,
    recommendedDeviceTier: RecommendedDeviceTier.highRamDevice,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'large-v1',
  );

  static const whisperLargeV2 = AiModelSpec(
    id: 'whisper-large-v2',
    kind: ModelKind.speechToText,
    displayName: 'Large (v2)',
    description:
        'Same size class as Large (v1) with the whisper.cpp project\'s later accuracy '
        'improvements - the most accurate option in this catalog.',
    downloadSource: 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin',
    sizeBytesApprox: 3094 * 1024 * 1024,
    ramRequirementMb: 3900,
    speedTier: ModelSpeedTier.slow,
    recommendedDeviceTier: RecommendedDeviceTier.highRamDevice,
    capabilities: ['Speech-to-text'],
    license: 'MIT (whisper.cpp)',
    version: 'large-v2',
  );

  /// P0-7 (Productivity Toolkit - OCR + Searchable PDF) - the catalog's
  /// first real [ModelKind.ocr] entry, closing the "zero entries,
  /// intentionally" gap this class's own doc comment used to describe.
  /// `eng.traineddata` from `tessdata_fast` (Tesseract's own smaller/faster
  /// integer LSTM model set, not the larger `tessdata_best`) - size
  /// confirmed by direct inspection of the file's real GitHub blob page
  /// (3.92 MB), not estimated. Only English is shipped: this session could
  /// not independently confirm other languages' real file sizes in
  /// `tessdata_fast` (some, e.g. Telugu/Tamil, did not even reliably show
  /// up in a repository listing fetch), and this catalog's whole point is
  /// never showing a language option that isn't verified to actually
  /// exist. The architecture is otherwise already language-ready: a second
  /// language is just one more [AiModelSpec] entry with `kind: ModelKind
  /// .ocr` and a real, verified `downloadSource` - no other code changes.
  static const ocrEnglish = AiModelSpec(
    id: 'ocr-eng',
    kind: ModelKind.ocr,
    displayName: 'English',
    description:
        'Recognizes English text in scans and photos so pages become '
        'searchable - the model behind Scan → Searchable PDF, Images → '
        'Searchable PDF, and Run OCR.',
    downloadSource: 'https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata',
    sizeBytesApprox: 4113000,
    ramRequirementMb: 250,
    speedTier: ModelSpeedTier.fast,
    recommendedDeviceTier: RecommendedDeviceTier.anyModernPhone,
    capabilities: ['OCR', 'Searchable PDF'],
    license: 'Apache 2.0 (Tesseract / tessdata_fast)',
    version: 'eng',
    isDefault: true,
  );

  /// Every catalog entry, across every [ModelKind] - deliberately `const`
  /// so `test/services/ai/model_catalog_test.dart` can assert invariants
  /// (exactly one default per kind with entries, every id unique) at
  /// compile-provable data, not runtime-assembled state.
  static const List<AiModelSpec> all = [
    llmQwen25_1_5b,
    llmQwen25_3b,
    embeddingGemma300m,
    whisperTiny,
    whisperBase,
    whisperSmall,
    whisperMedium,
    whisperLargeV1,
    whisperLargeV2,
    ocrEnglish,
  ];

  static List<AiModelSpec> forKind(ModelKind kind) =>
      all.where((m) => m.kind == kind).toList(growable: false);

  static AiModelSpec? byId(String id) {
    for (final spec in all) {
      if (spec.id == id) return spec;
    }
    return null;
  }

  /// The catalog's default pick for [kind] - the model a fresh install
  /// activates with no explicit user choice (mirrors `AppSettings
  /// .whisperModelName`'s existing `'small'` default). Returns `null` for
  /// a [kind] with no catalog entries at all (today: [ModelKind.ocr]/
  /// [ModelKind.vision]/[ModelKind.translation]).
  static AiModelSpec? defaultFor(ModelKind kind) {
    final entries = forKind(kind);
    if (entries.isEmpty) return null;
    return entries.firstWhere((m) => m.isDefault, orElse: () => entries.first);
  }
}
