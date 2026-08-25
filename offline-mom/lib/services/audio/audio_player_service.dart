/// Playback state for a single audio file - deliberately minimal (just
/// what the Transcript tab's playback bar needs), not a full player UI
/// contract.
enum PlaybackStatus { stopped, playing, paused, completed }

/// Contract for playing back a meeting's recorded/imported audio file.
/// Behind an interface for the same reason as [SpeechToTextEngine]/
/// [LlmEngine] - the concrete plugin (`audioplayers`) never leaks into
/// feature code.
abstract class AudioPlayerService {
  Future<void> playFile(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> seek(Duration position);

  Stream<PlaybackStatus> get statusStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;

  Future<void> dispose();
}
