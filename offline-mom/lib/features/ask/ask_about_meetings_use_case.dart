import 'package:intl/intl.dart';

import '../../models/meeting.dart';
import '../../repositories/meeting_repository.dart';
import '../../repositories/summary_repository.dart';
import '../../services/ai/llm_engine.dart';
import '../../services/ai/llm_request_queue.dart';

class AskAboutMeetingsAnswer {
  const AskAboutMeetingsAnswer({
    required this.answer,
    required this.sourceMeetings,
  });

  final String answer;
  final List<Meeting> sourceMeetings;
}

/// The distinctive feature this app has that most meeting assistants don't:
/// a fully offline, cross-meeting "ask a question" mode. It works because
/// everything it needs - transcripts, summaries, the LLM itself - already
/// lives on-device; there's no cloud vector database or hosted RAG service
/// involved, just local keyword relevance scoring feeding a small local
/// context window into the same on-device LLM used for summarization.
///
/// This is genuine multi-repository orchestration with real branching
/// (no meetings yet vs. no relevant match vs. found matches), so it earns
/// living as its own use case.
class AskAboutMeetingsUseCase {
  AskAboutMeetingsUseCase({
    required MeetingRepository meetingRepository,
    required SummaryRepository summaryRepository,
    required LlmEngine llmEngine,
    required LlmRequestQueue llmRequestQueue,
  })  : _meetingRepository = meetingRepository,
        _summaryRepository = summaryRepository,
        _llmEngine = llmEngine,
        _llmRequestQueue = llmRequestQueue;

  final MeetingRepository _meetingRepository;
  final SummaryRepository _summaryRepository;
  final LlmEngine _llmEngine;

  /// Submitted as a foreground request (ADR-008,
  /// docs/v2/implementation/03-decisions.md) - a user is actively waiting
  /// on this, so it never waits behind a queued (not yet started)
  /// background summary job.
  final LlmRequestQueue _llmRequestQueue;

  static const _maxMeetingsInContext = 4;

  static const _stopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'did', 'do', 'does',
    'for', 'from', 'had', 'has', 'have', 'how', 'in', 'is', 'it', 'of',
    'on', 'or', 'our', 'that', 'the', 'to', 'us', 'was', 'we', 'were',
    'what', 'when', 'where', 'which', 'who', 'will', 'with', 'would',
  };

  Future<AskAboutMeetingsAnswer> call(String question) async {
    final trimmed = question.trim();
    final allMeetings = await _meetingRepository.getAll();
    final readyMeetings = allMeetings.where((m) => m.status == MeetingStatus.ready).toList();

    if (readyMeetings.isEmpty) {
      return const AskAboutMeetingsAnswer(
        answer: "You don't have any fully-processed meetings yet - record "
            'or import one and let it finish transcribing and '
            'summarizing, then ask again.',
        sourceMeetings: [],
      );
    }

    final questionWords = _wordsOf(trimmed);
    final scored = <(Meeting, int)>[];
    for (final meeting in readyMeetings) {
      final summary = await _summaryRepository.getForMeeting(meeting.id!);
      if (summary == null) continue;
      final haystack = _wordsOf(
        '${meeting.title} ${summary.summaryText} ${summary.keyTopics.join(' ')}',
      );
      final overlap = questionWords.intersection(haystack).length;
      scored.add((meeting, overlap));
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final anyMatched = scored.isNotEmpty && scored.first.$2 > 0;
    final chosen = (anyMatched ? scored.where((s) => s.$2 > 0) : scored)
        .take(_maxMeetingsInContext)
        .map((s) => s.$1)
        .toList();

    if (chosen.isEmpty) {
      return const AskAboutMeetingsAnswer(
        answer: "None of your meetings look related to that yet - try "
            'mentioning something closer to what was actually discussed.',
        sourceMeetings: [],
      );
    }

    final contextBuffer = StringBuffer();
    for (final meeting in chosen) {
      final summary = await _summaryRepository.getForMeeting(meeting.id!);
      if (summary == null) continue;
      contextBuffer.writeln(
        '## ${meeting.title} (${DateFormat.yMMMd().format(meeting.createdAt)})',
      );
      contextBuffer.writeln(summary.summaryText);
      if (summary.keyTopics.isNotEmpty) {
        contextBuffer.writeln('Key topics: ${summary.keyTopics.join(', ')}');
      }
      contextBuffer.writeln();
    }

    final answer = await _llmRequestQueue
        .enqueue(
          LlmQueueRequest(
            isForeground: true,
            run: () => _llmEngine.answerQuestion(contextBuffer.toString(), trimmed),
          ),
        )
        .result;
    return AskAboutMeetingsAnswer(answer: answer, sourceMeetings: chosen);
  }

  Set<String> _wordsOf(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length > 2 && !_stopWords.contains(w))
        .toSet();
  }
}
