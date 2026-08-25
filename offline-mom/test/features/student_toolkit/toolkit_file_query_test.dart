// Pure logic tests for filterToolkitFilesByQuery/sortToolkitFiles (P0-9,
// File-Manager Parity) - no widgets, no database, matching
// pdf_search_matcher_test.dart's own "test the pure logic directly"
// precedent.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/toolkit_file_query.dart';
import 'package:offline_mom/models/toolkit_file.dart';

void main() {
  ToolkitFile build({
    required String title,
    DateTime? createdAt,
    int fileSizeBytes = 1000,
  }) {
    final now = createdAt ?? DateTime(2026, 1, 1);
    return ToolkitFile(
      id: null,
      toolType: ToolkitToolType.imageCompress,
      title: title,
      outputPath: '/data/toolkit/$title.jpg',
      fileSizeBytes: fileSizeBytes,
      originalFileSizeBytes: null,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('filterToolkitFilesByQuery', () {
    test('an empty query returns every file unchanged', () {
      final files = [build(title: 'Alpha'), build(title: 'Beta')];
      expect(filterToolkitFilesByQuery(files, ''), files);
    });

    test('a whitespace-only query returns every file unchanged', () {
      final files = [build(title: 'Alpha')];
      expect(filterToolkitFilesByQuery(files, '   '), files);
    });

    test('matches a case-insensitive substring of the title', () {
      final files = [build(title: 'Scholarship Form'), build(title: 'Passport Photo')];
      final result = filterToolkitFilesByQuery(files, 'photo');
      expect(result.map((f) => f.title), ['Passport Photo']);
    });

    test('returns an empty list when nothing matches', () {
      final files = [build(title: 'Alpha')];
      expect(filterToolkitFilesByQuery(files, 'zzz'), isEmpty);
    });
  });

  group('sortToolkitFiles', () {
    test('dateNewest orders most recently created first', () {
      final files = [
        build(title: 'Old', createdAt: DateTime(2026, 1, 1)),
        build(title: 'New', createdAt: DateTime(2026, 1, 3)),
        build(title: 'Mid', createdAt: DateTime(2026, 1, 2)),
      ];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.dateNewest);
      expect(sorted.map((f) => f.title).toList(), ['New', 'Mid', 'Old']);
    });

    test('dateOldest orders least recently created first', () {
      final files = [
        build(title: 'Old', createdAt: DateTime(2026, 1, 1)),
        build(title: 'New', createdAt: DateTime(2026, 1, 3)),
      ];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.dateOldest);
      expect(sorted.map((f) => f.title).toList(), ['Old', 'New']);
    });

    test('nameAZ orders case-insensitively', () {
      final files = [build(title: 'zebra'), build(title: 'Apple'), build(title: 'banana')];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.nameAZ);
      expect(sorted.map((f) => f.title).toList(), ['Apple', 'banana', 'zebra']);
    });

    test('nameZA reverses nameAZ', () {
      final files = [build(title: 'Apple'), build(title: 'zebra'), build(title: 'banana')];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.nameZA);
      expect(sorted.map((f) => f.title).toList(), ['zebra', 'banana', 'Apple']);
    });

    test('sizeLargest orders biggest file first', () {
      final files = [
        build(title: 'Small', fileSizeBytes: 100),
        build(title: 'Big', fileSizeBytes: 9000),
      ];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.sizeLargest);
      expect(sorted.map((f) => f.title).toList(), ['Big', 'Small']);
    });

    test('sizeSmallest orders smallest file first', () {
      final files = [
        build(title: 'Big', fileSizeBytes: 9000),
        build(title: 'Small', fileSizeBytes: 100),
      ];
      final sorted = sortToolkitFiles(files, ToolkitFileSort.sizeSmallest);
      expect(sorted.map((f) => f.title).toList(), ['Small', 'Big']);
    });

    test('never mutates the input list', () {
      final files = [build(title: 'B', createdAt: DateTime(2026, 1, 1)), build(title: 'A', createdAt: DateTime(2026, 1, 2))];
      final original = List.of(files);
      sortToolkitFiles(files, ToolkitFileSort.nameAZ);
      expect(files, original);
    });
  });
}
