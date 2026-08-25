import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/utils/ai_model_paths.dart';

/// AI Model Manager Storage Usage breakdown (Phase 6A objective 10) -
/// mirrors `StorageInfo`/`storageInfoProvider`'s shape
/// (`features/settings/presentation/providers/storage_providers.dart`,
/// Phase 4B) but deliberately a **separate** provider, not an extension of
/// that one: model files live outside `getApplicationDocumentsDirectory()`
/// (`llamadart`'s own cache root, and `getApplicationSupportDirectory()`
/// for Whisper - see [ModelDownloadService]'s doc comment), so summing
/// them into the same flat total would misrepresent where the bytes
/// actually are, and `storageInfoProvider`'s `sumDir` helper assumes a
/// flat (non-recursive) directory, which `llamadart`'s cache root (one
/// subdirectory per model) is not.
class ModelStorageInfo {
  const ModelStorageInfo({
    required this.whisperModelsBytes,
    required this.llmEmbeddingCacheBytes,
    required this.partialDownloadBytes,
  });

  /// Sum of every `ggml-*.bin` file actually installed.
  final int whisperModelsBytes;

  /// Sum of everything under `llamadart`'s own cache root (LLM + embedding
  /// models together - see [ModelStorageInfo]'s "what 'Delete Cache' does"
  /// note below; `llamadart` doesn't expose a way to attribute bytes to
  /// one specific model within that root, only the root's total).
  final int llmEmbeddingCacheBytes;

  /// `.part`/`.part.json` files - in-progress or abandoned downloads, not
  /// yet a usable model. Surfaced separately ("Temporary Downloads", Phase
  /// 6A objective 10) so a stalled download doesn't silently masquerade as
  /// real, usable storage.
  final int partialDownloadBytes;

  int get totalBytes => whisperModelsBytes + llmEmbeddingCacheBytes + partialDownloadBytes;
}

Future<int> _sumDirRecursive(Directory dir) async {
  if (!await dir.exists()) return 0;
  var bytes = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        bytes += await entity.length();
      } catch (_) {
        // A file removed mid-scan (e.g. a download completing concurrently)
        // is not a reason to fail the whole storage computation.
      }
    }
  }
  return bytes;
}

/// `llamadart`'s own cache root - the same default `DefaultModelDownloadManager`
/// resolves to internally (confirmed by source inspection, ADR-036), computed
/// independently here purely for Storage Usage display; nothing in this app
/// writes to or otherwise depends on this path being exactly right beyond
/// that display purpose.
Directory llamaModelCacheRoot() => Directory(p.join(Directory.systemTemp.path, 'llamadart', 'models'));

final modelStorageInfoProvider = FutureProvider<ModelStorageInfo>((ref) async {
  final whisperDir = await whisperModelDirectory();

  var whisperBytes = 0;
  var partialBytes = 0;
  if (await whisperDir.exists()) {
    await for (final entity in whisperDir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final length = await entity.length();
      if (name.endsWith('.part') || name.endsWith('.part.json')) {
        partialBytes += length;
      } else if (name.startsWith('ggml-') && name.endsWith('.bin')) {
        whisperBytes += length;
      }
    }
  }

  final llamaCacheBytes = await _sumDirRecursive(llamaModelCacheRoot());

  return ModelStorageInfo(
    whisperModelsBytes: whisperBytes,
    llmEmbeddingCacheBytes: llamaCacheBytes,
    partialDownloadBytes: partialBytes,
  );
});

/// "Delete Cache" (Phase 6A objective 10) - removes every `.part`/
/// `.part.json` orphan under the Whisper model directory and the entire
/// `llamadart` cache root. **Deliberately blunt for the `llamadart` half**:
/// that package exposes no per-model cache-eviction API (confirmed by
/// source inspection, ADR-036), so this clears the LLM *and* embedding
/// model caches together, forcing both to re-download on next use - a
/// real, disclosed trade-off (see the Storage Usage screen's confirmation
/// copy), not a silent limitation. Whisper's own `.bin` files are *not*
/// touched here - deleting an installed Whisper model is
/// `InstalledModelsController.delete`'s job, a precise per-model action
/// this blunt cache clear deliberately doesn't duplicate.
Future<void> clearModelCache() async {
  final whisperDir = await whisperModelDirectory();
  if (await whisperDir.exists()) {
    await for (final entity in whisperDir.list(followLinks: false)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.endsWith('.part') || name.endsWith('.part.json')) {
          await entity.delete();
        }
      }
    }
  }

  final llamaCache = llamaModelCacheRoot();
  if (await llamaCache.exists()) {
    await llamaCache.delete(recursive: true);
  }
}
