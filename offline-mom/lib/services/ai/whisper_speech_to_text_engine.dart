import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_flutter_new/whisper_flutter_new.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ai_model_paths.dart';
import '../../models/transcript.dart';
import 'model_download_service.dart';
import 'model_lifecycle_manager.dart';
import 'speech_to_text_engine.dart';

/// Thrown when the native whisper.cpp transcription call itself stalls or
/// hangs (V2.1 Production Hardening) - distinct from a model *download*
/// timeout (that path was already bounded; see [WhisperSpeechToTextEngine
/// ._downloadModelFile]). Root cause: `Whisper.transcribe()`
/// (`whisper_flutter_new`) is a single monolithic `Future` with no
/// progress callback and no public cancellation API, unlike this app's
/// LLM/embedding engines - so unlike those, this can only be bounded by a
/// flat wall-clock cap, not a per-token stall timer, and the underlying
/// native isolate cannot be force-stopped early the way `LlamaEngine
/// .cancelGeneration()` can. See [AppConstants
/// .whisperTranscriptionTimeoutMultiplier]'s doc comment for why the cap
/// is duration-scaled rather than a single fixed number.
class WhisperTranscriptionTimeoutException implements Exception {
  WhisperTranscriptionTimeoutException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// [SpeechToTextEngine] backed by whisper.cpp (via `whisper_flutter_new`).
///
/// whisper.cpp only reads 16kHz mono PCM WAV, but the app records/imports
/// audio as AAC (`.m4a`) - smaller, and lets recordings double as something
/// you could actually play back. So every transcription first re-encodes
/// the source into a throwaway WAV (via ffmpeg, already a dependency for
/// video import) and deletes it once whisper is done with it.
///
/// The whisper model itself (~140MB for `base`) is downloaded from Hugging
/// Face on first use and cached on-device from then on - the one deliberate
/// exception to "fully offline": a one-time asset download, not a runtime
/// dependency. Every actual transcription after that runs locally with no
/// network access.
///
/// `whisper_flutter_new` *can* do this download itself, but its own
/// implementation has no timeout at all (a plain `HttpClient` request with
/// default, unbounded timeouts) - on a slow or dropped connection it can
/// hang indefinitely with the UI stuck on a generic "transcribing" spinner,
/// giving no sign anything is even happening. This class does the download
/// itself first, with real timeouts and a status callback, and lets the
/// package's own download step become a no-op (it only downloads if the
/// model file isn't already there).
class WhisperSpeechToTextEngine implements SpeechToTextEngine {
  WhisperSpeechToTextEngine({
    this.model = WhisperModel.base,
    this.language = 'auto',
    this.translateToEnglish = false,
    ModelLifecycleManager? lifecycleManager,
  })  : _whisper = Whisper(model: model),
        _lifecycleManager = lifecycleManager {
    // Unlike the two `LlamaEngine`-backed engines, there is nothing to
    // unload here: `Whisper.transcribe` (whisper_flutter_new) spawns a
    // fresh `Isolate.run(...)` per call that loads the native model,
    // transcribes, and tears the isolate (and every native resource it
    // holds) down when the call completes - already the "never resident
    // longer than actively needed" behavior Phase 3A asks for, with no
    // persistent handle this class could unload even if it wanted to.
    // Attached anyway so [ModelLifecycleManager.statusOf] can report this
    // engine consistently alongside the LLM/embedding ones (Phase 3A
    // "reporting model status" for every model-backed engine) - `_active`
    // reflects "a transcription is running right now", not "a model is
    // resident in memory", since for Whisper those are the same window.
    _lifecycleManager?.attach(
      ModelKind.speechToText,
      unload: () async {},
      statusOf: () => _active ? ModelStatus.loaded : ModelStatus.unloaded,
    );
  }

  final Whisper _whisper;
  final WhisperModel model;
  final ModelLifecycleManager? _lifecycleManager;
  bool _active = false;

  /// Whisper language hint: 'auto' or an ISO-639-1 code, from the user's
  /// transcription language setting.
  final String language;

