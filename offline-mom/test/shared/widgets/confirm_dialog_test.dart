import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/shared/widgets/confirm_dialog.dart';

/// Tests the app's one shared destructive-confirmation dialog (Phase 4A,
/// ADR-031, docs/v2/implementation/03-decisions.md), which every delete
/// flow (meetings, documents, chat conversations, notes) now calls instead
/// of building its own near-identical `AlertDialog`.
void main() {
  testWidgets('tapping Cancel resolves to false and dismisses', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDestructiveConfirmDialog(
                  context,
                  title: 'Delete meeting?',
                  message: 'This can\'t be undone.',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete meeting?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Delete meeting?'), findsNothing);
  });

  testWidgets('tapping the destructive action resolves to true', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDestructiveConfirmDialog(
                  context,
                  title: 'Delete document?',
                  message: 'This can\'t be undone.',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('the destructive action button is styled with the error color, '
      'distinguishing it from a routine Save/Cancel action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDestructiveConfirmDialog(
                context,
                title: 'Delete conversation?',
                message: 'This can\'t be undone.',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Delete conversation?'));
    final scheme = Theme.of(context).colorScheme;

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'));
    final resolvedBackground = button.style?.backgroundColor?.resolve({});
    expect(resolvedBackground, scheme.error);
  });

  testWidgets('custom confirm/cancel labels are used verbatim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDestructiveConfirmDialog(
                context,
                title: 'Stop recording?',
                message: 'Leaving now will stop and save the current recording.',
                confirmLabel: 'Stop & save',
                cancelLabel: 'Keep recording',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Stop & save'), findsOneWidget);
    expect(find.text('Keep recording'), findsOneWidget);
  });
}
