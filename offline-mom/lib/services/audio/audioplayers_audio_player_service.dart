import 'package:audioplayers/audioplayers.dart' as ap;

import 'audio_player_service.dart';

class AudioplayersAudioPlayerService implements AudioPlayerService {
  AudioplayersAudioPlayerService() : _player = ap.AudioPlayer();

  final ap.AudioPlayer _player;

  @override
  Future<void> playFile(String path) => _player.play(ap.DeviceFileSource(path));

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> resume() => _player.resume();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Stream<PlaybackStatus> get statusStream =>
      _player.onPlayerStateChanged.map((state) => switch (state) {
            ap.PlayerState.playing => PlaybackStatus.playing,
            ap.PlayerState.paused => PlaybackStatus.paused,
            ap.PlayerState.completed => PlaybackStatus.completed,
            ap.PlayerState.stopped ||
            ap.PlayerState.disposed =>
              PlaybackStatus.stopped,
          });

  @override
  Stream<Duration> get positionStream => _player.onPositionChanged;

  @override
  Stream<Duration> get durationStream => _player.onDurationChanged;

  @override
  Future<void> dispose() => _player.dispose();
}
