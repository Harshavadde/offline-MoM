/// Barrel export for the retrieval infrastructure (V2 Phase 1B, M1.2) -
/// chunking, vector storage, indexing orchestration, and query retrieval.
/// See docs/v2/14-rag-architecture.md, ADR-003/004
/// (docs/v2/implementation/03-decisions.md), and
/// docs/v2/implementation/spikes/m1-0-embedding-spike.md.
library;

export 'chunking_service.dart';
export 'knowledge_chunk_filter.dart';
export 'vector_store.dart';
export 'indexing_service.dart';
export 'retrieval_engine.dart';
