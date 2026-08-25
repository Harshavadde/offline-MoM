import '../../models/toolkit_file.dart';

/// How the Files screen orders a list of [ToolkitFile]s (P0-9, File-Manager
/// Parity) - pure, UI-independent, matching `pdf_search_matcher.dart`'s own
/// "separate the logic from the widget so it's directly unit-testable"
/// precedent.
enum ToolkitFileSort {
  dateNewest,
  dateOldest,
  nameAZ,
  nameZA,
  sizeLargest,
  sizeSmallest,
}

extension ToolkitFileSortLabel on ToolkitFileSort {
  String get label => switch (this) {
        ToolkitFileSort.dateNewest => 'Newest first',
        ToolkitFileSort.dateOldest => 'Oldest first',
        ToolkitFileSort.nameAZ => 'Name (A-Z)',
        ToolkitFileSort.nameZA => 'Name (Z-A)',
        ToolkitFileSort.sizeLargest => 'Largest first',
        ToolkitFileSort.sizeSmallest => 'Smallest first',
      };
}

/// Case-insensitive substring match against [ToolkitFile.title] - the same
/// "simple, honest, no fuzzy-matching invented" convention
/// `searchPdfPagesText` already established for this app's other search
/// feature. An empty/whitespace-only [query] returns [files] unchanged.
List<ToolkitFile> filterToolkitFilesByQuery(List<ToolkitFile> files, String query) {
  final trimmed = query.trim().toLowerCase();
  if (trimmed.isEmpty) return files;
  return files.where((f) => f.title.toLowerCase().contains(trimmed)).toList();
}

/// Returns a new, sorted list - never mutates [files]. Ties within a sort
/// (e.g. two files with the exact same title under [ToolkitFileSort.nameAZ])
/// keep their relative order ([List.sort] is stable in Dart), so re-sorting
/// an already-date-ordered list by name still reads predictably.
List<ToolkitFile> sortToolkitFiles(List<ToolkitFile> files, ToolkitFileSort sort) {
  final sorted = List<ToolkitFile>.of(files);
  switch (sort) {
    case ToolkitFileSort.dateNewest:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    case ToolkitFileSort.dateOldest:
      sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    case ToolkitFileSort.nameAZ:
      sorted.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case ToolkitFileSort.nameZA:
      sorted.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
    case ToolkitFileSort.sizeLargest:
      sorted.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
    case ToolkitFileSort.sizeSmallest:
      sorted.sort((a, b) => a.fileSizeBytes.compareTo(b.fileSizeBytes));
  }
  return sorted;
}
