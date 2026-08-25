import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/ai/model_download_service.dart';

void main() {
  group('buildRangeHeaderValue (pure logic)', () {
    test('returns null for zero bytes (fresh download)', () {
      expect(buildRangeHeaderValue(0), isNull);
    });

    test('returns a bytes=N- header for a positive existing size', () {
      expect(buildRangeHeaderValue(1024), 'bytes=1024-');
    });
  });

  group('validatorsCompatible (pure logic)', () {
    test('false when either side is null', () {
      expect(validatorsCompatible(null, 'etag-1'), isFalse);
      expect(validatorsCompatible('etag-1', null), isFalse);
      expect(validatorsCompatible(null, null), isFalse);
    });

    test('true only when both validators match exactly', () {
      expect(validatorsCompatible('etag-1', 'etag-1'), isTrue);
      expect(validatorsCompatible('etag-1', 'etag-2'), isFalse);
    });
  });

  group('FakeModelDownloadService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('model_download_service_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('download() reports progress and writes the destination file', () async {
      final service = FakeModelDownloadService(chunkCount: 3, bytesPerChunk: 100);
      final destination = File('${tempDir.path}/model.bin');
      final progressEvents = <ModelDownloadProgress>[];

      final outcome = await service.download(
        url: 'https://example.invalid/model.bin',
        destination: destination,
        cancelToken: ModelDownloadCancelToken(),
        onProgress: progressEvents.add,
      );

      expect(await destination.exists(), isTrue);
      expect(progressEvents, hasLength(3));
      expect(progressEvents.last.fraction, 1.0);
      expect(outcome.sizeBytes, 300);
      expect(await service.hasPartialDownload(destination), isFalse);
    });

    test('cancelling mid-download throws a cancelled exception and marks a partial', () async {
      final service = FakeModelDownloadService(chunkCount: 5, bytesPerChunk: 100);
      final destination = File('${tempDir.path}/model2.bin');
      final cancelToken = ModelDownloadCancelToken();

      var calls = 0;
      await expectLater(
        service.download(
          url: 'https://example.invalid/model.bin',
          destination: destination,
          cancelToken: cancelToken,
          onProgress: (_) {
            calls++;
            if (calls == 2) cancelToken.cancel();
          },
        ),
        throwsA(isA<ModelDownloadException>().having((e) => e.wasCancelled, 'wasCancelled', isTrue)),
      );

      expect(await service.hasPartialDownload(destination), isTrue);
      expect(await destination.exists(), isFalse);
    });

    test('deletePartialDownload clears the tracked partial state', () async {
      final service = FakeModelDownloadService(failWith: ModelDownloadException('boom'));
      final destination = File('${tempDir.path}/model3.bin');

      await expectLater(
        service.download(
          url: 'https://example.invalid/model.bin',
          destination: destination,
          cancelToken: ModelDownloadCancelToken(),
        ),
        throwsA(isA<ModelDownloadException>()),
      );
      expect(await service.hasPartialDownload(destination), isTrue);

      await service.deletePartialDownload(destination);
      expect(await service.hasPartialDownload(destination), isFalse);
    });
  });

  group('HttpModelDownloadService against a real local loopback server', () {
    late Directory tempDir;
    late HttpServer server;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('http_model_download_service_test_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    });

    tearDown(() async {
      await server.close(force: true);
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('a full, correctly-sized response is written to destination and reports a matching size',
        () async {
      final bytes = List<int>.generate(1000, (i) => i % 256);
      server.listen((request) {
        request.response.headers.contentLength = bytes.length;
        request.response.add(bytes);
        request.response.close();
      });

      final service = HttpModelDownloadService();
      final destination = File('${tempDir.path}/model.bin');

      final outcome = await service.download(
        url: 'http://${server.address.address}:${server.port}/model.bin',
        destination: destination,
        cancelToken: ModelDownloadCancelToken(),
      );

      expect(outcome.sizeBytes, bytes.length);
      expect(await destination.exists(), isTrue);
      expect(await destination.readAsBytes(), bytes);
      expect(await service.hasPartialDownload(destination), isFalse);
    });

    test(
        'a response that closes early (fewer bytes than Content-Length) throws instead of '
        'silently accepting a truncated file - regression test for a real bug where the '
        '.part file was renamed into place without verifying the full byte count was received',
        () async {
      server.listen((request) async {
        // Write a raw response below dart:io's HttpResponse abstraction
        // (which would otherwise refuse to close() having written fewer
        // bytes than its own declared Content-Length) - this is the only
        // way to genuinely simulate what a dropped/throttled mobile
        // connection looks like on the wire: a Content-Length header
        // promising 1000 bytes, but the socket closing after only 500.
        final socket = await request.response.detachSocket();
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 1000\r\nConnection: close\r\n\r\n');
        socket.add(List<int>.filled(500, 7));
        await socket.flush();
        await socket.close();
      });

      final service = HttpModelDownloadService();
      final destination = File('${tempDir.path}/model.bin');

      await expectLater(
        service.download(
          url: 'http://${server.address.address}:${server.port}/model.bin',
          destination: destination,
          cancelToken: ModelDownloadCancelToken(),
        ),
        throwsA(isA<ModelDownloadException>()),
      );

      // The truncated file must never be renamed into the final destination.
      expect(await destination.exists(), isFalse);
      // The partial bytes stay on disk so a retry can resume from them,
      // exactly like every other failure mode this service treats as
      // resumable.
      expect(await service.hasPartialDownload(destination), isTrue);
    });

    test(
      'Part E (multi-model management, product-quality remediation pass): a download interrupted '
      'partway through - the common real-world case is the app being killed/crashing mid-download, '
      'leaving a real .part file plus its validator sidecar on disk from before this run even '
      'started - resumes correctly on the next attempt: the request sends a Range header for '
      'exactly the bytes already on disk, the server responds 206 with a matching validator, and '
      'the final file is the byte-for-byte splice of the pre-existing partial plus the '
      'newly-received bytes, not a re-download from byte 0',
      () async {
        const etag = '"stable-etag-v1"';
        final fullBytes = List<int>.generate(1000, (i) => i % 256);
        const alreadyOnDiskCount = 400;
        String? requestedRange;

        server.listen((request) async {
          requestedRange = request.headers.value(HttpHeaders.rangeHeader);
          final range = requestedRange;
          if (range == null) {
            fail('expected a Range request - a pre-existing .part file was on disk before this '
                'download() call started');
          }
          final requestedFrom = int.parse(range.replaceFirst('bytes=', '').replaceFirst('-', ''));
          final remaining = fullBytes.sublist(requestedFrom);
          request.response
            ..statusCode = 206
            ..headers.contentLength = remaining.length
            ..headers.set(HttpHeaders.etagHeader, etag)
            ..add(remaining);
          await request.response.close();
        });

        final service = HttpModelDownloadService();
        final destination = File('${tempDir.path}/model.bin');
        final url = 'http://${server.address.address}:${server.port}/model.bin';

        // Simulates a prior run that was interrupted (app killed, device
        // restarted, connection lost) after writing exactly
        // alreadyOnDiskCount bytes - the exact on-disk state this service's
        // own download() finds and reads on its next call, regardless of
        // why the prior attempt stopped.
        await File('${destination.path}.part').writeAsBytes(fullBytes.sublist(0, alreadyOnDiskCount));
        await File('${destination.path}.part.json').writeAsString(jsonEncode({'validator': etag}));
        expect(await service.hasPartialDownload(destination), isTrue);

        final outcome = await service.download(
          url: url,
          destination: destination,
          cancelToken: ModelDownloadCancelToken(),
        );

        expect(requestedRange, 'bytes=$alreadyOnDiskCount-');
        expect(outcome.sizeBytes, fullBytes.length);
        expect(await destination.readAsBytes(), fullBytes);
        expect(await service.hasPartialDownload(destination), isFalse);
      },
    );

    test(
      'Part E: if the server-side file changed since the partial was left on disk (a different '
      'ETag), the retry does NOT splice - it discards the stale partial and re-downloads fresh, '
      'never producing a corrupted file from mismatched halves',
      () async {
        final newFullBytes = List<int>.generate(600, (i) => i % 256);

        server.listen((request) async {
          // Server now reports a different ETag (the remote file changed) -
          // per validatorsCompatible, this must NOT be treated as resumable
          // even though a Range header was sent and a pre-existing partial
          // exists on disk with a different, now-stale validator.
          request.response
            ..statusCode = 200
            ..headers.contentLength = newFullBytes.length
            ..headers.set(HttpHeaders.etagHeader, '"v2"')
            ..add(newFullBytes);
          await request.response.close();
        });

        final service = HttpModelDownloadService();
        final destination = File('${tempDir.path}/model.bin');
        final url = 'http://${server.address.address}:${server.port}/model.bin';

        await File('${destination.path}.part').writeAsBytes(List<int>.filled(400, 1));
        await File('${destination.path}.part.json').writeAsString('{"validator": "v1"}');

        final outcome = await service.download(
          url: url,
          destination: destination,
          cancelToken: ModelDownloadCancelToken(),
        );

        expect(outcome.sizeBytes, newFullBytes.length);
        expect(await destination.readAsBytes(), newFullBytes);
      },
    );

    test(
      'R-11 P0 regression: a stalled connection (no bytes arriving, e.g. the app was '
      'backgrounded with no foreground service keeping the socket alive) is cooperatively '
      'cancelled as a PAUSE, not a hard failure, and preserves the partial bytes for the next '
      'attempt to resume from - never silently pretends the bytes never existed',
      () async {
        final firstChunk = List<int>.filled(300, 9);
        const totalBytes = 1000;
        final chunkSent = Completer<void>();

        server.listen((request) async {
          request.response.headers.contentLength = totalBytes;
          request.response.add(firstChunk);
          await request.response.flush();
          chunkSent.complete();
          // Deliberately never sends the rest and never closes - simulates
          // the connection going idle mid-download (backgrounded app, no
          // foreground service, Android throttling network I/O) rather than
          // a clean server-side close.
        });

        // A short stall timeout so this test doesn't need to wait minutes -
        // the production default (bumped by this pass, see the constructor's
        // own doc comment) is 3 minutes; only the mechanism is under test
        // here, not the exact production duration.
        final service = HttpModelDownloadService(stallTimeout: const Duration(milliseconds: 150));
        final destination = File('${tempDir.path}/model.bin');

        await expectLater(
          service.download(
            url: 'http://${server.address.address}:${server.port}/model.bin',
            destination: destination,
            cancelToken: ModelDownloadCancelToken(),
          ),
          throwsA(isA<ModelDownloadException>().having((e) => e.wasCancelled, 'wasCancelled', isTrue)),
        );

        await chunkSent.future;
        // The final destination is never written to on a paused/incomplete
        // attempt - only the .part file, which the next attempt's Range
        // request resumes from (proven by the splice test above).
        expect(await destination.exists(), isFalse);
        expect(await service.hasPartialDownload(destination), isTrue);
      },
    );
  });
}
