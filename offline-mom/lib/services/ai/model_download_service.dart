import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'download_progress_throttle.dart';

/// Thrown by [ModelDownloadService.download] on any failure - HTTP error,
/// stall, or a cooperative cancellation that wasn't a pause (see
/// [ModelDownloadCancelToken]'s doc comment for the pause/cancel
/// distinction).
class ModelDownloadException implements Exception {
  ModelDownloadException(this.message, {this.wasCancelled = false});
  final String message;

  /// True when this exception represents a user-requested pause/cancel
  /// (via [ModelDownloadCancelToken.cancel]) rather than a real failure -
  /// callers use this to decide whether to show an error banner (false) or
  /// just quietly reflect "paused" state (true).
  final bool wasCancelled;

  @override
  String toString() => message;
}

/// A cooperative cancel signal for an in-flight [ModelDownloadService
/// .download] call. Deliberately this app's own type, not `llamadart`'s
/// `ModelDownloadCancelToken` - Whisper/OCR/Vision/Translation downloads
/// never go through `llamadart`, so a shared token type would create a
/// dependency in the wrong direction (`lib/services/ai/` depending on a
/// third-party package's cancellation type for kinds that package never
/// touches).
///
/// **Pause vs. cancel, the one distinction that matters for Model Safety
/// (ADR-036):** calling [cancel] always leaves the `.part` file and its
/// resume metadata on disk - "pause" and "cancel" are the same signal to
/// the download loop itself; the *caller* decides which the user meant.
/// [ModelDownloadController.pause] just calls [cancel] and stops there
/// (resumable later). [ModelDownloadController.cancelAndDiscard] calls
/// [cancel] and then explicitly deletes the partial file afterward via
/// [ModelDownloadService.deletePartialDownload] - so a `.part` file with
/// no corresponding intent to resume it never lingers as orphan cache
/// longer than that one explicit follow-up call.
class ModelDownloadCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Progress snapshot passed to [ModelDownloadService.download]'s
/// `onProgress` callback.
class ModelDownloadProgress {
  const ModelDownloadProgress({required this.receivedBytes, required this.totalBytes});

  final int receivedBytes;

  /// Null if the server never reported a `Content-Length`/`Content-Range`
  /// total - callers show an indeterminate progress indicator in that case
  /// (same convention as `_DownloadProgressRow` in `model_setup_screen
  /// .dart`, reused verbatim by the new Model Manager UI).
  final int? totalBytes;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

/// The completed download's measured facts - what
/// [InstalledModelRepository] actually persists, distinct from
/// [AiModelSpec]'s upfront approximation.
class ModelDownloadOutcome {
  const ModelDownloadOutcome({required this.sizeBytes, required this.sha256Hex});
  final int sizeBytes;

  /// Hex-encoded SHA-256 of the fully downloaded file, computed
  /// incrementally during the download (never a second full-file re-read)
  /// - see [InstalledModel.localSha256]'s doc comment for what this can
  /// and can't prove.
  final String sha256Hex;
}

/// Downloads a single model file to [destination], with resume-after-
/// interruption, progress reporting, and a local integrity fingerprint -
/// the shared primitive Whisper model downloads use from Phase 6A onward
/// (replacing the hand-rolled, non-resumable logic
/// `WhisperSpeechToTextEngine._downloadModelFile` had before). The LLM and
/// embedding models are **not** routed through this - `llamadart`'s own
/// `ModelSource`/`ModelDownloadManager` already does real HTTP-range
/// resume internally (confirmed by direct source inspection, ADR-036) and
/// reimplementing that would be a pure regression, not an improvement; see
/// `LlamaDartLlmEngine`/`LlamaDartEmbeddingEngine` for how those two kinds
/// instead expose a cancel/resume seam directly on the engine.
abstract class ModelDownloadService {
  /// Downloads `url` into `${destination.path}.part`, resuming from any
  /// existing `.part` file for the same [destination] (validated by a
  /// stored `ETag`/`Last-Modified` sidecar - see [buildRangeHeaderValue]/
  /// [validatorsCompatible]), then atomically renames it into place.
  /// Throws [ModelDownloadException] on any failure, including a
  /// cancellation via [cancelToken] (with [ModelDownloadException
  /// .wasCancelled] `true` in that case) - the `.part` file and its
  /// sidecar are left in place on any exception except a fully successful
  /// download (real corruption safety: [destination] itself is only ever
  /// written by the final atomic rename of a fully-received file, so a
  /// caller can never observe a half-written [destination]).
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  });

  /// True if a resumable `.part` file exists for [destination] - drives
  /// whether the UI offers "Resume" or "Download".
  Future<bool> hasPartialDownload(File destination);

  /// Deletes any `.part` file/sidecar for [destination] without attempting
  /// to resume - see [ModelDownloadCancelToken]'s doc comment for when
  /// this is (and isn't) called.
  Future<void> deletePartialDownload(File destination);
}

