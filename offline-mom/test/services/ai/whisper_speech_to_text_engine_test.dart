import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/core/constants/app_constants.dart';
import 'package:offline_mom/services/ai/model_download_service.dart';
import 'package:offline_mom/services/ai/whisper_speech_to_text_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

/// [whisperModelDirectory] resolves via `getApplicationSupportDirectory()`
/// on Android or `getLibraryDirectory()` elsewhere - `flutter test` always
/// runs on the host (never Android), so only `getLibraryPath` needs faking
/// here (mirrors `model_download_controller_test.dart`'s identical pattern).
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;
  @override
  Future<String?> getLibraryPath() async => _path;
  @override
  Future<String?> getApplicationSupportPath() async => _path;
}

/// [WhisperSpeechToTextEngine.transcribe] itself can't be unit-tested
/// without a device (real whisper.cpp/ffmpeg native calls) - same standing
/// limitation as every other native-engine class in this project. What
/// *is* unit-testable, and what this V2.1 Production Hardening fix
/// depends on being correct, is the pure duration-estimation and
/// timeout-calculation logic the fix adds - covered here.
void main() {
  group('WhisperSpeechToTextEngine.estimateWavDuration', () {
    test('a 10-second 16kHz mono 16-bit WAV is estimated as 10 seconds', () {
      const headerBytes = 44;
      const bytesPerSecond = 16000 * 2;
      const fileSize = headerBytes + bytesPerSecond * 10;
      expect(
        WhisperSpeechToTextEngine.estimateWavDuration(fileSize),
        const Duration(seconds: 10),
      );
    });

    test('a file no larger than the header is estimated as zero duration', () {
      expect(
        WhisperSpeechToTextEngine.estimateWavDuration(44),
        Duration.zero,
      );
      expect(
        WhisperSpeechToTextEngine.estimateWavDuration(0),
        Duration.zero,
      );
    });

    test('does not throw on a file smaller than the header (malformed input)', () {
      expect(
        () => WhisperSpeechToTextEngine.estimateWavDuration(10),
        returnsNormally,
      );
      expect(WhisperSpeechToTextEngine.estimateWavDuration(10), Duration.zero);
    });
  });

  group('WhisperSpeechToTextEngine.transcriptionTimeoutFor', () {
    test('a very short recording still gets the floor timeout, not a tiny one', () {
      final timeout = WhisperSpeechToTextEngine.transcriptionTimeoutFor(
        const Duration(seconds: 5),
      );
      expect(timeout, AppConstants.whisperTranscriptionTimeoutFloor);
    });

    test('a long recording scales past the floor by the configured multiplier', () {
      const audioDuration = Duration(hours: 1);
      final timeout = WhisperSpeechToTextEngine.transcriptionTimeoutFor(audioDuration);
      expect(
        timeout,
        audioDuration * AppConstants.whisperTranscriptionTimeoutMultiplier,
      );
      expect(timeout > AppConstants.whisperTranscriptionTimeoutFloor, isTrue);
    });

    test('the timeout is never below the floor, regardless of audio duration', () {
      expect(
        WhisperSpeechToTextEngine.transcriptionTimeoutFor(Duration.zero) >=
            AppConstants.whisperTranscriptionTimeoutFloor,
        isTrue,
      );
    });

    test('this is a bounded value, not an infinite/unbounded wait, for any input', () {
      for (final audioDuration in [
        Duration.zero,
        const Duration(minutes: 1),
        const Duration(hours: 3),
      ]) {
        final timeout = WhisperSpeechToTextEngine.transcriptionTimeoutFor(audioDuration);
        expect(timeout.isNegative, isFalse);
        expect(timeout, isNot(equals(Duration.zero)));
      }
    });
  });

  group('WhisperSpeechToTextEngine.ensureModelDownloaded', () {
    // Real-device beta fix (Phase 9): this used to be a hand-rolled
    // download loop with no Range support that discarded its partial file
    // on any interruption - confirmed on a real Android phone as "download
    // restarts from zero after backgrounding the app". It now delegates to
    // [ModelDownloadService], the same resumable primitive the Model
    // Manager's LLM/embedding downloads already use. These tests cover the
    // delegation itself (right URL/destination reach the service, a
    // failure leaves a resumable partial behind, an already-downloaded
    // model never touches the network) - real Range-header wire behavior
    // is already covered by `model_download_service_test.dart`'s
    // loopback-server tests, and physical Android background/resume
    // behavior can only be verified on a device, not in this suite.
    late Directory modelDir;

    setUp(() async {
      modelDir = await Directory.systemTemp.createTemp('whisper_download_test_');
      PathProviderPlatform.instance = _FakePathProviderPlatform(modelDir.path);
    });

    tearDown(() async {
      if (await modelDir.exists()) await modelDir.delete(recursive: true);
    });

    test('delegates to the injected ModelDownloadService with the model URL and destination path', () async {
      String? capturedUrl;
      File? capturedDestination;
      final recordingService = _RecordingDownloadService((url, destination) {
        capturedUrl = url;
        capturedDestination = destination;
      });

      await WhisperSpeechToTextEngine.ensureModelDownloaded(
        WhisperModel.tiny,
        downloadService: recordingService,
      );

      expect(capturedUrl, contains('ggml-tiny.bin'));
      expect(capturedDestination!.path, endsWith('ggml-tiny.bin'));
    });

    test('a model that is already on disk is never re-downloaded', () async {
      final existing = File('${modelDir.path}/ggml-tiny.bin');
      await existing.writeAsBytes([1, 2, 3]);
      var downloadCalled = false;
      final recordingService = _RecordingDownloadService((_, __) => downloadCalled = true);

      await WhisperSpeechToTextEngine.ensureModelDownloaded(
        WhisperModel.tiny,
        downloadService: recordingService,
      );

      expect(downloadCalled, isFalse);
    });

    test('WhisperModel.none never calls the download service', () async {
      var downloadCalled = false;
      final recordingService = _RecordingDownloadService((_, __) => downloadCalled = true);

      await WhisperSpeechToTextEngine.ensureModelDownloaded(
        WhisperModel.none,
        downloadService: recordingService,
      );

      expect(downloadCalled, isFalse);
    });

    test('an interrupted download leaves a resumable partial the service can pick back up', () async {
      final failingService = FakeModelDownloadService(
        chunkCount: 2,
        bytesPerChunk: 100,
        failWith: ModelDownloadException('Download stalled - check your internet connection and try again.'),
      );
      final destination = File('${modelDir.path}/ggml-tiny.bin');

      await expectLater(
        () => WhisperSpeechToTextEngine.ensureModelDownloaded(
          WhisperModel.tiny,
          downloadService: failingService,
        ),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(await failingService.hasPartialDownload(destination), isTrue);
      expect(await destination.exists(), isFalse);

      final succeedingService = FakeModelDownloadService(chunkCount: 2, bytesPerChunk: 100);
      await WhisperSpeechToTextEngine.ensureModelDownloaded(
        WhisperModel.tiny,
        downloadService: succeedingService,
      );
      expect(await destination.exists(), isTrue);
    });
  });
}

/// Records the URL/destination [WhisperSpeechToTextEngine] passes through
/// to [ModelDownloadService.download] without doing any real I/O -
/// verifies the delegation itself, distinct from
/// [FakeModelDownloadService] which simulates the download's outcome.
class _RecordingDownloadService implements ModelDownloadService {
  _RecordingDownloadService(this.onDownload);
  final void Function(String url, File destination) onDownload;

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    onDownload(url, destination);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes([1, 2, 3]);
    return const ModelDownloadOutcome(sizeBytes: 3, sha256Hex: 'unused');
  }

  @override
  Future<bool> hasPartialDownload(File destination) async => false;

  @override
  Future<void> deletePartialDownload(File destination) async {}
}
