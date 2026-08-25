import 'hybrid_ranker.dart';

/// The final assembled prompt context, plus which chunks actually made it
/// in - callers build [ChatSourceRef]s from [includedChunkIds], never from
/// the full candidate/ranked list, so citations never claim a chunk that
/// was fused/ranked but didn't fit the token budget (no fabricated
/// citations, Phase 6B's explicit "do not fabricate citations"
/// requirement, extended from answers to sources too).
class AssembledContext {
  const AssembledContext({required this.text, required this.includedChunkIds});

  final String text;
  final List<int> includedChunkIds;
}

/// Formats a budget-selected, ranked chunk list into the final prompt
/// context string - ordering, not just concatenation (Phase 6B objective
/// 6, "Context Builder", ADR-037). Chunks are written in fused-rank order
/// (most relevant first), matching `WorkspaceChatUseCase._buildContext`'s
/// original `## <label>\n<text>\n\n` format exactly, so this is a drop-in
/// replacement for that method's output shape - no prompt-format
/// regression for the LLM, only a smarter *selection* of which chunks
/// reach it.
class ContextBuilder {
  const ContextBuilder();

  AssembledContext build(List<RankedChunk> selected, Map<int, String> labelForChunkId) {
    final buffer = StringBuffer();
    final includedIds = <int>[];
    for (final rankedChunk in selected) {
      final id = rankedChunk.chunk.id;
      if (id == null) continue;
      final label = labelForChunkId[id] ?? 'Source';
      buffer.writeln('## $label');
      buffer.writeln(rankedChunk.chunk.chunkText);
      buffer.writeln();
      includedIds.add(id);
    }
    return AssembledContext(text: buffer.toString().trim(), includedChunkIds: includedIds);
  }
}
