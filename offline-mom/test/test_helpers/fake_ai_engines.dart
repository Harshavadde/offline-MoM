import 'dart:math';

import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/services/ai/embedding_engine.dart';
import 'package:offline_mom/services/ai/llm_engine.dart';
import 'package:offline_mom/services/ai/speech_to_text_engine.dart';

/// Deterministic stand-in for a real whisper.cpp engine, so use-case tests
/// don't depend on native inference or a device.
class FakeSpeechToTextEngine implements SpeechToTextEngine {
  FakeSpeechToTextEngine({this.result, this.errorToThrow});

  final TranscriptionResult? result;
  final Object? errorToThrow;

  @override
  Future<void> ensureModelReady({void Function(double? fraction)? onProgress}) async {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<TranscriptionResult> transcribe(
    String audioFilePath, {
    void Function()? onPreparingModel,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return result ??
        const TranscriptionResult(
          language: 'en',
          fullText: 'Default fake transcript.',
          segments: [
            TranscriptSegment(startMs: 0, endMs: 1000, text: 'Default fake transcript.'),
          ],
        );
  }
}

/// Deterministic stand-in for a real llama.cpp engine, so use-case tests
/// don't depend on native inference or a device.
class FakeLlmEngine implements LlmEngine {
  FakeLlmEngine({
    this.result,
    this.errorToThrow,
    this.answer,
    this.summaryFromText,
    this.promptResponse,
    this.responseFromPrompt,
  });

  final LlmSummaryResult? result;
  final Object? errorToThrow;
  final String? answer;

  /// Fixed response for [generateFromPrompt] - defaults to [answer] when
  /// unset, so a single fake can serve both the chat-shaped methods and
  /// the resume-suggestion prompt method interchangeably in simple tests.
  final String? promptResponse;

  /// When set, [generateFromPrompt] returns this function's result instead
  /// of [promptResponse]/[answer] - lets a test return different raw
  /// output per call (e.g. a malformed response for one entry, a valid one
  /// for another), mirroring [summaryFromText]'s identical role.
  final String Function(String systemPrompt, String userPrompt)? responseFromPrompt;

  /// Every `(systemPrompt, userPrompt)` pair passed to [generateFromPrompt],
  /// in call order - lets a test assert on exactly what was sent without
  /// needing [responseFromPrompt].
  final List<(String, String)> promptCalls = [];

  /// When set, [generateSummary] returns this function's result instead of
  /// the fixed [result]/default - lets a test assert on *which* text a
  /// caller actually sent per call (e.g. `ChunkedSummarizationService`
  /// tests proving early/middle/late source content each reach a distinct
  /// underlying `generateSummary` call), which a single fixed [result]
  /// can't distinguish between calls. Every call is also recorded in
  /// [summaryCalls], regardless of whether this is set.
  final LlmSummaryResult Function(String transcriptText)? summaryFromText;

  /// Every [transcriptText] passed to [generateSummary], in call order -
  /// lets a test assert on chunk boundaries/count without needing
  /// [summaryFromText] at all.
  final List<String> summaryCalls = [];

  /// The [history] most recently passed to [answerQuestionStream] or
  /// [answerGeneralKnowledgeStream] - lets tests assert on what
  /// conversation memory a caller actually supplied, without needing a
  /// real (or controllable) engine.
  List<LlmChatTurn> lastHistory = const [];

  @override
  Future<LlmSummaryResult> generateSummary(
    String transcriptText, {
    void Function()? onPreparingModel,
  }) async {
    summaryCalls.add(transcriptText);
    if (errorToThrow != null) throw errorToThrow!;
    final fromText = summaryFromText;
    if (fromText != null) return fromText(transcriptText);
    return result ??
        const LlmSummaryResult(
          summaryText: 'Default fake summary.',
          minutesOfMeeting: 'Default fake minutes of meeting.',
          keyTopics: ['topic one', 'topic two'],
          actionItems: [
            LlmActionItem(task: 'Do the thing', owner: 'Alex'),
          ],
          decisions: ['Decided the thing'],
          modelUsed: 'fake-model',
        );
  }

  @override
  Future<String> answerQuestion(String context, String question) async {
    if (errorToThrow != null) throw errorToThrow!;
    return answer ?? 'Default fake answer.';
  }

  /// Emits the answer split into whitespace-preserving word-ish chunks via
  /// [onToken] before resolving, so streaming-consumer tests (chat) have
  /// something deterministic to assert against without needing a real
  /// model.
  @override
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) async {
    lastHistory = history;
    if (errorToThrow != null) throw errorToThrow!;
    final result = answer ?? 'Default fake answer.';
    if (onToken != null) {
      final matches = RegExp(r'\S+\s*').allMatches(result);
      for (final match in matches) {
        onToken(match.group(0)!);
      }
    }
    return result;
  }

  /// See [LlmEngine.answerGeneralKnowledgeStream] - reuses [answer]/
  /// [errorToThrow] the same way [answerQuestionStream] does, so a test
  /// can configure one fake for either prompt mode interchangeably.
  @override
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) async {
    lastHistory = history;
    if (errorToThrow != null) throw errorToThrow!;
    final result = answer ?? 'Default fake answer.';
    if (onToken != null) {
      final matches = RegExp(r'\S+\s*').allMatches(result);
      for (final match in matches) {
        onToken(match.group(0)!);
      }
    }
    return result;
  }

  @override
  Future<String> generateFromPrompt(String systemPrompt, String userPrompt) async {
    promptCalls.add((systemPrompt, userPrompt));
    if (errorToThrow != null) throw errorToThrow!;
    final fromPrompt = responseFromPrompt;
    if (fromPrompt != null) return fromPrompt(systemPrompt, userPrompt);
    return promptResponse ?? answer ?? 'Default fake answer.';
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
  }
}

/// Deterministic stand-in for a real llama.cpp-backed embedding model, so
/// retrieval/indexing tests don't depend on native inference or a device.
/// Produces a reproducible, text-dependent (not random) vector per input,
/// so similarity-search tests can assert meaningful relationships between
/// specific inputs (e.g. "text A embeds closer to query Q than text B
/// does") rather than only checking dimensionality.
class FakeEmbeddingEngine implements EmbeddingEngine {
  FakeEmbeddingEngine({this.errorToThrow, this.dimension = 16});

  final Object? errorToThrow;
  final int dimension;

  @override
  Future<List<double>> embed(String text, {bool normalize = true}) async {
    if (errorToThrow != null) throw errorToThrow!;
    return _vectorFor(text);
  }

  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    bool normalize = true,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
    return texts.map(_vectorFor).toList();
  }

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) async {
    if (errorToThrow != null) throw errorToThrow!;
  }

  /// A bag-of-characters hash spread across [dimension] buckets, then
  /// L2-normalized - deterministic and text-sensitive (two different
  /// strings produce different vectors, the same string always produces
  /// the same vector) without needing a real embedding model.
  List<double> _vectorFor(String text) {
    final buckets = List<double>.filled(dimension, 0);
    for (final codeUnit in text.toLowerCase().codeUnits) {
      buckets[codeUnit % dimension] += 1;
    }
    final norm = buckets.fold<double>(0, (sum, v) => sum + v * v);
    if (norm == 0) return buckets;
    final scale = 1 / sqrt(norm);
    return [for (final v in buckets) v * scale];
  }
}
