import 'package:record/record.dart';

import 'recorder_service.dart';

/// [RecorderService] implementation backed by the `record` package.
///
/// Records AAC-LC audio (`.m4a`) - a format we already support importing,
/// so a recorded meeting and an imported one flow through the exact same
/// downstream pipeline (transcription, storage) with no branching.
class RecordPackageRecorderService implements RecorderService {
  RecordPackageRecorderService({bool highQuality = false})
      : _config = highQuality ? _highQualityConfig : _standardConfig,
        _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  final RecordConfig _config;

  // Transcription always re-encodes down to 16kHz mono before whisper.cpp
  // sees it (see WhisperSpeechToTextEngine._convertToWav), so the quality
  // choice here only affects standalone playback fidelity and file size,
  // never transcription accuracy.
  static const _standardConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    sampleRate: 16000,
    numChannels: 1,
  );

  static const _highQualityConfig = RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 192000,
    sampleRate: 44100,
    numChannels: 2,
  );

  @override
  Future<bool> hasMicrophonePermission() => _recorder.hasPermission();

  @override
  Future<void> start(String filePath) {
    return _recorder.start(_config, path: filePath);
  }

  @override
  Future<void> pause() => _recorder.pause();

  @override
  Future<void> resume() => _recorder.resume();

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Stream<RecordingSessionState> get stateStream =>
      _recorder.onStateChanged().map((state) => switch (state) {
            RecordState.record => RecordingSessionState.recording,
            RecordState.pause => RecordingSessionState.paused,
            RecordState.stop => RecordingSessionState.stopped,
          });

  @override
  Stream<RecordingAmplitude> get amplitudeStream => _recorder
      .onAmplitudeChanged(const Duration(milliseconds: 200))
      .map((a) => RecordingAmplitude(current: a.current, max: a.max));

  @override
  Future<void> dispose() => _recorder.dispose();
}
