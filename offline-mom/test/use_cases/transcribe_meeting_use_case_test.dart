import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/transcription/transcribe_meeting_use_case.dart';
import 'package:offline_mom/models/meeting.dart';
import 'package:offline_mom/models/transcript.dart';
import 'package:offline_mom/repositories/meeting_repository.dart';
import 'package:offline_mom/repositories/transcript_repository.dart';
import 'package:offline_mom/services/ai/speech_to_text_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/fake_ai_engines.dart';
import '../test_helpers/test_database.dart';

void main() {
  late Database db;
  late MeetingRepository meetingRepository;
  late TranscriptRepository transcriptRepository;
  late Directory tempDir;

  setUp(() async {
    db = await openTestDatabase();
    meetingRepository = SqfliteMeetingRepository(db);
    transcriptRepository = SqfliteTranscriptRepository(db);
    tempDir = await Directory.systemTemp.createTemp('transcribe_use_case_test_');
  });

  tearDown(() async {
    await db.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// A real file on disk, since [TranscribeMeetingUseCase] now checks
  /// [File.exists] before attempting to transcribe (R5,
  /// docs/v2/implementation/02-backlog.md Task 1.3.1.1) - a path string
  /// alone is no longer enough to reach the "audio present" path.
  Future<String> createRealAudioFile() async {
    final file = File('${tempDir.path}/audio.m4a');
    await file.writeAsBytes([0]);
    return file.path;
  }

  Future<int> insertMeeting({String? audioFilePath}) {
    final now = DateTime(2026, 1, 1);
    return meetingRepository.insert(
      Meeting(
        id: null,
        title: 'Test meeting',
        source: MeetingSource.recorded,
        status: MeetingStatus.created,
        createdAt: now,
        updatedAt: now,
        audioFilePath: audioFilePath,
      ),
    );
  }

  test('transcribes successfully: persists transcript, advances to summarizing',
      () async {
    final meetingId = await insertMeeting(audioFilePath: await createRealAudioFile());
    final useCase = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(
        result: const TranscriptionResult(
          language: 'en',
          fullText: 'We reviewed the roadmap.',
          segments: [
            TranscriptSegment(startMs: 0, endMs: 2000, text: 'We reviewed the roadmap.'),
          ],
        ),
      ),
    );

    await useCase(meetingId);

    final transcript = await transcriptRepository.getForMeeting(meetingId);
    expect(transcript, isNotNull);
    expect(transcript!.fullText, 'We reviewed the roadmap.');

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.summarizing);
  });

  test('engine failure marks the meeting as error and persists no transcript',
      () async {
    final meetingId = await insertMeeting(audioFilePath: await createRealAudioFile());
    final useCase = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(
        errorToThrow: Exception('ffmpeg failed'),
      ),
    );

    await useCase(meetingId);

    expect(await transcriptRepository.getForMeeting(meetingId), isNull);
    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.error);
  });

  test(
      'a meeting with no audio path at all reaches audioMissing with a '
      'diagnosable message, not a silent no-op (real-device QA finding: an '
      'app killed mid-recording, before stopRecording() ever writes the '
      'path, previously left the meeting stuck at created forever with no '
      'error and no way for Retry to know anything was wrong)', () async {
    final meetingId = await insertMeeting(audioFilePath: null);
    final useCase = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(
        errorToThrow: StateError('should not be called'),
      ),
    );

    await useCase(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.audioMissing);
    expect(meeting.errorMessage, isNotNull);
    expect(await transcriptRepository.getForMeeting(meetingId), isNull);
  });

  test('does nothing for an unknown meeting id', () async {
    final useCase = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(),
    );

    await useCase(9999); // should not throw
  });

  test('a meeting whose audio file is missing from disk reaches '
      'audioMissing, not a generic error, and never calls the engine',
      () async {
    final meetingId = await insertMeeting(
      audioFilePath: '${tempDir.path}/never_written.m4a',
    );
    final useCase = TranscribeMeetingUseCase(
      meetingRepository: meetingRepository,
      transcriptRepository: transcriptRepository,
      speechToTextEngine: FakeSpeechToTextEngine(
        errorToThrow: StateError('should not be called'),
      ),
    );

    await useCase(meetingId);

    final meeting = await meetingRepository.getById(meetingId);
    expect(meeting!.status, MeetingStatus.audioMissing);
    expect(meeting.errorMessage, contains('could not be found'));
    expect(await transcriptRepository.getForMeeting(meetingId), isNull);
  });
}
