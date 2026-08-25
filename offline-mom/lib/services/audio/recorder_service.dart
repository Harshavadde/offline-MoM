/// Lifecycle states a recording session can be in. Deliberately smaller than
/// the `record` package's own `RecordState` (which also has platform-specific
/// nuance) so presentation code depends only on what it actually needs.
enum RecordingSessionState { recording, paused, stopped }

/// A single amplitude sample, used to drive a live level indicator while
/// recording. Values are dBFS (negative, 0 = loudest); further from 0 is
/// quieter.
class RecordingAmplitude {
  const RecordingAmplitude({required this.current, required this.max});

  final double current;
  final double max;
}

/// Contract for capturing microphone audio to a file.
///
/// Presentation code depends only on this interface, never on the `record`
/// package directly, so the recording backend can be swapped without
/// touching any screen.
abstract class RecorderService {
  Future<bool> hasMicrophonePermission();

  /// Starts a new recording session, writing audio to [filePath].
  Future<void> start(String filePath);

  Future<void> pause();

  Future<void> resume();

  /// Stops the session and returns the final file path (or null if nothing
  /// was recorded).
  Future<String?> stop();

  Stream<RecordingSessionState> get stateStream;

  Stream<RecordingAmplitude> get amplitudeStream;

  Future<void> dispose();
}
