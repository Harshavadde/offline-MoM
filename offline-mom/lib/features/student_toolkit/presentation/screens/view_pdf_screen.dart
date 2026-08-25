import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/router/route_paths.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../providers/view_pdf_providers.dart';
import '../toolkit_snackbars.dart';

/// View PDF + Search (Productivity Toolkit productization pass, P0-6) -
/// pick a PDF, browse it one page at a time, and search its extractable
/// text (`PdfTextSearchService`, born-digital text only). When a PDF has
/// no extractable text, "Run OCR" (P0-7) builds a new searchable copy via
/// `ViewPdfController.runOcr()` - the original file is never modified.
class ViewPdfScreen extends ConsumerStatefulWidget {
  const ViewPdfScreen({super.key});

  @override
  ConsumerState<ViewPdfScreen> createState() => _ViewPdfScreenState();
}

class _ViewPdfScreenState extends ConsumerState<ViewPdfScreen> {
  bool _searchOpen = false;
  final _searchController = TextEditingController();

  // Real, resolution-aware PDF rendering (`package:pdfrx`'s own viewer
  // widget, backed by the same bundled PDFium engine every other PDF Tool
  // already rasterizes through - `PdfiumPdfPageRenderingService`) -
  // replaces displaying a single fixed-DPI JPEG snapshot, whose sharpness
  // necessarily degrades past whatever zoom level that one DPI was chosen
  // for. `PdfViewer` re-renders the visible page at whatever resolution the
  // current viewport/zoom actually needs (see its own `getPageRenderingScale`
  // hook) and bounds its own render cache (`maxImageBytesCachedOnMemory`),
  // rather than this app hand-rolling adaptive re-rasterization.
  //
  // `ViewPdfController`'s own `_rasterize()`/`state.pages` pipeline is
  // deliberately left completely unchanged and still runs - `runOcr()`
  // reuses those already-rasterized JPEG bytes to prime the OCR session
  // without a second rasterization pass, and `saveUnlockedCopy()`'s saved-
  // file record still reports `state.pages.length` as its page count. This
  // widget's own PDFium document is therefore a second, independent decode
  // of the same bytes - a deliberate, disclosed tradeoff (one extra decode
  // per PDF picked, not per zoom/interaction) favoring not touching that
  // already-working, more deeply-interconnected logic.
  final _pdfViewerController = PdfViewerController();
  int? _pdfrxCurrentPageNumber;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Keeps `ViewPdfState.currentPage` (the existing search/prev-next source
  /// of truth) and the `PdfViewer`'s own on-screen page in sync in both
  /// directions: this controller's own navigation calls `notifier.goToPage`
  /// as it always has, and this listener drives `_pdfViewerController` to
  /// follow it; conversely a user swiping within the `PdfViewer` itself
  /// reports back here via `PdfViewerParams.onPageChanged` so the "Page N
  /// of M" text and prev/next button state stay accurate either way.
  void _syncViewerToState(ViewPdfState state) {
    final targetPageNumber = state.currentPage + 1;
    if (_pdfrxCurrentPageNumber == targetPageNumber) return;
    _pdfrxCurrentPageNumber = targetPageNumber;
    if (_pdfViewerController.isReady) {
      _pdfViewerController.goToPage(pageNumber: targetPageNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(viewPdfControllerProvider);
    final notifier = ref.read(viewPdfControllerProvider.notifier);

    ref.listen<ViewPdfState>(viewPdfControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (previous?.currentPage != next.currentPage) {
        _syncViewerToState(next);
      }
    });

    if (state.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('View PDF')),
        body: Center(
          child: EmptyState(
            icon: Icons.picture_as_pdf_outlined,
            title: 'View and search a PDF',
            message: 'Browse any PDF page by page and search its text - fully offline, on-device.',
            actions: [
              FilledButton.icon(
                onPressed: notifier.pickPdf,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Choose a PDF'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.needsPassword) {
      return Scaffold(
        appBar: AppBar(title: const Text('View PDF')),
        body: Center(child: _PasswordPrompt(state: state, notifier: notifier)),
      );
    }

    if (state.isBusy && state.pages.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final page = state.currentPage < state.pages.length ? state.pages[state.currentPage] : null;

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(hintText: 'Search this PDF…', border: InputBorder.none),
                onChanged: notifier.setSearchQuery,
              )
            : Text('Page ${state.currentPage + 1} of ${state.pages.length}'),
        actions: [
          if (state.unlockedBytes != null && !_searchOpen)
            TextButton.icon(
              onPressed: state.unlockedSavedFile != null
                  ? null
                  : () async {
                      await notifier.saveUnlockedCopy();
                      if (!context.mounted) return;
                      showSavedToRecentFilesSnackBar(context);
                    },
              icon: Icon(state.unlockedSavedFile != null ? Icons.check_rounded : Icons.lock_open_rounded),
              label: Text(state.unlockedSavedFile != null ? 'Saved' : 'Save Unlocked Copy'),
            ),
          if (_searchOpen)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close search',
              onPressed: () {
                _searchController.clear();
                notifier.clearSearch();
                setState(() => _searchOpen = false);
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search',
              onPressed: () async {
                setState(() => _searchOpen = true);
                await notifier.ensureTextExtracted();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_searchOpen) _SearchResultsBar(state: state, notifier: notifier),
            Expanded(
              child: page == null
                  ? const Center(child: Text('This page could not be loaded.'))
                  : PdfViewer.data(
                      state.unlockedBytes ?? state.source!.bytes,
                      // Must stay stable across rebuilds for the same PDF
                      // (not e.g. re-derived from a changing value) so
                      // pdfrx doesn't treat every unrelated state change as
                      // a brand-new document to reload.
                      sourceName: state.source!.fileName,
                      controller: _pdfViewerController,
                      initialPageNumber: state.currentPage + 1,
                      params: PdfViewerParams(
                        onPageChanged: (pageNumber) {
                          if (pageNumber == null) return;
                          _pdfrxCurrentPageNumber = pageNumber;
                          final index = pageNumber - 1;
                          if (index != state.currentPage) notifier.goToPage(index);
                        },
                      ),
                    ),
            ),
            if (!_searchOpen && state.pages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: state.currentPage > 0 ? () => notifier.goToPage(state.currentPage - 1) : null,
                    ),
                    Text('${state.currentPage + 1} / ${state.pages.length}'),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: state.currentPage < state.pages.length - 1 ? () => notifier.goToPage(state.currentPage + 1) : null,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({required this.state, required this.notifier});
  final ViewPdfState state;
  final ViewPdfController notifier;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 56),
          const SizedBox(height: 16),
          Text('This PDF is password protected.', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            enabled: !state.isBusy,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: state.passwordError,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => widget.notifier.tryPassword(_controller.text),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: state.isBusy ? null : () => widget.notifier.tryPassword(_controller.text),
            icon: state.isBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock_open_rounded),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsBar extends StatelessWidget {
  const _SearchResultsBar({required this.state, required this.notifier});
  final ViewPdfState state;
  final ViewPdfController notifier;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (state.isSearchBusy) {
      return const LinearProgressIndicator(minHeight: 3);
    }

    if (state.hasExtractedText && !state.isSearchable) {
      return Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No searchable text found in this PDF - it may be a scanned or image-only document.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () async {
                await notifier.runOcr();
                if (!context.mounted) return;
                context.push(RoutePaths.toolkitOcr);
              },
              child: const Text('Run OCR'),
            ),
          ],
        ),
      );
    }

    if (state.searchQuery.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    if (state.matches.isEmpty) {
      return Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Text('No matches for "${state.searchQuery}"', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
      );
    }

    final current = state.matches[state.currentMatchIndex];
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${state.totalOccurrences} match${state.totalOccurrences == 1 ? '' : 'es'} on ${state.matches.length} page${state.matches.length == 1 ? '' : 's'} · '
                    '${state.currentMatchIndex + 1}/${state.matches.length}: Page ${current.pageIndex + 1}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(icon: const Icon(Icons.keyboard_arrow_up_rounded), tooltip: 'Previous', onPressed: notifier.previousMatch),
                IconButton(icon: const Icon(Icons.keyboard_arrow_down_rounded), tooltip: 'Next', onPressed: notifier.nextMatch),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
              itemCount: state.matches.length,
              itemBuilder: (context, index) {
                final match = state.matches[index];
                final selected = index == state.currentMatchIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('Page ${match.pageIndex + 1} (${match.occurrenceCount})'),
                    selected: selected,
                    onSelected: (_) => notifier.selectMatch(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