String _partPath(File destination) => '${destination.path}.part';
String _sidecarPath(File destination) => '${destination.path}.part.json';

/// Builds the `Range` header value to resume from [existingBytes] - `null`
/// when there's nothing to resume from (a fresh download). Extracted as a
/// pure function (no `dart:io` dependency) so the resume decision itself
/// is unit-testable without a real socket - the same "pull the pure logic
/// out of the untestable I/O shell" discipline `PdfPageRenderingService`
/// already applies to `Printing.raster()` (Phase 5B, R-32).
String? buildRangeHeaderValue(int existingBytes) =>
    existingBytes > 0 ? 'bytes=$existingBytes-' : null;

/// Whether a stored resume validator (`ETag` or `Last-Modified` from the
/// original, interrupted response) still matches what the server reports
/// now - if not, the server-side file changed since the partial download
/// started, and resuming would silently splice two different files
/// together (real corruption). A `null` stored validator (no sidecar,
/// e.g. this is the very first attempt) is never "compatible" - callers
/// must treat a missing sidecar as "start fresh", not "resume unconditionally".
bool validatorsCompatible(String? stored, String? current) {
  if (stored == null || current == null) return false;
  return stored == current;
}

class HttpModelDownloadService implements ModelDownloadService {
  // R-11 P0 fix: 45s was too aggressive for a real Android device - a
  // normal "lock the phone for a minute" during a large model download
  // easily exceeds it, since this app has no foreground service keeping
  // the connection alive while backgrounded (AppSettings
  // .allowBackgroundDownloads defaults to false). The `.part` file/sidecar
  // are always preserved regardless of this value (see `download`'s own
  // doc comment) - this only controls how long a genuinely idle connection
  // is given before the attempt is cooperatively cancelled, not whether
  // resume works.
  HttpModelDownloadService({Duration? stallTimeout})
      : _stallTimeout = stallTimeout ?? const Duration(minutes: 3);

  final Duration _stallTimeout;

  @override
  Future<bool> hasPartialDownload(File destination) => File(_partPath(destination)).exists();

  @override
  Future<void> deletePartialDownload(File destination) async {
    final part = File(_partPath(destination));
    final sidecar = File(_sidecarPath(destination));
    if (await part.exists()) await part.delete();
    if (await sidecar.exists()) await sidecar.delete();
  }

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    final partFile = File(_partPath(destination));
    final sidecarFile = File(_sidecarPath(destination));

    var existingBytes = 0;
    String? storedValidator;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
      if (await sidecarFile.exists()) {
        try {
          final decoded = jsonDecode(await sidecarFile.readAsString()) as Map<String, dynamic>;
          storedValidator = decoded['validator'] as String?;
        } catch (_) {
          // A corrupted sidecar is treated the same as a missing one -
          // start this partial file over rather than risk splicing.
          storedValidator = null;
        }
      }
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    final hashSink = AccumulatorSink<Digest>();
    final hashInput = sha256.startChunkedConversion(hashSink);
    final throttle = ProgressThrottle();
    Timer? stallTimer;
    void resetStallTimer(void Function() onStall) {
      stallTimer?.cancel();
      stallTimer = Timer(_stallTimeout, onStall);
    }

    // R-11 P0 fix - a real bug found while adding this pass's own
    // regression test: `await for (final chunk in response)` only checks
    // `cancelToken.isCancelled` at the top of each loop iteration, which
    // only runs once a *new* chunk arrives. On a genuinely stalled
    // connection (the server accepts the connection but sends nothing
    // further - exactly what happens when this app is backgrounded with no
    // foreground service keeping the socket alive), no further chunk ever
    // arrives, so the loop blocks on the stream forever and merely setting
    // `cancelToken`'s flag from the stall timer has no effect at all - the
    // "stall timeout" was silently a no-op for the one scenario it exists
    // to handle. Force-closing the client actually unblocks the stalled
    // read (the response stream errors out), which is what actually lets
    // the loop exit and this method report a paused/resumable state
    // instead of hanging indefinitely with no error, no pause state, and no
    // progress update ever again.
    void onStall() {
      cancelToken.cancel();
      client.close(force: true);
    }

