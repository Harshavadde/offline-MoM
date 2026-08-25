import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/shared/widgets/knowledge_source_card.dart';

void main() {
  Widget buildApp(Widget card) => MaterialApp(home: Scaffold(body: card));

  testWidgets('renders title, status and updated label', (tester) async {
    await tester.pumpWidget(
      buildApp(
        const KnowledgeSourceCard(
          icon: Icons.mic_none_rounded,
          title: 'Standup',
          updatedLabel: 'Jul 28, 2026 4:00 PM',
          statusLabel: 'Ready',
          statusColor: Colors.green,
        ),
      ),
    );

    expect(find.text('Standup'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.textContaining('Jul 28, 2026'), findsOneWidget);
  });

  testWidgets('shows size alongside the updated label when provided',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        const KnowledgeSourceCard(
          icon: Icons.description_outlined,
          title: 'Report',
          updatedLabel: 'Jul 28, 2026',
          sizeLabel: '1.2 MB',
          statusLabel: 'Ready',
          statusColor: Colors.green,
        ),
      ),
    );

    expect(find.textContaining('Jul 28, 2026 · 1.2 MB'), findsOneWidget);
  });

  testWidgets('shows Summary/Searchable indicators only when the source is '
      'actually ready (Phase 2B Knowledge Source card requirement)',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        const KnowledgeSourceCard(
          icon: Icons.mic_none_rounded,
          title: 'In progress meeting',
          updatedLabel: 'Jul 28, 2026',
          statusLabel: 'Transcribing 45%',
          statusColor: Colors.orange,
          progress: 0.45,
        ),
      ),
    );

    expect(find.text('Summary'), findsNothing);
    expect(find.text('Searchable'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('shows Summary/Searchable indicators once ready', (tester) async {
    await tester.pumpWidget(
      buildApp(
        const KnowledgeSourceCard(
          icon: Icons.mic_none_rounded,
          title: 'Finished meeting',
          updatedLabel: 'Jul 28, 2026',
          statusLabel: 'Ready',
          statusColor: Colors.green,
          isSummaryAvailable: true,
          isSearchable: true,
        ),
      ),
    );

    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Searchable'), findsOneWidget);
  });

  testWidgets('tapping the card invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      buildApp(
        KnowledgeSourceCard(
          icon: Icons.mic_none_rounded,
          title: 'Standup',
          updatedLabel: 'Jul 28, 2026',
          statusLabel: 'Ready',
          statusColor: Colors.green,
          onTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.text('Standup'));
    expect(tapped, isTrue);
  });

  testWidgets('swiping away with onDelete set shows a confirmation dialog '
      'and calls onDelete only once confirmed', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      buildApp(
        KnowledgeSourceCard(
          icon: Icons.mic_none_rounded,
          title: 'Standup',
          updatedLabel: 'Jul 28, 2026',
          statusLabel: 'Ready',
          statusColor: Colors.green,
          onDelete: () => deleted = true,
          dismissibleKey: const ValueKey('card-1'),
          deleteConfirmTitle: 'Delete meeting?',
        ),
      ),
    );

    await tester.drag(find.text('Standup'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Delete meeting?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
  });
}