  /// When true, whisper.cpp's own translate task is used instead of plain
  /// transcription: it recognizes speech in [language] (or auto-detects it)
  /// but outputs English text directly, rather than transcribing in the
  /// original language - from AppSettings.translateToEnglish.
  final bool translateToEnglish;

  @override
  Future<void> ensureModelReady({void Function(double? fraction)? onProgress}) async {
    _lifecycleManager?.beginUse(ModelKind.speechToText);
    _active = true;
    try {
      await _ensureModelDownloaded(null, onProgress);
    } finally {
      _active = false;
      _lifecycleManager?.endUse(ModelKind.speechToText);
    }
  }

  /// Downloads a specific [model] size, independent of whichever one is
  /// currently the active engine - used by onboarding to let a user fetch
  /// more than one size up front (e.g. Small now, Base as a fallback),
  /// so switching between already-downloaded sizes later in Settings is
  /// instant instead of triggering a fresh download mid-transcription.
  ///
  /// [downloadService] is injectable for tests (`FakeModelDownloadService`)
  /// - defaults to a real [HttpModelDownloadService], matching the same
  /// pattern `ModelDownloadController` already uses for the LLM/embedding
  /// Model Manager downloads.
  static Future<void> ensureModelDownloaded(
    WhisperModel model, {
    void Function(double? fraction)? onProgress,
    ModelDownloadService? downloadService,
  }) =>
      _downloadModelFile(model, onProgress, downloadService: downloadService);

  /// Whether [model]'s file is already on disk (no network check).
  static Future<bool> isModelDownloaded(WhisperModel model) async {
    if (model == WhisperModel.none) return true;
    final modelDir = await whisperModelDirectory();
    return File(model.getPath(modelDir.path)).exists();
  }

  @override
  Future<TranscriptionResult> transcribe(
    String audioFilePath, {
    void Function()? onPreparingModel,
  }) async {
    _lifecycleManager?.beginUse(ModelKind.speechToText);
    _active = true;
    try {
      return await _transcribe(audioFilePath, onPreparingModel: onPreparingModel);
    } finally {
      _active = false;
      _lifecycleManager?.endUse(ModelKind.speechToText);
    }
  }

  Future<TranscriptionResult> _transcribe(
    String audioFilePath, {
    void Function()? onPreparingModel,
  }) async {
    await _ensureModelDownloaded(onPreparingModel, null);

    final wavPath = await _convertToWav(audioFilePath);
    try {
      final audioDuration = estimateWavDuration(await File(wavPath).length());
      final timeout = transcriptionTimeoutFor(audioDuration);

      final WhisperTranscribeResponse response;
      try {
        response = await _whisper
            .transcribe(
              transcribeRequest: TranscribeRequest(
                audio: wavPath,
                isTranslate: translateToEnglish,
                isNoTimestamps: false,
                splitOnWord: false,
                language: language,
              ),
            )
            .timeout(timeout);
      } on TimeoutException {
        // No native cancellation is possible here (see
        // WhisperTranscriptionTimeoutException's doc comment) - the
        // spawned isolate is simply abandoned and will free itself once
        // whisper.cpp eventually returns or the app process exits,
        // mirroring the UI-level "abandon" semantics already established
        // for chat generation (ADR-027). What matters for this bug is
        // that the *meeting* is no longer left showing "Transcribing 45%"
        // forever: throwing here lets TranscribeMeetingUseCase's existing
        // catch-all mark the meeting MeetingStatus.error with a
        // diagnosable message, which unblocks its existing Retry action.
        throw WhisperTranscriptionTimeoutException(
          'Transcription stalled and was stopped after ${timeout.inMinutes} '
          'minutes. This can happen on a very slow or overloaded device - '
          'try again, or pick a smaller Whisper model in Settings > AI '
          'Models.',
        );
      }

      final segments = (response.segments ?? [])
          .map(
            (s) => TranscriptSegment(
              startMs: s.fromTs.inMilliseconds,
              endMs: s.toTs.inMilliseconds,
              text: s.text.trim(),
            ),
          )
          .toList();

      return TranscriptionResult(
        language: 'en',
        fullText: response.text.trim(),
        segments: segments,
      );
    } finally {
      final wavFile = File(wavPath);
      if (await wavFile.exists()) {
        await wavFile.delete();
      }
    }
  }

