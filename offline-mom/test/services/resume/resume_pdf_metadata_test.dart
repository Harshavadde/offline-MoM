// Milestone 5 (docs/v3/01-prd.md §14/§25) - PDF metadata privacy check.
//
// package:pdf's `pw.Document()` only ever constructs a `PdfInfo` object
// (the PDF `/Info` dictionary - Title/Author/Creator/Producer/Subject/
// Keywords) when the caller explicitly passes at least one of those named
// parameters (confirmed by direct inspection of
// package:pdf 3.11.3's lib/src/widgets/document.dart - `Document`'s
// constructor only calls `PdfInfo(...)` inside an `if (title != null ||
// author != null || ...)` guard). `ResumeTemplateRenderer.render()` calls
// `pw.Document()` with none of those parameters, so no `/Info` dictionary
// - and therefore no identifying metadata of any kind, not even a
// fallback "Producer: package:pdf" string - is written to a generated
// resume PDF today.
//
// This test verifies that claim empirically, against real rendered PDF
// bytes, not just by reading the dependency's source: every metadata key
// a PDF reader could surface (Title/Author/Creator/Producer/Subject/
// Keywords, and the `/Info` dictionary reference itself) is searched for
// directly in the raw output bytes, for every one of the 10 beta catalog
// templates. A future `package:pdf` upgrade or an accidental
// `pw.Document(title: ...)` call anywhere in the render path would fail
// this test immediately, rather than silently reintroducing identifying
// metadata into an externally-shared document.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

void main() {
  // Post-Milestone-5 visual-quality redesign pass: the renderer now loads
  // the bundled Inter font via rootBundle, which requires the Flutter
  // services binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  const renderer = ResumeTemplateRenderer();

  ResumeSnapshot snapshot() {
    return ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(
        fullName: 'Jane Doe',
        email: 'jane.doe@example.com',
      ),
    );
  }

  group('no identifying PDF metadata in any beta catalog template', () {
    for (final spec in ResumeTemplateCatalog.all) {
      test('${spec.id}: raw PDF bytes contain no /Info dictionary or metadata key', () async {
        final bytes = await renderer.render(snapshot(), spec);
        final raw = String.fromCharCodes(bytes);

        for (final key in [
          '/Info',
          '/Producer',
          '/Author',
          '/Title',
          '/Creator',
          '/Subject',
          '/Keywords',
        ]) {
          expect(raw.contains(key), isFalse, reason: '${spec.id} unexpectedly contains "$key"');
        }
      });
    }
  });
}
