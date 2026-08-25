import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/router/route_paths.dart';
import '../../../../../models/certification_block.dart';
import '../../../../../models/education_block.dart';
import '../../../../../models/experience_block.dart';
import '../../../../../models/project_block.dart';
import '../../../../../models/skill_entry.dart';
import '../../../../../services/resume/resume_import_parser.dart';
import '../../../../../services/resume/resume_import_second_pass.dart';
import '../../../../../shared/widgets/ai_disclaimer.dart';
import '../../../../../shared/widgets/section_heading.dart';
import '../providers/resume_import_providers.dart';

/// Import an existing PDF/DOCX/TXT/Markdown resume - mirrors
/// `DocumentImportScreen`'s tap-to-pick shape
/// (lib/features/documents/presentation/screens/document_import_screen.dart)
/// for the initial step, then adds the review step Batch 7 requires before
/// anything is written to the database. Confirming import navigates into
/// the *existing* `ResumeEditorScreen` for the newly created resume - this
/// screen never duplicates any Editor functionality of its own.
///
/// **Milestone 4 (docs/v3/01-prd.md §10/§25):** the review step is now
/// per-entry editable - every detected Experience/Education/Project/
/// Certification/Skill entry can be corrected or removed before Import
/// commits, not just the resume title. Adding a brand-new entry during
/// review is deliberately out of scope (the existing Editor's own
/// add-block flow already covers that, once the resume exists) - this
/// screen's job is correcting what the deterministic parser already
/// detected, not authoring new content.
class ResumeImportScreen extends ConsumerWidget {
  const ResumeImportScreen({super.key});

