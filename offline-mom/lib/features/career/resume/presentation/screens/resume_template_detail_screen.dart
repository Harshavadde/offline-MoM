import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../../../../services/resume/template/resume_template_catalog.dart';
import '../../../../../services/resume/template/resume_template_spec.dart';
import '../../../../../shared/widgets/error_state.dart';
import '../providers/resume_template_providers.dart';

/// The "tap a template -> larger real preview -> Use This Template" confirm
/// step: Resume Editor -> Choose Template -> Template Gallery -> **this
/// screen** -> return to Editor. Reuses [PdfPreview] directly - the exact
/// same widget `ResumePreviewScreen` uses for the real resume's own
/// preview - fed **the actual current resume** rendered through this
/// template (`templateResumePdfBytesProvider`, real-device beta fix
/// (Phase 7): previously a fixed sample resume, now the live-compiled
/// current draft via the same [ResumeTemplateRenderer] every export/
/// preview call goes through). Never a second, fake preview
/// implementation, and this is the one place in the selection flow that
/// genuinely shows pagination behavior for the user's own content
/// (multi-page resumes page-navigate here exactly like the real exported
/// PDF would).
class ResumeTemplateDetailScreen extends ConsumerWidget {
  const ResumeTemplateDetailScreen({super.key, required this.resumeId, required this.templateId});

  final int resumeId;
  final String templateId;

  Future<void> _useThisTemplate(BuildContext context, WidgetRef ref, ResumeTemplateSpec spec) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(resumeTemplateSelectionControllerProvider(resumeId).notifier).select(spec);
    if (!context.mounted) return;

    final state = ref.read(resumeTemplateSelectionControllerProvider(resumeId));
    if (state.error != null) {
      messenger.showSnackBar(SnackBar(content: Text(state.error!)));
      return;
    }

    // Returns to the Editor by popping exactly two routes off the stack -
    // this screen (Detail) and the gallery grid beneath it - rather than
    // context.go(...), which would instead replace the ENTIRE navigation
    // stack with just the Editor route: silently discarding whatever real
    // back-history got the user here (the Resume List screen, "Create
    // Resume from Profile", etc.) and breaking the phone's back button
    // afterward. Both Gallery and this screen were reached via
    // context.push ("Editor -> Choose Template -> Template Gallery ->
    // this screen", docs/v3/implementation/03-decisions.md), so exactly
    // two pops always lands back on the Editor, never further. Resume
    // content is never touched here or by select() itself - only
    // Resume.templateId changes.
    context.pop();
    context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spec = ResumeTemplateCatalog.specById(templateId);
    final selectionState = ref.watch(resumeTemplateSelectionControllerProvider(resumeId));

    return Scaffold(
      appBar: AppBar(title: Text(spec.displayName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(spec.candidateType, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: PdfPreview(
              build: (format) =>
                  ref.read(templateResumePdfBytesProvider((resumeId: resumeId, templateId: templateId)).future),
              pdfFileName: 'template_preview.pdf',
              canDebug: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowPrinting: false,
              allowSharing: false,
              scrollViewDecoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
              ),
              // Part J (template gallery/preview - "shows blank when
              // preview" fix): without this, `PdfPreview` falls back to
              // Flutter's own default `ErrorWidget` on any render failure
              // (or when `Printing.info()` reports `canRaster: false`) -
              // and `ErrorWidget`'s message text is built inside an
              // `assert()` block, which release builds strip entirely,
              // leaving a bare, textless colored box exactly matching the
              // "blank preview" symptom. Reuses the app's own existing
              // ErrorState/friendlyErrorMessage convention rather than a
              // one-off message.
              onError: (context, error) => ErrorState(
                title: 'Preview unavailable',
                error: error,
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FilledButton.icon(
              onPressed: selectionState.isBusy ? null : () => _useThisTemplate(context, ref, spec),
              icon: selectionState.isBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: const Text('Use This Template'),
            ),
          ),
        ],
      ),
    );
  }
}
