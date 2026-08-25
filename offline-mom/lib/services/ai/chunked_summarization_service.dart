import 'llm_engine.dart';
import 'llm_request_queue.dart';

/// Closes M2.4 (docs/v2/07-feature-roadmap.md Phase 2): replaces flat
/// truncation at [LlamaDartLlmEngine]'s internal `_maxTranscriptChars`
/// (4000) with real chunked, hierarchical map-reduce summarization, so a
/// long meeting transcript or document doesn't silently lose everything
/// past its first ~700-800 words.
///
/// Reuses [LlmEngine.generateSummary] as both the map step (one call per
/// chunk) and the reduce step (one call on the combined intermediate
/// summaries) - no new engine method, no new prompt, no parallel engine
/// instance. Every call still goes through the same shared
/// [LlmRequestQueue] a direct `generateSummary` call already did, so
/// nothing about NFR-11's single-flight/foreground-pause contract changes;
/// each individual call keeps [LlamaDartLlmEngine]'s existing per-call
/// stall timeout/cancellation, since that lives inside `generateSummary`
/// itself and this service never bypasses it.
///
/// **Fast path unchanged:** content that already fits in one call (the
/// overwhelming common case - most meetings/documents) takes exactly the
/// same single `generateSummary` call as before, with no chunking overhead
/// at all.
class ChunkedSummarizationService {
  const ChunkedSummarizationService({
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
    this.chunkCharBudget = _defaultChunkCharBudget,
  })  : _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue;

  final LlmEngine _llmEngine;
  final LlmRequestQueue _llmRequestQueue;

  /// Deliberately below [LlamaDartLlmEngine]'s own internal
  /// `_maxTranscriptChars` (4000) - every chunk this service ever hands to
  /// `generateSummary` should comfortably fit under that engine-level
  /// truncation point on its own, with headroom for this service's own
  /// "Part N: " reduce-step framing text. A `const` default rather than a
  /// value read from the engine itself: [LlmEngine] is an interface with no
  /// such property, and adding one just to avoid one duplicated constant
  /// would be a bigger interface change than the constant is worth.
  static const _defaultChunkCharBudget = 3500;

  final int chunkCharBudget;

  /// Hard ceiling on reduce levels - a real bug (caught by this service's
  /// own test suite, not assumed away) proved this must be bounded: if
  /// per-chunk summaries don't compress enough relative to
  /// [chunkCharBudget] (e.g. a small/fixed-length summarizer whose
  /// "Part N: "-framed output doesn't shrink round over round), the
  /// combined reduce input can stay the same size - or even the same
  /// content - forever, and an unbounded recursion never terminates. Five
  /// levels is already an enormous compression ratio in the case that does
  /// converge (each level can fold dozens of chunks into one); if reduction
  /// still hasn't converged by then, something about the inputs genuinely
  /// isn't compressing, and one final direct call on the (possibly still
  /// long) combined text - accepting whatever truncation
  /// [LlmEngine.generateSummary] itself applies - is strictly better than
  /// hanging.
  static const _maxReduceDepth = 5;

  /// Summarizes [text], transparently chunking and hierarchically reducing
  /// if it's longer than [chunkCharBudget]. [onPreparingModel] fires (at
  /// most once) only on this call's very first underlying `generateSummary`
  /// invocation - by the time any later chunk/reduce call runs, the model
  /// is already loaded, so there's nothing further to announce.
  Future<LlmSummaryResult> summarize(String text, {void Function()? onPreparingModel}) {
    return _summarizeRecursive(text, onPreparingModel: onPreparingModel, depth: 0);
  }

  Future<LlmSummaryResult> _summarizeRecursive(
    String text, {
    void Function()? onPreparingModel,
    required int depth,
  }) async {
    if (text.length <= chunkCharBudget || depth >= _maxReduceDepth) {
      return _generateSummary(text, onPreparingModel: onPreparingModel);
    }

    final chunks = _splitIntoChunks(text);
    // A single "chunk" that's just the whole text again (nothing left to
    // split further - e.g. one word alone longer than the budget) would
    // otherwise recurse forever on unchanged input; fall through to a
    // direct call instead of looping.
    if (chunks.length <= 1) {
      return _generateSummary(text, onPreparingModel: onPreparingModel);
    }

    final partSummaries = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final result = await _generateSummary(
        chunks[i],
        onPreparingModel: i == 0 ? onPreparingModel : null,
      );
      partSummaries.add('Part ${i + 1}: ${result.summaryText}');
    }

    // Reduce: combine the map step's intermediate summaries into one
    // "transcript" and summarize that. If the combined text is itself
    // still too long (a very long source, many chunks), recurse - this
    // naturally produces hierarchical (multi-level) reduction rather than
    // ever sending an oversized reduce prompt. Bounded by [_maxReduceDepth]
    // above, so this can never recurse forever even if [combined] doesn't
    // shrink round over round.
    final combined = partSummaries.join('\n\n');
    return _summarizeRecursive(combined, depth: depth + 1);
  }

  Future<LlmSummaryResult> _generateSummary(String text, {void Function()? onPreparingModel}) {
    return _llmRequestQueue
        .enqueue(
          LlmQueueRequest(
            isForeground: false,
            run: () => _llmEngine.generateSummary(text, onPreparingModel: onPreparingModel),
          ),
        )
        .result;
  }

  /// Packs [text] into chunks up to [chunkCharBudget], preferring to break
  /// on paragraph boundaries (never mid-word/mid-sentence unless a single
  /// paragraph itself exceeds the budget, in which case
  /// [_splitLongParagraph] takes over for just that paragraph).
  List<String> _splitIntoChunks(String text) {
    final paragraphs = text.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).toList();
    final chunks = <String>[];
    var current = '';

    void flush() {
      if (current.isNotEmpty) {
        chunks.add(current);
        current = '';
      }
    }

    for (final paragraph in paragraphs) {
      if (paragraph.length > chunkCharBudget) {
        flush();
        chunks.addAll(_splitLongParagraph(paragraph));
        continue;
      }
      final candidate = current.isEmpty ? paragraph : '$current\n\n$paragraph';
      if (candidate.length > chunkCharBudget) {
        flush();
        current = paragraph;
      } else {
        current = candidate;
      }
    }
    flush();
    return chunks;
  }

  /// Splits a single over-budget paragraph on sentence boundaries instead
  /// of blindly cutting through a word.
  List<String> _splitLongParagraph(String paragraph) {
    final sentences =
        paragraph.split(RegExp(r'(?<=[.!?])\s+')).where((s) => s.isNotEmpty).toList();
    final chunks = <String>[];
    var current = '';

    for (final sentence in sentences) {
      if (sentence.length > chunkCharBudget) {
        if (current.isNotEmpty) {
          chunks.add(current);
          current = '';
        }
        chunks.addAll(_hardSplit(sentence));
        continue;
      }
      final candidate = current.isEmpty ? sentence : '$current $sentence';
      if (candidate.length > chunkCharBudget) {
        chunks.add(current);
        current = sentence;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  /// Last resort for a single "sentence" (no punctuation at all, e.g. a
  /// wall of unpunctuated text) that alone exceeds the budget - a plain
  /// fixed-length split, so this service can never produce an unbounded
  /// chunk regardless of input shape.
  List<String> _hardSplit(String text) {
    final result = <String>[];
    for (var i = 0; i < text.length; i += chunkCharBudget) {
      final end = i + chunkCharBudget > text.length ? text.length : i + chunkCharBudget;
      result.add(text.substring(i, end));
    }
    return result;
  }
}