  static const _formats = ['PDF', 'DOCX', 'TXT', 'MD'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resumeImportControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<ResumeImportUiState>(resumeImportControllerProvider, (previous, next) {
      if (next is ResumeImportSucceeded) {
        final resumeId = next.resumeId;
        ref.read(resumeImportControllerProvider.notifier).reset();
        context.pushReplacement(RoutePaths.resumeEditorPath(resumeId));
      } else if (next is ResumeImportFailed) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
        ref.read(resumeImportControllerProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Import Resume')),
      body: switch (state) {
        ResumeImportIdle() || ResumeImportProcessing() => _PickBody(
            isProcessing: state is ResumeImportProcessing,
            scheme: scheme,
          ),
        ResumeImportReviewing() => _ReviewBody(state: state),
        ResumeImportSucceeded() || ResumeImportFailed() => const SizedBox.shrink(),
      },
    );
  }
}

class _PickBody extends ConsumerWidget {
  const _PickBody({required this.isProcessing, required this.scheme});

  final bool isProcessing;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: isProcessing
                    ? null
                    : () => ref.read(resumeImportControllerProvider.notifier).pickAndParse(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: isProcessing
                            ? Padding(
                                padding: const EdgeInsets.all(20),
                                child: CircularProgressIndicator(color: scheme.onPrimaryContainer),
                              )
                            : Icon(
                                Icons.file_upload_outlined,
                                size: 34,
                                color: scheme.onPrimaryContainer,
                              ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isProcessing ? 'Reading your resume…' : 'Tap to choose a file',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isProcessing
                            ? 'Extracting and structuring the content on this '
                                'device. This can take a moment for longer files.'
                            : 'Pick an existing resume from this device - we\'ll '
                                'extract its content and turn it into an '
                                'editable, structured resume.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      if (!isProcessing) ...[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () =>
                              ref.read(resumeImportControllerProvider.notifier).pickAndParse(),
                          icon: const Icon(Icons.folder_open_rounded),
                          label: const Text('Choose a file'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Supported formats', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final format in ResumeImportScreen._formats)
                  Chip(
                    label: Text(format),
                    backgroundColor: scheme.surfaceContainerHighest,
                    side: BorderSide.none,
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Your resume is read and structured entirely on this device. '
              'Nothing is ever uploaded or sent anywhere.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewBody extends ConsumerWidget {
  const _ReviewBody({required this.state});

  final ResumeImportReviewing state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = state.draft;
    final scheme = Theme.of(context).colorScheme;
    final notifier = ref.read(resumeImportControllerProvider.notifier);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              children: [
                if (state.error != null) ...[
                  Card(
                    color: scheme.errorContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        state.error!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _InlineTextField(
                  key: const ValueKey('title'),
                  initialText: state.title,
                  labelText: 'Resume title',
                  onChanged: notifier.updateTitle,
                ),
                const SizedBox(height: 20),
                const SectionHeading('Detected profile'),
                const SizedBox(height: 8),
                _ProfileSummaryCard(draft: draft),
                const SizedBox(height: 20),
                _EditableSection<ExperienceBlock>(
                  label: 'Experience',
                  entries: draft.experience,
                  cardBuilder: (entry, index) => _ExperienceEntryCard(
                    key: ValueKey('experience-$index'),
                    entry: entry,
                    onChanged: (updated) => notifier.updateDraft((d) {
                      final list = [...d.experience];
                      list[index] = updated;
                      return d.copyWith(experience: list);
                    }),
                    onRemove: () => notifier.updateDraft((d) {
                      final list = [...d.experience]..removeAt(index);
                      return d.copyWith(experience: list);
                    }),
                  ),
                ),
                _EditableSection<EducationBlock>(
                  label: 'Education',
                  entries: draft.education,
                  cardBuilder: (entry, index) => _EducationEntryCard(
                    key: ValueKey('education-$index'),
                    entry: entry,
                    onChanged: (updated) => notifier.updateDraft((d) {
                      final list = [...d.education];
                      list[index] = updated;
                      return d.copyWith(education: list);
                    }),
                    onRemove: () => notifier.updateDraft((d) {
                      final list = [...d.education]..removeAt(index);
                      return d.copyWith(education: list);
                    }),
                  ),
                ),
                _EditableSection<ProjectBlock>(
                  label: 'Projects',
                  entries: draft.projects,
                  cardBuilder: (entry, index) => _ProjectEntryCard(
                    key: ValueKey('project-$index'),
                    entry: entry,
                    onChanged: (updated) => notifier.updateDraft((d) {
                      final list = [...d.projects];
                      list[index] = updated;
                      return d.copyWith(projects: list);
                    }),
                    onRemove: () => notifier.updateDraft((d) {
                      final list = [...d.projects]..removeAt(index);
                      return d.copyWith(projects: list);
                    }),
                  ),
                ),
                _EditableSection<CertificationBlock>(
                  label: 'Certifications',
                  entries: draft.certifications,
                  cardBuilder: (entry, index) => _CertificationEntryCard(
                    key: ValueKey('certification-$index'),
                    entry: entry,
                    onChanged: (updated) => notifier.updateDraft((d) {
                      final list = [...d.certifications];
                      list[index] = updated;
                      return d.copyWith(certifications: list);
                    }),
                    onRemove: () => notifier.updateDraft((d) {
                      final list = [...d.certifications]..removeAt(index);
                      return d.copyWith(certifications: list);
                    }),
                  ),
                ),
                _EditableSection<SkillEntry>(
                  label: 'Skills',
                  entries: draft.skills,
                  cardBuilder: (entry, index) => _SkillEntryCard(
                    key: ValueKey('skill-$index'),
                    entry: entry,
                    onChanged: (updated) => notifier.updateDraft((d) {
                      final list = [...d.skills];
                      list[index] = updated;
                      return d.copyWith(skills: list);
                    }),
                    onRemove: () => notifier.updateDraft((d) {
                      final list = [...d.skills]..removeAt(index);
                      return d.copyWith(skills: list);
                    }),
                  ),
                ),
                if (draft.warnings.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeading('Warnings'),
                  const SizedBox(height: 8),
                  Card(
                    color: scheme.tertiaryContainer,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final warning in draft.warnings)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                warning,
                                style: TextStyle(color: scheme.onTertiaryContainer),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (draft.unclassifiedText.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionHeading('Could not be automatically classified'),
                  const SizedBox(height: 4),
                  Text(
                    'This content was found in the file but could not be '
                    'confidently structured. It will not be imported unless '
                    'you copy anything useful into the Editor manually after '
                    'import - you can remove any of these blocks below if '
                    'they\'re not useful.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (shouldOfferImportSecondPass(draft)) ...[
                    const SizedBox(height: 12),
                    _SecondPassOfferCard(
                      isRunning: state.isRunningSecondPass,
                      onRun: notifier.runImportSecondPass,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < draft.unclassifiedText.length; i++) ...[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: Text(draft.unclassifiedText[i])),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                  tooltip: 'Remove',
                                  onPressed: () => notifier.updateDraft((d) {
                                    final list = [...d.unclassifiedText]..removeAt(i);
                                    return d.copyWith(unclassifiedText: list);
                                  }),
                                ),
                              ],
                            ),
                            const Divider(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: state.isConfirming ? null : notifier.reset,
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: state.isConfirming ? null : notifier.confirmImport,
                    child: state.isConfirming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Import'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Offers the optional LLM-assisted import second pass (docs/v3/01-prd.md
/// §10, Milestone 4) when a lot of this document's content couldn't be
/// automatically classified. Purely opt-in - tapping the button is the
/// only way [ResumeImportController.runImportSecondPass] ever runs; any
/// entries it finds still land in the same per-entry-editable review list
/// above, fully reviewable before Import.
class _SecondPassOfferCard extends StatelessWidget {
  const _SecondPassOfferCard({required this.isRunning, required this.onRun});

  final bool isRunning;
  final Future<void> Function() onRun;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'A large part of this document couldn\'t be automatically '
                    'organized. An on-device AI pass can try to sort it into '
                    'the sections above - still fully editable before you '
                    'import.',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: isRunning ? null : onRun,
                  child: isRunning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Try it'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const AiDisclaimer.resume(),
          ],
        ),
      ),
    );
  }
}

class _ProfileSummaryCard extends StatelessWidget {
  const _ProfileSummaryCard({required this.draft});

  final ParsedResumeDraft draft;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (draft.fullName case final fullName?) fullName,
      if (draft.email case final email?) email,
      if (draft.phone case final phone?) phone,
      if (draft.location case final location?) location,
      for (final link in draft.links) '${link.label}: ${link.url}',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: lines.isEmpty
            ? Text(
                'No profile information was detected.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final line in lines) Text(line)],
              ),
      ),
    );
  }
}

/// One section (Experience/Education/Projects/Certifications/Skills) of
/// the per-entry-editable review list (Milestone 4). Shows a count in the
/// section heading, an empty-state message when there's nothing detected,
/// and otherwise one editable card per entry via [cardBuilder].
class _EditableSection<T> extends StatelessWidget {
  const _EditableSection({required this.label, required this.entries, required this.cardBuilder});

  final String label;
  final List<T> entries;
  final Widget Function(T entry, int index) cardBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading('$label (${entries.length})'),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'None detected.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            )
          else
            for (var i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: cardBuilder(entries[i], i),
              ),
        ],
      ),
    );
  }
}

