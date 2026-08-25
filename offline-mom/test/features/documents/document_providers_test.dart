import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/documents/presentation/providers/document_providers.dart';
import 'package:offline_mom/models/document.dart';

void main() {
  Document doc({
    required String title,
    DateTime? updatedAt,
    int fileSizeBytes = 1024,
  }) {
    final at = updatedAt ?? DateTime(2026, 1, 1);
    return Document(
      id: null,
      title: title,
      originalFilename: '$title.pdf',
      sourceType: DocumentSourceType.pdf,
      mimeType: 'application/pdf',
      fileSizeBytes: fileSizeBytes,
      filePath: '/tmp/$title.pdf',
      status: DocumentStatus.ready,
      createdAt: at,
      updatedAt: at,
    );
  }

  group('applyDocumentSearchAndSort (Document Manager improvement pass, Part D)', () {
    test('an empty query returns every document, unfiltered', () {
      final documents = [doc(title: 'Report'), doc(title: 'Notes')];
      final result = applyDocumentSearchAndSort(documents, '', DocumentSortOrder.titleAZ);
      expect(result, hasLength(2));
    });

    test('a query matches by title, case-insensitively, as a substring', () {
      final documents = [doc(title: 'Physics Notes'), doc(title: 'Chemistry Lab Report'), doc(title: 'Resume')];
      final result = applyDocumentSearchAndSort(documents, 'notes', DocumentSortOrder.titleAZ);
      expect(result.map((d) => d.title), ['Physics Notes']);
    });

    test('a query with no match returns an empty list, not every document', () {
      final documents = [doc(title: 'Report')];
      final result = applyDocumentSearchAndSort(documents, 'nonexistent', DocumentSortOrder.titleAZ);
      expect(result, isEmpty);
    });

    test('surrounding whitespace in the query is trimmed before matching', () {
      final documents = [doc(title: 'Report')];
      final result = applyDocumentSearchAndSort(documents, '  report  ', DocumentSortOrder.titleAZ);
      expect(result, hasLength(1));
    });

    test('titleAZ sorts case-insensitively, alphabetically', () {
      final documents = [doc(title: 'zebra'), doc(title: 'Apple'), doc(title: 'mango')];
      final result = applyDocumentSearchAndSort(documents, '', DocumentSortOrder.titleAZ);
      expect(result.map((d) => d.title), ['Apple', 'mango', 'zebra']);
    });

    test('newestFirst orders by updatedAt descending', () {
      final documents = [
        doc(title: 'Old', updatedAt: DateTime(2025, 1, 1)),
        doc(title: 'New', updatedAt: DateTime(2026, 6, 1)),
        doc(title: 'Middle', updatedAt: DateTime(2025, 12, 1)),
      ];
      final result = applyDocumentSearchAndSort(documents, '', DocumentSortOrder.newestFirst);
      expect(result.map((d) => d.title), ['New', 'Middle', 'Old']);
    });

    test('oldestFirst orders by updatedAt ascending', () {
      final documents = [
        doc(title: 'Old', updatedAt: DateTime(2025, 1, 1)),
        doc(title: 'New', updatedAt: DateTime(2026, 6, 1)),
      ];
      final result = applyDocumentSearchAndSort(documents, '', DocumentSortOrder.oldestFirst);
      expect(result.map((d) => d.title), ['Old', 'New']);
    });

    test('largestFirst orders by fileSizeBytes descending', () {
      final documents = [
        doc(title: 'Small', fileSizeBytes: 1000),
        doc(title: 'Big', fileSizeBytes: 5_000_000),
        doc(title: 'Medium', fileSizeBytes: 50_000),
      ];
      final result = applyDocumentSearchAndSort(documents, '', DocumentSortOrder.largestFirst);
      expect(result.map((d) => d.title), ['Big', 'Medium', 'Small']);
    });

    test('search and sort compose - filters first, then sorts the surviving subset', () {
      final documents = [
        doc(title: 'Lab Report B', updatedAt: DateTime(2026, 1, 1)),
        doc(title: 'Resume', updatedAt: DateTime(2026, 3, 1)),
        doc(title: 'Lab Report A', updatedAt: DateTime(2026, 2, 1)),
      ];
      final result = applyDocumentSearchAndSort(documents, 'lab report', DocumentSortOrder.newestFirst);
      expect(result.map((d) => d.title), ['Lab Report A', 'Lab Report B']);
    });

    test('never mutates the input list', () {
      final documents = [doc(title: 'B'), doc(title: 'A')];
      final original = List<Document>.of(documents);
      applyDocumentSearchAndSort(documents, '', DocumentSortOrder.titleAZ);
      expect(documents.map((d) => d.title), original.map((d) => d.title));
    });
  });
}
