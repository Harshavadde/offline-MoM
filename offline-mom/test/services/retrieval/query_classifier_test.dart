import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/chat_session.dart';
import 'package:offline_mom/services/retrieval/query_classifier.dart';

void main() {
  group('DefaultQueryClassifier', () {
    const classifier = DefaultQueryClassifier();

    test('meeting scope classifies as meetingQuestion by default', () {
      final result = classifier.classify('what did we discuss?', ChatScope.meeting);
      expect(result.type, QueryType.meetingQuestion);
    });

    test('document scope classifies as documentQuestion by default', () {
      final result = classifier.classify('what does this say about pricing?', ChatScope.document);
      expect(result.type, QueryType.documentQuestion);
    });

    test('workspace scope with no special pattern classifies as mixed', () {
      final result = classifier.classify('what was decided about the budget?', ChatScope.workspace);
      expect(result.type, QueryType.mixed);
    });

    test('a targeted-lookup question in workspace scope classifies as workspaceSearch', () {
      expect(classifier.classify('find the meeting about onboarding', ChatScope.workspace).type,
          QueryType.workspaceSearch);
      expect(classifier.classify('which document mentions the budget?', ChatScope.workspace).type,
          QueryType.workspaceSearch);
      expect(classifier.classify('where is the Q3 report?', ChatScope.workspace).type,
          QueryType.workspaceSearch);
    });

    test('a summarization pattern classifies as summaryRequest regardless of scope', () {
      expect(classifier.classify('summarize this meeting', ChatScope.meeting).type,
          QueryType.summaryRequest);
      expect(classifier.classify('give me a tldr', ChatScope.workspace).type, QueryType.summaryRequest);
      expect(classifier.classify('what are the key points?', ChatScope.document).type,
          QueryType.summaryRequest);
    });

    test('a comparison pattern classifies as comparisonRequest regardless of scope', () {
      expect(classifier.classify('compare this to last quarter', ChatScope.workspace).type,
          QueryType.comparisonRequest);
      expect(classifier.classify('what is the difference between these two?', ChatScope.document).type,
          QueryType.comparisonRequest);
    });

    test('summarization pattern takes priority over meeting/document scope defaults', () {
      // A scope-specific default (meetingQuestion/documentQuestion) would
      // otherwise mask a genuine summarize/compare request - the pattern
      // match must win.
      final result = classifier.classify('can you summarize this meeting for me?', ChatScope.meeting);
      expect(result.type, QueryType.summaryRequest);
    });

    test('classify never returns generalKnowledge - that is assigned only after retrieval', () {
      for (final scope in ChatScope.values) {
        for (final question in ['random question', 'summarize', 'compare a and b', 'find the doc']) {
          expect(classifier.classify(question, scope).type, isNot(QueryType.generalKnowledge));
        }
      }
    });

    test('summary/comparison requests get a wider candidate pool than a targeted search', () {
      final summary = classifier.classify('summarize everything', ChatScope.workspace);
      final search = classifier.classify('find the onboarding doc', ChatScope.workspace);
      expect(summary.candidateK, greaterThan(search.candidateK));
    });
  });
}