/// A single text field that owns its own [TextEditingController], seeded
/// once from [initialText] - keeps typing cursor position stable across
/// this screen's frequent provider rebuilds (every keystroke in *any*
/// field replaces the whole draft, per [ResumeImportController.updateDraft]),
/// as long as the caller gives each instance a stable [Key] (every call
/// site below does, keyed by section + entry index + field name).
class _InlineTextField extends StatefulWidget {
  const _InlineTextField({
    super.key,
    required this.initialText,
    required this.labelText,
    this.onChanged,
    this.maxLines = 1,
    this.minLines,
    this.helperText,
  });

  final String initialText;
  final String labelText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final int? minLines;

  @override
  State<_InlineTextField> createState() => _InlineTextFieldState();
}

class _InlineTextFieldState extends State<_InlineTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      decoration: InputDecoration(labelText: widget.labelText, helperText: widget.helperText),
      onChanged: widget.onChanged,
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.delete_outline_rounded, size: 20),
      tooltip: 'Remove this entry',
      onPressed: onPressed,
    );
  }
}

class _EntryCardShell extends StatelessWidget {
  const _EntryCardShell({required this.fields, required this.onRemove});

  final List<Widget> fields;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                _RemoveButton(onPressed: onRemove),
              ],
            ),
            for (final field in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: field),
          ],
        ),
      ),
    );
  }
}

class _ExperienceEntryCard extends StatelessWidget {
  const _ExperienceEntryCard({super.key, required this.entry, required this.onChanged, required this.onRemove});

  final ExperienceBlock entry;
  final ValueChanged<ExperienceBlock> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EntryCardShell(
      onRemove: onRemove,
      fields: [
        _InlineTextField(
          initialText: entry.role,
          labelText: 'Role',
          onChanged: (v) => onChanged(entry.copyWith(role: v)),
        ),
        _InlineTextField(
          initialText: entry.company,
          labelText: 'Company',
          onChanged: (v) => onChanged(entry.copyWith(company: v)),
        ),
        _InlineTextField(
          initialText: entry.location ?? '',
          labelText: 'Location (optional)',
          onChanged: (v) => onChanged(entry.copyWith(location: v)),
        ),
        _InlineTextField(
          initialText: entry.startDate,
          labelText: 'Start date',
          helperText: 'YYYY-MM',
          onChanged: (v) => onChanged(entry.copyWith(startDate: v)),
        ),
        _InlineTextField(
          initialText: entry.endDate ?? '',
          labelText: 'End date',
          helperText: 'YYYY-MM, blank = Present',
          onChanged: (v) => onChanged(entry.copyWith(endDate: v)),
        ),
        _InlineTextField(
          initialText: entry.bullets.join('\n'),
          labelText: 'Bullets',
          helperText: 'One per line',
          maxLines: 6,
          minLines: 3,
          onChanged: (v) => onChanged(
            entry.copyWith(bullets: v.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()),
          ),
        ),
      ],
    );
  }
}