    // Real-device beta fix (Phase 9): diagnostics specifically requested for
    // beta testing - the exact request/response facts that decide whether a
    // download resumes or restarts, printed via debugPrint (visible in
    // `flutter logs`/Logcat on a real device, unlike a silent decision
    // baked into a boolean). Never gated behind kDebugMode - a beta APK is
    // still a release build, and this is exactly the build these
    // diagnostics need to be visible in.
    debugPrint(
      '[ModelDownload] request: url=$url existingPartialBytes=$existingBytes '
      'storedValidator=${storedValidator ?? "(none)"}',
    );
    try {
      final rangeHeader = buildRangeHeaderValue(existingBytes);
      final request = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (rangeHeader != null) request.headers.set(HttpHeaders.rangeHeader, rangeHeader);
      debugPrint('[ModelDownload] Range header sent: ${rangeHeader ?? "(none - fresh download)"}');
      final response = await request.close().timeout(const Duration(seconds: 30));

      final serverValidator = response.headers.value(HttpHeaders.etagHeader) ??
          response.headers.value(HttpHeaders.lastModifiedHeader);
      final isResuming = response.statusCode == 206 &&
          rangeHeader != null &&
          validatorsCompatible(storedValidator, serverValidator);
      debugPrint(
        '[ModelDownload] response: HTTP ${response.statusCode} '
        'contentRange=${response.headers.value(HttpHeaders.contentRangeHeader) ?? "(none)"} '
        'contentLength=${response.contentLength} '
        'serverValidator=${serverValidator ?? "(none)"} '
        'decision=${isResuming ? "RESUME (append from byte $existingBytes)" : "FRESH (overwrite from byte 0)"}',
      );

      IOSink raf;
      int startingBytes;
      if (isResuming) {
        raf = partFile.openWrite(mode: FileMode.append);
        startingBytes = existingBytes;
        // Re-seed the running hash with the bytes already on disk from the
        // prior attempt, so the final hash covers the whole file, not just
        // the bytes received in this resumed call.
        final alreadyOnDisk = await partFile.readAsBytes();
        hashInput.add(alreadyOnDisk.sublist(0, startingBytes));
      } else if (response.statusCode == 200) {
        // Either a fresh download, or the server didn't honor our Range
        // request (some CDNs don't) - start clean rather than risk
        // corrupting a file the server is sending from byte 0 anyway.
        if (rangeHeader != null) {
          debugPrint(
            '[ModelDownload] server returned 200 (not 206) despite a Range request - '
            'it does not support Range/resume for this URL, or the stored validator no '
            'longer matches; starting fresh rather than risking a spliced file.',
          );
        }
        raf = partFile.openWrite(mode: FileMode.write);
        startingBytes = 0;
      } else {
        throw ModelDownloadException(
          'Model download failed (HTTP ${response.statusCode}). Check your internet '
          'connection and try again.',
        );
      }

      if (serverValidator != null) {
        await sidecarFile.writeAsString(jsonEncode({'validator': serverValidator}));
      }

      final contentLength = response.contentLength >= 0 ? response.contentLength : null;
      final totalBytes = contentLength == null
          ? null
          : (isResuming ? startingBytes + contentLength : contentLength);

      var receivedBytes = startingBytes;
      resetStallTimer(onStall);

      try {
        await for (final chunk in response) {
          if (cancelToken.isCancelled) {
            throw ModelDownloadException('Download paused.', wasCancelled: true);
          }
          raf.add(chunk);
          hashInput.add(chunk);
          receivedBytes += chunk.length;
          resetStallTimer(onStall);
          if (throttle.shouldEmit()) {
            onProgress?.call(ModelDownloadProgress(receivedBytes: receivedBytes, totalBytes: totalBytes));
          }
        }
      } finally {
        stallTimer?.cancel();
        await raf.flush();
        await raf.close();
      }

      if (cancelToken.isCancelled) {
        throw ModelDownloadException('Download paused.', wasCancelled: true);
      }

      // The response stream can close cleanly (no exception) after fewer
      // bytes than the server itself advertised - a real, observed failure
      // mode for a dropped/throttled mobile connection, not merely a
      // stream error. Without this check the truncated `.part` file would
      // be renamed into place as if it were a complete, valid download.
      // Leaving `.part` on disk here (instead of renaming) means the next
      // attempt resumes from `receivedBytes`, exactly like any other
      // failure this method already treats as resumable.
      if (totalBytes != null && receivedBytes != totalBytes) {
        throw ModelDownloadException(
          'Download ended early ($receivedBytes of $totalBytes bytes received). '
          'Check your internet connection and try again.',
        );
      }

      hashInput.close();
      final digest = hashSink.events.single;

      await partFile.rename(destination.path);
      if (await sidecarFile.exists()) await sidecarFile.delete();

      debugPrint(
        '[ModelDownload] complete: destination=${destination.path} totalBytes=$receivedBytes '
        'sha256=${digest.toString().substring(0, 12)}…',
      );
      onProgress?.call(ModelDownloadProgress(receivedBytes: receivedBytes, totalBytes: receivedBytes));
      return ModelDownloadOutcome(sizeBytes: receivedBytes, sha256Hex: digest.toString());
    } on ModelDownloadException catch (e) {
      debugPrint('[ModelDownload] stopped (partial file preserved unless wasCancelled+discarded '
          'by caller): wasCancelled=${e.wasCancelled} message=${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('[ModelDownload] failed with an unexpected error (partial file preserved): $e');
      // R-11 P0 fix: `onStall`'s forced client close is what actually
      // unblocks a genuinely stalled `await for` read (see that function's
      // own doc comment) - doing so makes the response stream throw here,
      // in this generic catch, not as a clean `ModelDownloadException` from
      // inside the loop. Attributing it correctly (rather than a raw
      // "failed" message) is what lets a caller show "paused, tap to
      // resume" instead of a scary error for exactly the case this stall
      // timer exists to handle.
      if (cancelToken.isCancelled) {
        throw ModelDownloadException('Download paused.', wasCancelled: true);
      }
      throw ModelDownloadException('Model download failed: $e');
    } finally {
      client.close(force: true);
    }
  }
}

