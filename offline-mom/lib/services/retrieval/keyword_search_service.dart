import 'package:sqflite/sqflite.dart';

import '../../core/utils/fts5_query_builder.dart';
import '../../database/tables.dart';
import '../../models/knowledge_chunk.dart';
import 'knowledge_chunk_filter.dart';
import 'scored_chunk.dart';

/// Chunk-granularity BM25 keyword search over [KnowledgeChunksFtsTable] -
/// the lexical half of the Hybrid Retrieval Engine (V2 Phase 6B, ADR-037),
/// alongside [RetrievalEngine]'s existing vector half. Deliberately its own
/// small interface (not folded into [ContentSearchRepository], which
/// operates at a different granularity for a different consumer - see
/// [KnowledgeChunksFtsTable]'s doc comment).
abstract class KeywordSearchService {
  /// Returns up to [k] chunks matching [query], ordered best-first, each
  /// paired with a **sign-corrected** BM25 score (higher = more relevant -
  /// SQLite's own `bm25()` returns the opposite convention, more negative
  /// = better; this service negates it once here so nothing downstream
  /// has to remember that). Applies [filter] in SQL (`WHERE`), not
  /// in-memory - unlike [KnowledgeChunkFilter.matches] applied by
  /// [BruteForceVectorStore], this service can push the filter down to
  /// the database directly. Returns an empty list for a query with no
  /// alphanumeric tokens, mirroring [ContentSearchRepository.search]'s
  /// identical convention for the same reason.
  Future<List<ScoredChunk>> search(
    String query, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  });
}

class SqfliteKeywordSearchService implements KeywordSearchService {
  SqfliteKeywordSearchService(this._db);

  final Database _db;

  @override
  Future<List<ScoredChunk>> search(
    String query, {
    required int k,
    KnowledgeChunkFilter filter = KnowledgeChunkFilter.workspace,
  }) async {
    if (k <= 0) return const [];
    final matchQuery = buildFts5MatchQuery(query);
    if (matchQuery == null) return const [];

    final whereClauses = <String>[
      '${KnowledgeChunksFtsTable.name} MATCH ?',
    ];
    final args = <Object?>[matchQuery];

    final contentTypes = filter.contentTypes;
    if (contentTypes != null && contentTypes.isNotEmpty) {
      final placeholders = List.filled(contentTypes.length, '?').join(', ');
      whereClauses.add('kc.${KnowledgeChunksTable.contentType} IN ($placeholders)');
      args.addAll(contentTypes.map((c) => c.name));
    }
    if (filter.ownerType == KnowledgeChunkOwnerType.meeting) {
      whereClauses.add('kc.${KnowledgeChunksTable.meetingId} IS NOT NULL');
    }
    if (filter.ownerType == KnowledgeChunkOwnerType.document) {
      whereClauses.add('kc.${KnowledgeChunksTable.documentId} IS NOT NULL');
    }
    if (filter.meetingId != null) {
      whereClauses.add('kc.${KnowledgeChunksTable.meetingId} = ?');
      args.add(filter.meetingId);
    }
    if (filter.documentId != null) {
      whereClauses.add('kc.${KnowledgeChunksTable.documentId} = ?');
      args.add(filter.documentId);
    }

    args.add(k);

    final rows = await _db.rawQuery(
      'SELECT kc.*, bm25(${KnowledgeChunksFtsTable.name}) AS _bm25 '
      'FROM ${KnowledgeChunksFtsTable.name} '
      'JOIN ${KnowledgeChunksTable.name} kc ON kc.${KnowledgeChunksTable.id} = ${KnowledgeChunksFtsTable.name}.rowid '
      'WHERE ${whereClauses.join(' AND ')} '
      'ORDER BY _bm25 ASC '
      'LIMIT ?',
      args,
    );

    return [
      for (final row in rows)
        ScoredChunk(
          chunk: KnowledgeChunk.fromMap(row),
          // SQLite's bm25() is "more negative = better" - negated once
          // here so every caller of this service sees the same
          // "higher = more relevant" convention cosine similarity uses.
          score: -(row['_bm25'] as num).toDouble(),
        ),
    ];
  }
}
