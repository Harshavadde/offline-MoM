import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../../../providers/app_providers.dart';
import '../../../../../services/resume/template/resume_template_catalog.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../providers/resume_editor_providers.dart';

/// Renders a resume to PDF for on-screen preview, via `printing`'s
/// [PdfPreview] - mirrors `PdfPreviewScreen`'s exact shape
/// (lib/features/export/presentation/screens/pdf_preview_screen.dart).
///
/// Two modes, chosen by whether [versionId] is passed:
/// - null (default, reached from the Editor's Preview action): compiles and
///   renders the Editor's *current, unsaved* live draft directly via
///   [ResumeEditorController.preview] - see that method's own doc comment
///   for why this never requires a saved [ResumeVersion]. Do not change
///   this to read a version instead.
/// - set (reached from the Versions screen): re-renders one already-saved
///   version's frozen [ResumeSnapshot] - never the live draft, and never
///   affected by edits made to the Editor since that version was saved.
class ResumePreviewScreen extends ConsumerWidget {
  const ResumePreviewScreen({super.key, required this.resumeId, this.versionId});

  final int resumeId;
  final int? versionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(versionId == null ? 'Preview' : 'Version preview')),
      body: PdfPreview(
        build: (format) => versionId == null
            ? ref.read(resumeEditorControllerProvider(resumeId).notifier).preview()
            : _renderVersion(ref, versionId!),
        pdfFileName: 'resume.pdf',
        canDebug: false,
        scrollViewDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
        ),
        // Part J (template gallery/preview - "shows blank when preview"
        // fix, see resume_template_detail_screen.dart's identical fix and
        // its own doc comment for the root cause): this screen shares the
        // exact same `PdfPreview` gap - no `onError` meant a render
        // failure fell back to Flutter's default `ErrorWidget`, whose
        // message text is stripped in release builds, leaving a bare
        // textless box.
        onError: (context, error) => ErrorState(
          title: 'Preview unavailable',
          error: error,
        ),
      ),
    );
  }

  Future<Uint8List> _renderVersion(WidgetRef ref, int versionId) async {
    final version = await ref.read(resumeVersionRepositoryProvider).getById(versionId);
    if (version == null) {
      throw StateError('This version could not be found. It may have been deleted.');
    }
    final templateSpec = ResumeTemplateCatalog.specById(version.templateId);
    return ref.read(resumePdfExportServiceProvider).render(version.compiledSnapshot, templateSpec: templateSpec);
  }
}
