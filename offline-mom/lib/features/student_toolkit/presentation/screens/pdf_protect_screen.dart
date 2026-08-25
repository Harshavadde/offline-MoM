import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offline_mom/services/pdf_security/pdf_permissions.dart';

import '../../../../shared/widgets/empty_state.dart';
import '../providers/pdf_protect_providers.dart';
import '../toolkit_snackbars.dart';

/// Protect PDF (P0-8) - pick a plain PDF, set a password + permissions,
/// confirm, save a new protected copy. The original file is never touched.
class PdfProtectScreen extends ConsumerWidget {
  const PdfProtectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(protectPdfControllerProvider);
    final notifier = ref.read(protectPdfControllerProvider.notifier);

    ref.listen<ProtectPdfState>(protectPdfControllerProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(state.isDone ? 'Protected' : 'Protect PDF')),
      body: SafeArea(
        child: switch ((state.isEmpty, state.isDone)) {
          (true, _) => _PickPrompt(isBusy: state.isBusy, notifier: notifier),
          (false, false) => _SetupBody(state: state, notifier: notifier),
          (false, true) => _ResultBody(state: state, notifier: notifier),
        },
      ),
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({required this.isBusy, required this.notifier});
  final bool isBusy;
  final ProtectPdfController notifier;

  @override
  Widget build(BuildContext context) {
    if (isBusy) return const Center(child: CircularProgressIndicator());
    return EmptyState(
      icon: Icons.lock_outline_rounded,
      title: 'Add a password to a PDF',
      message: 'Pick a PDF, choose a password and what it should allow - '
          'fully offline, real encryption. Your original file is never changed.',
      actions: [
        FilledButton.icon(
          onPressed: notifier.pickPdf,
          icon: const Icon(Icons.folder_open_outlined),
          label: const Text('Choose a PDF'),
        ),
      ],
    );
  }
}

class _SetupBody extends StatefulWidget {
  const _SetupBody({required this.state, required this.notifier});
  final ProtectPdfState state;
  final ProtectPdfController notifier;

  @override
  State<_SetupBody> createState() => _SetupBodyState();
}

class _SetupBodyState extends State<_SetupBody> {
  bool _obscure = true;

  Future<void> _confirmAndProtect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create protected PDF?'),
        content: const Text('Your original PDF will remain unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Protect PDF')),
        ],
      ),
    );
    if (confirmed == true) await widget.notifier.protect();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    if (state.isBusy && state.pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final permissions = state.permissions;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('${state.pages.length} page${state.pages.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: state.pages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                state.pages[index],
                width: 84,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onChanged: widget.notifier.setPassword,
        ),
        const SizedBox(height: 12),
        TextField(
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Confirm password',
            errorText: state.confirmPassword.isNotEmpty && !state.passwordsMatch
                ? 'Passwords don\'t match'
                : null,
          ),
          onChanged: widget.notifier.setConfirmPassword,
        ),
        const SizedBox(height: 20),
        Text('Security', style: Theme.of(context).textTheme.titleSmall),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow printing'),
          value: permissions.allowPrinting,
          onChanged: (v) => widget.notifier.setPermissions(
            _copyPermissions(permissions, allowPrinting: v),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow copying text'),
          value: permissions.allowCopying,
          onChanged: (v) => widget.notifier.setPermissions(
            _copyPermissions(permissions, allowCopying: v),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow editing'),
          value: permissions.allowModify,
          onChanged: (v) => widget.notifier.setPermissions(
            _copyPermissions(permissions, allowModify: v),
          ),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Allow annotations'),
          value: permissions.allowAnnotations,
          onChanged: (v) => widget.notifier.setPermissions(
            _copyPermissions(permissions, allowAnnotations: v),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: state.canProtect ? _confirmAndProtect : null,
          icon: state.isBusy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.lock_outline_rounded),
          label: const Text('Protect PDF'),
        ),
      ],
    );
  }
}

// Local helper: PdfPermissions itself has no copyWith (a deliberately tiny,
// immutable value class - see pdf_permissions.dart) since production code
// only ever constructs it once per protect() call; the UI needs to toggle
// individual checkboxes, so this small local helper fills that one gap
// without adding a copyWith the real service logic never uses.
PdfPermissions _copyPermissions(
  PdfPermissions base, {
  bool? allowPrinting,
  bool? allowCopying,
  bool? allowModify,
  bool? allowAnnotations,
}) {
  return PdfPermissions(
    allowPrinting: allowPrinting ?? base.allowPrinting,
    allowHighQualityPrinting: base.allowHighQualityPrinting,
    allowCopying: allowCopying ?? base.allowCopying,
    allowModify: allowModify ?? base.allowModify,
    allowAnnotations: allowAnnotations ?? base.allowAnnotations,
  );
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({required this.state, required this.notifier});
  final ProtectPdfState state;
  final ProtectPdfController notifier;

  @override
  Widget build(BuildContext context) {
    final saved = state.savedFile != null;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(Icons.lock_rounded, size: 48),
                      const SizedBox(height: 12),
                      Text('This PDF is now password protected',
                          style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      const Text(
                        'Your original file was not changed.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.pages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(
                state.pages[index],
                width: 84,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
              ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Visual content is unchanged (${state.pages.length} page${state.pages.length == 1 ? '' : 's'}) - '
                'only opening the file now requires the password.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: saved
                ? null
                : () async {
                    await notifier.save();
                    if (!context.mounted) return;
                    showSavedToRecentFilesSnackBar(context);
                  },
            icon: Icon(saved ? Icons.check_rounded : Icons.save_alt_rounded),
            label: Text(saved ? 'Saved' : 'Save'),
          ),
        ),
      ],
    );
  }
}
