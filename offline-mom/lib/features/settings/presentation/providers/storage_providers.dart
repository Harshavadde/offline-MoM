import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../providers/app_providers.dart';

class StorageInfo {
  const StorageInfo({
    required this.recordingsBytes,
    required this.recordingsCount,
    required this.toolkitBytes,
    required this.toolkitCount,
    required this.documentsBytes,
    required this.documentsCount,
    required this.databaseBytes,
    this.cacheBytes = 0,
    this.backupsBytes = 0,
  });

  final int recordingsBytes;
  final int recordingsCount;

  /// Productivity Toolkit outputs (`toolkit/`, V2 Phase 5A) - saved
  /// compressed/resized images.
  final int toolkitBytes;
  final int toolkitCount;

  /// Imported documents (`documents/`, Phase 1A) - closes a pre-existing gap
  /// (R-30, docs/v2/implementation/04-risk-register.md) where this
  /// directory was never counted anywhere in Storage (Phase 7B, item 7).
  final int documentsBytes;
  final int documentsCount;
  final int databaseBytes;
  final int cacheBytes;
  final int backupsBytes;

  int get totalBytes =>
      recordingsBytes + toolkitBytes + documentsBytes + databaseBytes + cacheBytes + backupsBytes;
}

/// Real on-device usage - sums every directory this app actually writes
/// user data to that this screen currently tracks (no estimate/placeholder).
final storageInfoProvider = FutureProvider<StorageInfo>((ref) async {
  final docsDir = await getApplicationDocumentsDirectory();

  Future<(int bytes, int count)> sumDir(String subfolder) async {
    final dir = Directory(p.join(docsDir.path, subfolder));
    if (!await dir.exists()) return (0, 0);
    var bytes = 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        bytes += await entity.length();
        count++;
      }
    }
    return (bytes, count);
  }

  final (recordingsBytes, recordingsCount) = await sumDir('recordings');
  final (toolkitBytes, toolkitCount) = await sumDir('toolkit');
  final (documentsBytes, documentsCount) = await sumDir('documents');

  final dbPath = ref.watch(appDatabaseProvider).db.path;
  final dbFile = File(dbPath);
  final databaseBytes = await dbFile.exists() ? await dbFile.length() : 0;

  final tempDir = await getTemporaryDirectory();
  var cacheBytes = 0;
  var backupsBytes = 0;
  if (await tempDir.exists()) {
    await for (final entity in tempDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.wav')) cacheBytes += await entity.length();
      if (name.startsWith('offline_mom_backup_') && name.endsWith('.db')) {
        backupsBytes += await entity.length();
      }
    }
  }

  return StorageInfo(
    recordingsBytes: recordingsBytes,
    recordingsCount: recordingsCount,
    toolkitBytes: toolkitBytes,
    toolkitCount: toolkitCount,
    documentsBytes: documentsBytes,
    documentsCount: documentsCount,
    databaseBytes: databaseBytes,
    cacheBytes: cacheBytes,
    backupsBytes: backupsBytes,
  );
});

/// Deletes any leftover temp files this app is the sole owner of: whisper-
/// conversion `.wav` files (each transcription normally cleans up its own,
/// but a crash mid-transcribe can leave one behind) and `offline_mom_backup_
/// *.db` files (`BackupScreen._exportBackup` now deletes its own as soon as
/// the share sheet closes, per Phase 4B, but this stays as a safety net for
/// the one path that can't: the app process being killed between writing
/// the copy and that cleanup running). Never touches recordings or the live
/// database, so it's safe to run any time.
Future<int> clearTempTranscodeCache() async {
  final tempDir = await getTemporaryDirectory();
  if (!await tempDir.exists()) return 0;

  var deleted = 0;
  await for (final entity in tempDir.list()) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    final isLeftoverTranscode = name.endsWith('.wav');
    final isLeftoverBackup =
        name.startsWith('offline_mom_backup_') && name.endsWith('.db');
    if (isLeftoverTranscode || isLeftoverBackup) {
      await entity.delete();
      deleted++;
    }
  }
  return deleted;
}
