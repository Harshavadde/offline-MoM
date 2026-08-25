import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/chunked_summarization_service.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/ai/llm_engine.dart';
import 'package:offline_mom/services/ai/llm_request_queue.dart';

import '../../test_helpers/fake_ai_engines.dart';

/// A queue wrapper that counts how many requests actually pass through
/// [enqueue], proving [ChunkedSummarizationService] routes every
/// map/reduce call through the shared queue rather than calling the engine
/// directly for any of them (NFR-11, ADR-008).
class _CountingLlmRequestQueue implements LlmRequestQueue {
  _CountingLlmRequestQueue(this._delegate);
  final LlmRequestQueue _delegate;
  int enqueueCount = 0;

  @override
  LlmQueueHandle<T> enqueue<T>(LlmQueueRequest<T> request) {
    enqueueCount++;
    return _delegate.enqueue(request);
  }

  @override
  bool cancel(int requestId) => _delegate.cancel(requestId);

  @override
  Stream<LlmQueueSnapshot> get statusStream => _delegate.statusStream;
}

/// A deterministic "map" behavior that actually shrinks its input (unlike a
/// pure identity echo, which would never converge through hierarchical
/// reduction): pulls out any `..._MARKER` tokens present and returns just
/// those, comma-joined - a short synthetic condensation, standing in for
/// what a real `generateSummary` call would produce (a real, short
/// summary of whatever text it's given). Lets a test trace a specific
/// source region's marker all the way through map -> reduce -> final
/// result without needing a real model.
LlmSummaryResult _markerSummaryOf(String text) {
  final markers = RegExp(r'[A-Z]+_MARKER').allMatches(text).map((m) => m.group(0)!).toSet();
  final summaryText = markers.isEmpty
      ? (text.length <= 20 ? text : text.substring(0, 20))
      : markers.join(', ');
  return LlmSummaryResult(
    summaryText: summaryText,
    minutesOfMeeting: '',
    keyTopics: const [],
    actionItems: const [],
    decisions: const [],
    modelUsed: 'fake',
  );
}

const _threeMarkedParagraphs = [
  'EARLY_MARKER: this is the first paragraph of the source text.',
  'MIDDLE_MARKER: this is a paragraph from the middle of the text.',
  'LATE_MARKER: this is the very last paragraph of the source text.',
];

