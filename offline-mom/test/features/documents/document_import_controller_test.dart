import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/presentation/providers/document_providers.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/services/documents/document_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_helpers/test_database.dart';

/// Lets a test hold [pickFile] open until it chooses to let it resolve -
/// the only way to reliably create the "two calls in flight at once"
/// window a rapid double-tap would otherwise only produce nondeterministically.
class _SlowFakeDocumentImportService implements DocumentImportService {
  int pickFileCallCount = 0;
  final _pickCompleter = Completer<String?>();

  void completePick(String? path) => _pickCompleter.complete(path);

  @override
  Future<String?> pickFile() {
    pickFileCallCount++;
    return _pickCompleter.future;
  }

  @override
  Future<PreparedDocumentFile> prepareDocumentFile(String pickedFilePath) async {
    throw UnimplementedError('not reached in this test - pickFile never resolves to a path');
  }
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  test(
      'importFile() ignores a second call while one is already in flight '
      '(Phase 8C production-hardening: a rapid double-tap on Import could '
      'previously open the system file picker twice concurrently)',
      () async {
    final fakeService = _SlowFakeDocumentImportService();
    container = ProviderContainer(
      overrides: [
        documentRepositoryProvider.overrideWithValue(documentRepository),
        documentImportServiceProvider.overrideWithValue(fakeService),
      ],
    );
    final notifier = container.read(documentImportControllerProvider.notifier);

    // Both fire before either's `pickFile()` resolves - the exact race a
    // fast double-tap produces, made deterministic instead of timing-dependent.
    final first = notifier.importFile();
    final second = notifier.importFile();

    expect(
      container.read(documentImportControllerProvider),
      isA<DocumentImportProcessing>(),
    );

    fakeService.completePick(null);
    await first;
    await second;

    expect(fakeService.pickFileCallCount, 1);
  });
}
