import '../../models/document.dart';

/// V2 scaffolding (Epic 2, docs/v2/implementation/02-backlog.md Tasks
/// 2.1.1.5-2.1.1.7). Mirrors [SpeechToTextEngine]'s interface/implementation
/// split (services/ai/speech_to_text_engine.dart) - one interface, one
/// implementation per format, swappable without touching call sites, the
/// same reason that split exists for whisper.cpp.
///
/// Per docs/v2/16-security.md and ADR-016
/// (docs/v2/implementation/03-decisions.md): no concrete implementation is
/// adopted here without a license audit first.
abstract class DocumentTextExtractionService {
  DocumentSourceType get supportedSourceType;

  /// Extracts plain text from the file at [filePath]. Returns null (not an
  /// empty string) when no extractable text layer is found - e.g. a
  /// scanned/image-only PDF - so callers can distinguish "genuinely no
  /// text" from "extraction produced an empty document," per ADR-015's
  /// "clear error, not silent failure" decision.
  Future<String?> extractText(String filePath);
}