void main() {
  group('ChunkedSummarizationService', () {
    test('short content (fits in one call) takes the single-call fast path, unchanged', () async {
      final engine = FakeLlmEngine(
        result: const LlmSummaryResult(
          summaryText: 'A short summary.',
          minutesOfMeeting: 'Minutes.',
          keyTopics: ['topic'],
          actionItems: [],
          decisions: [],
          modelUsed: 'fake',
        ),
      );
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
      );

      final result = await service.summarize('A short transcript.');

      expect(result.summaryText, 'A short summary.');
      expect(engine.summaryCalls, ['A short transcript.']);
    });

    test('long content is chunked, and every underlying call stays within the configured budget', () async {
      final engine = FakeLlmEngine(summaryFromText: _markerSummaryOf);
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
        chunkCharBudget: 80,
      );

      await service.summarize(_threeMarkedParagraphs.join('\n\n'));

      expect(engine.summaryCalls.length, greaterThan(1));
      for (final call in engine.summaryCalls) {
        expect(call.length, lessThanOrEqualTo(80));
      }
    });

    test('early, middle, and late source content are all represented in the final summary', () async {
      final engine = FakeLlmEngine(summaryFromText: _markerSummaryOf);
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
        chunkCharBudget: 80,
      );

      final result = await service.summarize(_threeMarkedParagraphs.join('\n\n'));

      expect(result.summaryText, contains('EARLY_MARKER'));
      expect(result.summaryText, contains('MIDDLE_MARKER'));
      expect(result.summaryText, contains('LATE_MARKER'));
    });

    test('a single paragraph longer than the budget is split on sentence boundaries, not mid-word', () async {
      final engine = FakeLlmEngine();
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
        // Wide enough that every individual sentence below (max ~59 chars)
        // fits in one chunk on its own - this test is specifically about
        // sentence-boundary *packing*, not the separate, documented
        // last-resort `_hardSplit` fallback for a single sentence that's
        // longer than the budget even alone (which legitimately can cut
        // mid-word - that's a different, already-covered trade-off).
        chunkCharBudget: 60,
      );

      const oneLongParagraph =
          'This is the first sentence of a long paragraph. This is the second '
          'sentence, also fairly long. This is a third sentence to push it '
          'well past the budget.';

      await service.summarize(oneLongParagraph);

      expect(engine.summaryCalls.length, greaterThan(1));
      // Every chunk boundary lands on a real sentence start, never inside
      // a word - each chunk's trimmed text starts with an uppercase letter
      // (as every sentence in the source does), never a lowercase
      // continuation of a word split across chunks.
      for (final call in engine.summaryCalls) {
        final trimmed = call.trim();
        expect(
          trimmed.isEmpty || !RegExp(r'^[a-z]').hasMatch(trimmed),
          isTrue,
          reason: '"$trimmed" starts mid-word (a lowercase continuation), not at a sentence boundary',
        );
      }
    });

    test('an engine failure during a map-step call propagates, not silently swallowed', () async {
      final engine = FakeLlmEngine(errorToThrow: Exception('model crashed mid-chunk'));
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
        chunkCharBudget: 40,
      );

      const longText = 'First paragraph is long enough to need chunking here.\n\n'
          'Second paragraph also adds real length to the source text.';

      await expectLater(
        service.summarize(longText),
        throwsA(isA<Exception>()),
      );
    });

    test('every map/reduce call is routed through the shared LlmRequestQueue, never called directly', () async {
      final engine = FakeLlmEngine(summaryFromText: _markerSummaryOf);
      final countingQueue = _CountingLlmRequestQueue(DefaultLlmRequestQueue());
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: countingQueue,
        chunkCharBudget: 80,
      );

      await service.summarize(_threeMarkedParagraphs.join('\n\n'));

      // One enqueue per underlying generateSummary call - map calls plus
      // the reduce call(s) - proving no call ever bypasses the queue.
      expect(countingQueue.enqueueCount, engine.summaryCalls.length);
    });

    test('onPreparingModel fires at most once, only on the very first underlying call', () async {
      // FakeLlmEngine.generateSummary deliberately never invokes
      // onPreparingModel at all (there is no download to simulate for a
      // fake) - a real engine does call it, exactly once, on its very
      // first underlying call. This tiny local double actually invokes it,
      // so this test can meaningfully verify ChunkedSummarizationService's
      // own forwarding logic (only the first call gets it) rather than
      // asserting something FakeLlmEngine's own established contract
      // (relied on elsewhere across the suite) doesn't do.
      final engine = _PreparingModelSpyEngine();
      final service = ChunkedSummarizationService(
        llmEngine: engine,
        llmRequestQueue: DefaultLlmRequestQueue(),
        chunkCharBudget: 80,
      );

      var preparingCalls = 0;

      await service.summarize(
        _threeMarkedParagraphs.join('\n\n'),
        onPreparingModel: () => preparingCalls++,
      );

      expect(preparingCalls, 1);
    });
  });
}

/// Delegates summarization to [_markerSummaryOf] but - unlike
/// [FakeLlmEngine] - actually invokes [onPreparingModel], mirroring what a
/// real engine does on its first call. Every other [LlmEngine] method
/// throws [UnimplementedError] - this double exists for exactly one test.
class _PreparingModelSpyEngine implements LlmEngine {
  @override
  Future<LlmSummaryResult> generateSummary(
    String transcriptText, {
    void Function()? onPreparingModel,
  }) async {
    onPreparingModel?.call();
    return _markerSummaryOf(transcriptText);
  }

  @override
  Future<String> answerQuestion(String context, String question) => throw UnimplementedError();

  @override
  Future<String> answerQuestionStream(
    String context,
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<String> answerGeneralKnowledgeStream(
    String question, {
    void Function(String token)? onToken,
    List<LlmChatTurn> history = const [],
  }) =>
      throw UnimplementedError();

  @override
  Future<String> generateFromPrompt(String systemPrompt, String userPrompt) =>
      throw UnimplementedError();

  @override
  Future<void> ensureModelReady({
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  }) =>
      throw UnimplementedError();
}