class _EducationEntryCard extends StatelessWidget {
  const _EducationEntryCard({super.key, required this.entry, required this.onChanged, required this.onRemove});

  final EducationBlock entry;
  final ValueChanged<EducationBlock> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EntryCardShell(
      onRemove: onRemove,
      fields: [
        _InlineTextField(
          initialText: entry.institution,
          labelText: 'Institution',
          onChanged: (v) => onChanged(entry.copyWith(institution: v)),
        ),
        _InlineTextField(
          initialText: entry.degree,
          labelText: 'Degree',
          onChanged: (v) => onChanged(entry.copyWith(degree: v)),
        ),
        _InlineTextField(
          initialText: entry.fieldOfStudy ?? '',
          labelText: 'Field of study (optional)',
          onChanged: (v) => onChanged(entry.copyWith(fieldOfStudy: v)),
        ),
        _InlineTextField(
          initialText: entry.startDate,
          labelText: 'Start date',
          helperText: 'YYYY-MM',
          onChanged: (v) => onChanged(entry.copyWith(startDate: v)),
        ),
        _InlineTextField(
          initialText: entry.endDate ?? '',
          labelText: 'End date',
          helperText: 'YYYY-MM, blank = Present',
          onChanged: (v) => onChanged(entry.copyWith(endDate: v)),
        ),
        _InlineTextField(
          initialText: entry.details.join('\n'),
          labelText: 'Details (optional)',
          helperText: 'Honors, GPA, coursework - one per line',
          maxLines: 4,
          minLines: 2,
          onChanged: (v) => onChanged(
            entry.copyWith(details: v.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()),
          ),
        ),
      ],
    );
  }
}

class _ProjectEntryCard extends StatelessWidget {
  const _ProjectEntryCard({super.key, required this.entry, required this.onChanged, required this.onRemove});

  final ProjectBlock entry;
  final ValueChanged<ProjectBlock> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EntryCardShell(
      onRemove: onRemove,
      fields: [
        _InlineTextField(
          initialText: entry.name,
          labelText: 'Project name',
          onChanged: (v) => onChanged(entry.copyWith(name: v)),
        ),
        _InlineTextField(
          initialText: entry.link ?? '',
          labelText: 'Link (optional)',
          onChanged: (v) => onChanged(entry.copyWith(link: v)),
        ),
        _InlineTextField(
          initialText: entry.bullets.join('\n'),
          labelText: 'Bullets',
          helperText: 'One per line',
          maxLines: 6,
          minLines: 3,
          onChanged: (v) => onChanged(
            entry.copyWith(bullets: v.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()),
          ),
        ),
      ],
    );
  }
}

class _CertificationEntryCard extends StatelessWidget {
  const _CertificationEntryCard({super.key, required this.entry, required this.onChanged, required this.onRemove});

  final CertificationBlock entry;
  final ValueChanged<CertificationBlock> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EntryCardShell(
      onRemove: onRemove,
      fields: [
        _InlineTextField(
          initialText: entry.name,
          labelText: 'Certification name',
          onChanged: (v) => onChanged(entry.copyWith(name: v)),
        ),
        _InlineTextField(
          initialText: entry.issuer,
          labelText: 'Issuer',
          onChanged: (v) => onChanged(entry.copyWith(issuer: v)),
        ),
        _InlineTextField(
          initialText: entry.issuedDate ?? '',
          labelText: 'Issued date (optional)',
          onChanged: (v) => onChanged(entry.copyWith(issuedDate: v)),
        ),
      ],
    );
  }
}

class _SkillEntryCard extends StatelessWidget {
  const _SkillEntryCard({super.key, required this.entry, required this.onChanged, required this.onRemove});

  final SkillEntry entry;
  final ValueChanged<SkillEntry> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return _EntryCardShell(
      onRemove: onRemove,
      fields: [
        _InlineTextField(
          initialText: entry.name,
          labelText: 'Skill',
          onChanged: (v) => onChanged(entry.copyWith(name: v)),
        ),
      ],
    );
  }
}