/// Test double for [ModelDownloadService] - synthetic progress, no real
/// I/O, mirrors [FakePdfPageRenderingService]'s exact role (Phase 5B): the
/// one seam in this feature genuinely untestable under `flutter test`
/// (real sockets), replaced with a deterministic fake everywhere else
/// (controllers, repository-integration tests) depends on it.
class FakeModelDownloadService implements ModelDownloadService {
  FakeModelDownloadService({this.chunkCount = 4, this.failWith, this.bytesPerChunk = 1024});

  /// How many synthetic progress events to emit before completing.
  final int chunkCount;
  final int bytesPerChunk;

  /// If set, [download] throws this instead of succeeding.
  final ModelDownloadException? failWith;

  final Set<String> _partialsWritten = {};

  @override
  Future<bool> hasPartialDownload(File destination) async => _partialsWritten.contains(destination.path);

  @override
  Future<void> deletePartialDownload(File destination) async {
    _partialsWritten.remove(destination.path);
  }

  @override
  Future<ModelDownloadOutcome> download({
    required String url,
    required File destination,
    required ModelDownloadCancelToken cancelToken,
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    final total = chunkCount * bytesPerChunk;
    var received = 0;
    for (var i = 0; i < chunkCount; i++) {
      if (cancelToken.isCancelled) {
        _partialsWritten.add(destination.path);
        throw ModelDownloadException('Download paused.', wasCancelled: true);
      }
      await Future<void>.delayed(Duration.zero);
      received += bytesPerChunk;
      onProgress?.call(ModelDownloadProgress(receivedBytes: received, totalBytes: total));
    }

    final failure = failWith;
    if (failure != null) {
      _partialsWritten.add(destination.path);
      throw failure;
    }

    _partialsWritten.remove(destination.path);
    await destination.parent.create(recursive: true);
    await destination.writeAsString('fake-model-bytes');
    return ModelDownloadOutcome(sizeBytes: total, sha256Hex: 'fake-sha256-$url'.hashCode.toRadixString(16));
  }
}