  Future<void> _ensureModelDownloaded(
    void Function()? onPreparingModel,
    void Function(double? fraction)? onProgress,
  ) async {
    if (model == WhisperModel.none) return;
    if (!await isModelDownloaded(model)) onPreparingModel?.call();
    await _downloadModelFile(model, onProgress);
  }

  /// Real-device beta fix (Phase 9): previously a hand-rolled download loop
  /// that (a) never sent a `Range` header, so a retry after ANY
  /// interruption re-fetched the whole file instead of resuming, and (b)
  /// deleted the `.part` file on any failure, including a network stall or
  /// the OS suspending the app while backgrounded - confirmed on a real
  /// Android phone: start download, background the app, return, and the
  /// download had restarted from byte 0. Now delegates to
  /// [ModelDownloadService] - the same Range-resume, `ETag`/`Last-Modified`
  /// validated, stall-timeout-protected implementation the Model
  /// Manager's LLM/embedding downloads already use
  /// (`ModelDownloadController`) - rather than a second, independently
  /// broken download implementation. A future call (whether a user-tapped
  /// "Retry" or the app simply being reopened) resumes automatically: the
  /// `.part` file left on disk by the interrupted attempt is exactly what
  /// [ModelDownloadService.download] looks for on its next invocation.
  static Future<void> _downloadModelFile(
    WhisperModel model,
    void Function(double? fraction)? onProgress, {
    ModelDownloadService? downloadService,
  }) async {
    if (model == WhisperModel.none) return;

    final modelDir = await whisperModelDirectory();
    final modelFile = File(model.getPath(modelDir.path));
    if (await modelFile.exists()) return;

    final url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/'
        'ggml-${model.modelName}.bin';
    final service = downloadService ?? HttpModelDownloadService();
    await service.download(
      url: url,
      destination: modelFile,
      cancelToken: ModelDownloadCancelToken(),
      onProgress: (progress) => onProgress?.call(progress.fraction),
    );
  }

  Future<String> _convertToWav(String sourcePath) async {
    final tempDir = await getTemporaryDirectory();
    final wavPath = p.join(
      tempDir.path,
      '${p.basenameWithoutExtension(sourcePath)}_'
      '${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final command =
        '-y -i "$sourcePath" -ar 16000 -ac 1 -c:a pcm_s16le "$wavPath"';
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (returnCode == null || !ReturnCode.isSuccess(returnCode)) {
      throw Exception(
        'Could not prepare audio for transcription '
        '(ffmpeg exit code: $returnCode).',
      );
    }
    return wavPath;
  }

  /// Estimates a WAV file's audio duration directly from its size, rather
  /// than parsing the header or shelling out to a media-info tool - exact
  /// for [_convertToWav]'s fixed output format (a standard 44-byte header,
  /// 16000 samples/sec, 16-bit, mono), and needs no new dependency. Public
  /// and pure (no native/platform dependency) specifically so it can be
  /// unit-tested without a device - see `test/services/ai/
  /// whisper_speech_to_text_engine_test.dart`.
  @visibleForTesting
  static Duration estimateWavDuration(int fileSizeBytes) {
    const headerBytes = 44;
    const bytesPerSecond = 16000 * 2; // 16kHz sample rate * 16-bit samples
    final dataBytes = fileSizeBytes > headerBytes ? fileSizeBytes - headerBytes : 0;
    return Duration(milliseconds: dataBytes * 1000 ~/ bytesPerSecond);
  }

  /// How long [_transcribe] waits for `Whisper.transcribe()` before
  /// treating it as hung rather than genuinely still working - see
  /// [AppConstants.whisperTranscriptionTimeoutMultiplier]'s doc comment
  /// for why this multiplier and floor were chosen. Public and pure for
  /// the same testability reason as [estimateWavDuration].
  @visibleForTesting
  static Duration transcriptionTimeoutFor(Duration audioDuration) {
    final scaled = audioDuration * AppConstants.whisperTranscriptionTimeoutMultiplier;
    return scaled > AppConstants.whisperTranscriptionTimeoutFloor
        ? scaled
        : AppConstants.whisperTranscriptionTimeoutFloor;
  }
}
