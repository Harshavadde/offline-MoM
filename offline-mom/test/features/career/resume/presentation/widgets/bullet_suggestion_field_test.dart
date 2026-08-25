// Tests BulletSuggestionField
// (lib/features/career/resume/presentation/widgets/bullet_suggestion_field.dart) -
// Tier 1 heuristic hints, Tier 2 debounced AI trigger, accept/reject.
// Real wall-clock delays via tester.runAsync(), mirroring this codebase's
// own established debounce-testing discipline (see chat_screen_test.dart's
// settle() helper).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/generate_bullet_rewrite_use_case.dart';
import 'package:offline_mom/features/career/resume/presentation/widgets/bullet_suggestion_field.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/shared/widgets/ai_disclaimer.dart';

import '../../../../../test_helpers/fake_ai_engines.dart';

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late TextEditingController controller;

  setUp(() {
    controller = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpField(WidgetTester tester, {String? answer, Object? errorToThrow}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          generateBulletRewriteUseCaseProvider.overrideWithValue(
            GenerateBulletRewriteUseCase(
              llmEngine: FakeLlmEngine(answer: answer, errorToThrow: errorToThrow),
              llmRequestQueue: DefaultLlmRequestQueue(),
            ),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: BulletSuggestionField(
              controller: controller,
              entryContextLabel: 'Backend Engineer at Acme Corp',
            ),
          ),
        ),
      ),
    );
  }

  group('Tier 1 heuristic hints (debounced)', () {
    testWidgets('a weak-verb bullet shows a hint only after the debounce pause elapses',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester);
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Helped the team ship things.');
        await tester.pump();

        // Immediately after typing, before the debounce fires, no hint yet.
        expect(find.textContaining('stronger action verb'), findsNothing);

        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        expect(find.textContaining('stronger action verb'), findsOneWidget);
      });
    });

    testWidgets('a strong, quantified bullet shows no hints after the debounce pause', (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester);
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Reduced latency by 40%.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        expect(find.textContaining('stronger action verb'), findsNothing);
        expect(find.textContaining('measurable detail'), findsNothing);
      });
    });
  });

  group('Tier 2 trigger gating', () {
    testWidgets('the "Improve with AI" button is disabled while the debounce is pending',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester);
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await tester.pump();

        final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Improve with AI'));
        expect(button.onPressed, isNull);
      });
    });

    testWidgets('the "Improve with AI" button becomes enabled once the debounce settles',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester);
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Improve with AI'));
        expect(button.onPressed, isNotNull);
      });
    });
  });

  group('Tier 2 accept/reject', () {
    testWidgets('accepting a suggestion replaces the field text and clears the preview',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester, answer: 'Orchestrated dashboard delivery end-to-end.');
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Improve with AI'));
        await settle(tester);

        expect(find.text('Orchestrated dashboard delivery end-to-end.'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
        await tester.pump();

        expect(controller.text, 'Orchestrated dashboard delivery end-to-end.');
        expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
      });
    });

    testWidgets('rejecting a suggestion leaves the field text unchanged', (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester, answer: 'Orchestrated dashboard delivery end-to-end.');
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Improve with AI'));
        await settle(tester);

        await tester.tap(find.widgetWithText(TextButton, 'Reject'));
        await tester.pump();

        expect(controller.text, 'Built the dashboard.');
        expect(find.widgetWithText(TextButton, 'Reject'), findsNothing);
      });
    });

    testWidgets('R-8.1: the AI-generated suggestion preview shows the shared AiDisclaimer',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester, answer: 'Orchestrated dashboard delivery end-to-end.');
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Improve with AI'));
        await settle(tester);

        expect(find.byType(AiDisclaimer), findsOneWidget);
      });
    });

    testWidgets('a flagged suggestion shows a review-carefully warning in the preview',
        (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester, answer: 'Orchestrated Kubernetes deployments, improving uptime by 40%.');
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Improve with AI'));
        await settle(tester);

        expect(find.textContaining('Review carefully'), findsOneWidget);
      });
    });
  });

  group('model unavailable', () {
    testWidgets('a model failure shows an error message rather than crashing', (tester) async {
      await tester.runAsync(() async {
        await pumpField(tester, errorToThrow: StateError('model not downloaded'));
        await settle(tester);

        await tester.enterText(find.byType(TextField), 'Built the dashboard.');
        await Future<void>.delayed(BulletSuggestionField.debounceDuration + const Duration(milliseconds: 200));
        await tester.pump();

        await tester.tap(find.widgetWithText(TextButton, 'Improve with AI'));
        await settle(tester);

        expect(find.textContaining("Couldn't generate"), findsOneWidget);
      });
    });
  });
}
