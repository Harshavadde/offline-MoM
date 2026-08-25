import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/document_import_use_case.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/repositories/document_repository.dart';
import 'package:offline_mom/services/documents/document_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test_helpers/test_database.dart';

class _FakeDocumentImportService implements DocumentImportService {
  _FakeDocumentImportService({this.pickedPath, this.prepared, this.errorToThrow});

  final String? pickedPath;
  final PreparedDocumentFile? prepared;
  final Object? errorToThrow;

  @override
  Future<String?> pickFile() async => pickedPath;

  @override
  Future<PreparedDocumentFile> prepareDocumentFile(String pickedFilePath) async {
    if (errorToThrow != null) throw errorToThrow!;
    return prepared!;
  }
}

void main() {
  late Database db;
  late DocumentRepository documentRepository;

  setUp(() async {
    db = await openTestDatabase();
    documentRepository = SqfliteDocumentRepository(db);
  });

  tearDown(() => db.close());

  test('creates a Document row from the prepared file, titled from the '
      'original filename', () async {
    final useCase = DocumentImportUseCase(
      documentRepository: documentRepository,
      documentImportService: _FakeDocumentImportService(
        pickedPath: '/picked/Quarterly Report.pdf',
        prepared: const PreparedDocumentFile(
          filePath: '/app/storage/documents/abc123.pdf',
          originalFilename: 'Quarterly Report.pdf',
          sourceType: DocumentSourceType.pdf,
          fileSizeBytes: 4096,
        ),
      ),
    );

    final documentId = await useCase();

    expect(documentId, isNotNull);
    final document = await documentRepository.getById(documentId!);
    expect(document!.title, 'Quarterly Report');
    expect(document.originalFilename, 'Quarterly Report.pdf');
    expect(document.filePath, '/app/storage/documents/abc123.pdf');
    expect(document.fileSizeBytes, 4096);
    expect(document.sourceType, DocumentSourceType.pdf);
    expect(document.mimeType, 'application/pdf');
    expect(document.status, DocumentStatus.created);
  });

  test('a messy machine-generated filename gets a cleaned title, but the '
      'original filename is preserved unchanged (Phase 7B, item 3)',
      () async {
    final useCase = DocumentImportUseCase(
      documentRepository: documentRepository,
      documentImportService: _FakeDocumentImportService(
        pickedPath: '/picked/202607291339933883_resume_final.pdf',
        prepared: const PreparedDocumentFile(
          filePath: '/app/storage/documents/xyz789.pdf',
          originalFilename: '202607291339933883_resume_final.pdf',
          sourceType: DocumentSourceType.pdf,
          fileSizeBytes: 2048,
        ),
      ),
    );

    final documentId = await useCase();

    final document = await documentRepository.getById(documentId!);
    expect(document!.title, 'resume final');
    expect(document.originalFilename, '202607291339933883_resume_final.pdf');
  });

  test('returns null and inserts nothing when the user cancels the picker',
      () async {
    final useCase = DocumentImportUseCase(
      documentRepository: documentRepository,
      documentImportService: _FakeDocumentImportService(pickedPath: null),
    );

    final documentId = await useCase();

    expect(documentId, isNull);
    expect(await documentRepository.getAll(), isEmpty);
  });

  test('propagates a DocumentImportException (unsupported type/copy '
      'failure) to the caller without inserting a row', () async {
    final useCase = DocumentImportUseCase(
      documentRepository: documentRepository,
      documentImportService: _FakeDocumentImportService(
        pickedPath: '/picked/file.exe',
        errorToThrow: DocumentImportException('Unsupported file type: .exe'),
      ),
    );

    await expectLater(useCase(), throwsA(isA<DocumentImportException>()));
    expect(await documentRepository.getAll(), isEmpty);
  });
}
