import 'package:flutter/material.dart';

/// Shows the app's one single-line text-input dialog shape (Batch 3, Design
/// System Consolidation) - every "name this" prompt in the app (create/
/// rename a folder, rename a document/meeting/conversation/toolkit file,
/// edit the display name) used to build its own near-identical `AlertDialog`
/// wrapping a `TextFormField`, seven times over. This is the single shared
/// version.
///
/// Deliberately has no `TextEditingController` - `TextFormField.initialValue`
/// + `onChanged` avoids owning a controller whose lifetime would need to
/// outlive `showDialog`'s returned Future (which completes at `pop()`,
/// before the dialog's own exit transition has finished rebuilding its
/// still-mounted `TextField` one more time - disposing a controller in a
/// `finally` right after that Future resolves races that last rebuild), the
/// same reasoning every one of the seven call sites this replaces already
/// carried in an identical doc comment.
///
/// Returns the trimmed entered text, or `null` if the dialog was cancelled
/// or dismissed (tapping outside, back button) - never an empty-vs-null
/// distinction the seven original call sites didn't already make themselves
/// (some reject an empty result, some don't; that validation stays with
/// each caller, unchanged, rather than being silently added or removed
/// here). Submitting via the keyboard's "done"/enter action also confirms -
/// two of the seven original dialogs already had this, the other five
/// didn't; standardized here as a small, genuine consistency fix rather
/// than a behavior change with any real downside.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String labelText,
  String? initialValue,
  String? helperText,
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
}) {
  var entered = initialValue ?? '';
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextFormField(
        initialValue: initialValue,
        autofocus: true,
        decoration: InputDecoration(labelText: labelText, helperText: helperText),
        onChanged: (value) => entered = value,
        onFieldSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(entered.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
