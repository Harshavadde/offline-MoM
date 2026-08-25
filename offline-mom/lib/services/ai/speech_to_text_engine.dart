import '../../models/transcript.dart';

class TranscriptionResult {
  const TranscriptionResult({
    required this.language,
    required this.fullText,
    required this.segments,
  });

  final String language;
  final String fullText;
  final List<TranscriptSegment> segments;
}

/// Contract for turning an audio file into text, entirely on-device.
///
/// Presentation/use-case code depends only on this interface, never on
/// whisper.cpp or any specific wrapper package directly, so the engine can
/// be swapped without touching a single screen.
abstract class SpeechToTextEngine {
  /// [onPreparingModel] fires once, only the very first time this device
  /// transcribes anything with a given model: the model file (tens to a
  /// few hundred MB) has to be downloaded before any transcription can
  /// run. Callers use it to show "downloading the speech model" instead of
  /// leaving the user staring at a generic "transcribing" spinner for
  /// however long that one-time download takes.
  Future<TranscriptionResult> transcribe(
    String audioFilePath, {
    void Function()? onPreparingModel,
  });

  /// Downloads and caches the model without transcribing anything - used by
  /// onboarding's model-setup step, so the user waits once, up front, on a
  /// screen that says exactly what's happening, instead of the download
  /// silently happening the first time they record or import a meeting.
  /// [onProgress] reports 0.0-1.0 (or null if the total size isn't known
  /// yet, e.g. before the response headers arrive).
  Future<void> ensureModelReady({void Function(double? fraction)? onProgress});
}
