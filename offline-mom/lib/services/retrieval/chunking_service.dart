/// Splits long text into retrieval-sized pieces - see
/// docs/v2/14-rag-architecture.md for the chunking strategy and ADR-011
/// (docs/v2/implementation/03-decisions.md) for the chunk-size parameters.
abstract class ChunkingService {
  /// Splits [text] (the full transcript/extracted-text of one meeting or
  /// document) into ordered, retrieval-sized [TextChunk]s.
  List<TextChunk> chunk(String text);
}

/// One chunk of source text, not yet embedded - [ChunkingService]'s output,
/// [EmbeddingEngine]'s input (see services/ai/embedding_engine.dart), on
/// its way to becoming a [KnowledgeChunk] (lib/models/knowledge_chunk.dart)
/// once embedded and persisted.
class TextChunk {
  const TextChunk({required this.index, required this.text});

  final int index;
  final String text;
}

/// Paragraph/sentence-boundary-aware chunking per
/// docs/v2/14-rag-architecture.md ("not a fixed-character-count cut") and
/// ADR-011's chunk-size target (~200-250 tokens per chunk).
///
/// [targetChunkChars] is a *character* budget, not a token budget, because
/// this runs synchronously over plain text with no tokenizer call per
/// candidate split point (round-tripping every paragraph through the
/// embedding engine's worker isolate just to count tokens during chunking
/// would make indexing a large document meaningfully slower for no
/// retrieval-quality benefit - the real token budget is enforced once,
/// downstream, by whatever assembles the final chat prompt). The default
/// (900 chars) is derived from ADR-011's 200-250 token target using the
/// commonly-cited ~4 characters-per-token average for English prose with a
/// BPE/SentencePiece-family tokenizer (the family `embeddinggemma`'s
/// tokenizer belongs to) - see
/// docs/v2/implementation/spikes/m1-0-embedding-spike.md for why this
/// ratio, not a measured one, is what's available: this spike could not
/// execute the real tokenizer against real content (no on-device runtime
/// in this development environment), so the ratio is a documented,
/// widely-used estimate to be re-validated empirically once real
/// on-device runs are possible, per ADR-011's own "starting values, not
/// final tuned constants" framing.
class DefaultChunkingService implements ChunkingService {
  const DefaultChunkingService({
    this.targetChunkChars = 900,
    this.overlapSentences = 2,
  });

  final int targetChunkChars;
  final int overlapSentences;

  static final _paragraphSplit = RegExp(r'\n\s*\n');
  static final _sentenceSplit = RegExp(r'(?<=[.!?])\s+');

  @override
  List<TextChunk> chunk(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final sentences = <String>[];
    for (final paragraph in trimmed.split(_paragraphSplit)) {
      final paragraphTrimmed = paragraph.trim();
      if (paragraphTrimmed.isEmpty) continue;
      for (final sentence in paragraphTrimmed.split(_sentenceSplit)) {
        final sentenceTrimmed = sentence.trim();
        if (sentenceTrimmed.isNotEmpty) sentences.add(sentenceTrimmed);
      }
    }
    if (sentences.isEmpty) return const [];

    final chunks = <TextChunk>[];
    var buffer = <String>[];
    var bufferChars = 0;

    void flush() {
      if (buffer.isEmpty) return;
      chunks.add(TextChunk(index: chunks.length, text: buffer.join(' ')));
    }

    for (final sentence in sentences) {
      final addedLength = sentence.length + (buffer.isEmpty ? 0 : 1);
      if (buffer.isNotEmpty && bufferChars + addedLength > targetChunkChars) {
        flush();
        // Carry the trailing sentences forward as overlap, per
        // docs/v2/14-rag-architecture.md, so an answer-relevant sentence
        // sitting near a chunk boundary isn't split away from its
        // surrounding context.
        buffer = buffer.length <= overlapSentences
            ? List.of(buffer)
            : buffer.sublist(buffer.length - overlapSentences);
        bufferChars = buffer.fold(0, (sum, s) => sum + s.length + 1);
      }
      buffer.add(sentence);
      bufferChars += sentence.length + 1;
    }
    flush();

    return chunks;
  }
}
