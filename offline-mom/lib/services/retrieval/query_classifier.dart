import '../../models/chat_session.dart';

/// The 7 query types the Hybrid Retrieval Engine (V2 Phase 6B, ADR-037)
/// identifies. **Honest scope, stated once here**: 6 of these 7 are
/// genuinely detectable *before* retrieval runs, from [ChatScope] and
/// simple keyword patterns - [documentQuestion], [meetingQuestion],
/// [summaryRequest], [comparisonRequest], [workspaceSearch], [mixed].
/// [generalKnowledge] is **not** predicted upfront by [QueryClassifier] -
/// no keyword pattern reliably distinguishes "what's the capital of
/// France" from "what did we decide about the Q3 budget" without already
/// knowing whether the workspace has anything about it. Instead,
/// [generalKnowledge] is assigned *after* retrieval, based on
/// [RetrievalConfidence] (see `HybridRetrievalPipeline
/// .effectiveQueryType`) - evidence-based, not guessed. This file's own
/// [QueryClassifier.classify] never returns [generalKnowledge]; only the
/// pipeline's post-retrieval result can.
enum QueryType {
  documentQuestion,
  meetingQuestion,
  generalKnowledge,
  mixed,
  workspaceSearch,
  summaryRequest,
  comparisonRequest,
}

/// The classifier's pre-retrieval guess, plus the retrieval-behavior
/// adjustments it implies - "different query types should produce
/// different retrieval behavior where appropriate" (Phase 6B objective),
/// concretely: how many candidates to fetch per stage before fusion.
class QueryClassification {
  const QueryClassification({required this.type, required this.candidateK});

  final QueryType type;

  /// How many candidates each of the vector/keyword stages should fetch
  /// *before* fusion (not the final number of chunks sent to the LLM -
  /// see `TokenBudgetSelector` for that). Wider for query types that
  /// benefit from a larger candidate pool (summaries, comparisons across
  /// multiple sources); narrower for a targeted lookup.
  final int candidateK;
}

abstract class QueryClassifier {
  QueryClassification classify(String question, ChatScope scope);
}

class DefaultQueryClassifier implements QueryClassifier {
  const DefaultQueryClassifier();

  static const _defaultK = 8;
  static const _summaryOrComparisonK = 12;
  static const _targetedSearchK = 5;

  static final _summaryPattern = RegExp(
    r'\b(summar(y|ize|ise)|overview|tl;?dr|recap|key points?)\b',
    caseSensitive: false,
  );

  static final _comparisonPattern = RegExp(
    r'\b(compare|comparison|versus|vs\.?|difference(s)? between|similarit(y|ies))\b',
    caseSensitive: false,
  );

  static final _targetedSearchPattern = RegExp(
    r'^\s*(find|which|where is|show me|locate)\b',
    caseSensitive: false,
  );

  @override
  QueryClassification classify(String question, ChatScope scope) {
    if (_summaryPattern.hasMatch(question)) {
      return const QueryClassification(type: QueryType.summaryRequest, candidateK: _summaryOrComparisonK);
    }
    if (_comparisonPattern.hasMatch(question)) {
      return const QueryClassification(type: QueryType.comparisonRequest, candidateK: _summaryOrComparisonK);
    }

    switch (scope) {
      case ChatScope.meeting:
        return const QueryClassification(type: QueryType.meetingQuestion, candidateK: _defaultK);
      case ChatScope.document:
        return const QueryClassification(type: QueryType.documentQuestion, candidateK: _defaultK);
      case ChatScope.workspace:
      case ChatScope.general:
        if (_targetedSearchPattern.hasMatch(question)) {
          return const QueryClassification(type: QueryType.workspaceSearch, candidateK: _targetedSearchK);
        }
        return const QueryClassification(type: QueryType.mixed, candidateK: _defaultK);
    }
  }
}
