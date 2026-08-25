// Tests OfflineReadinessScreen (R-11 P1 fix: "must be user-friendly") -
// confirms the screen renders plain, capability-oriented language and never
// leaks the implementation detail OfflineReadinessCheck.label/.detail carry
// internally (model filenames, "llama.cpp"/"whisper.cpp", "SQLite"). Does
// not re-test OfflineReadinessService's own pass/fail logic - that's
// offline_readiness_service_test.dart's job; this screen is a pure
// presentation layer over a fixed, injected report.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:offline_mom/core/router/route_paths.dart';
import 'package:offline_mom/features/settings/presentation/providers/offline_readiness_providers.dart';
import 'package:offline_mom/features/settings/presentation/screens/offline_readiness_screen.dart';
import 'package:offline_mom/services/offline/offline_readiness_service.dart';

Future<void> pumpScreen(WidgetTester tester, OfflineReadinessReport report) async {
  final router = GoRouter(
    initialLocation: RoutePaths.offlineReadiness,
    routes: [
      GoRoute(path: RoutePaths.offlineReadiness, builder: (_, __) => const OfflineReadinessScreen()),
      GoRoute(path: RoutePaths.aiModels, builder: (_, __) => const Scaffold(body: Text('AI MODELS SCREEN'))),
    ],
  );

  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [offlineReadinessReportProvider.overrideWith((ref) async => report)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    // The screen's own private _liveConnectivityProvider calls the real
    // hasInternetConnection() (a real InternetAddress.lookup with a real 5s
    // Timer-based .timeout()) - this is a private, file-local provider this
    // test file has no way to override, so the real Timer must actually be
    // allowed to fire (via runAsync's real event loop) and be awaited here,
    // or it's still pending when the widget tree is disposed at test
    // teardown - `flutter_test` treats a leftover Timer as a hard failure
    // ("A Timer is still pending even after the widget tree was disposed").
    await Future<void>.delayed(const Duration(seconds: 6));
    await tester.pump();
  });
}

void main() {
  const readyReport = OfflineReadinessReport(checks: [
    OfflineReadinessCheck(
      label: 'AI language model',
      passed: true,
      detail: 'qwen2.5-1.5b-instruct-q4_k_m.gguf is installed and active.',
    ),
    OfflineReadinessCheck(
      label: 'Embedding model (semantic search)',
      passed: true,
      detail: 'embeddinggemma-300m-q8_0.gguf is installed and active.',
    ),
    OfflineReadinessCheck(
      label: 'Speech-to-text model',
      passed: true,
      detail: 'ggml-small.bin is installed and active.',
    ),
    OfflineReadinessCheck(
      label: 'OCR model',
      passed: false,
      required: false,
      detail: 'Not installed - only needed for Searchable PDF.',
    ),
    OfflineReadinessCheck(
      label: 'Local database available',
      passed: true,
      detail: 'On-device SQLite - no network round-trip for any read or write.',
    ),
    OfflineReadinessCheck(
      label: 'AI inference runs entirely on-device',
      passed: true,
      detail: 'llama.cpp (LLM/embedding) and whisper.cpp (speech-to-text) run locally.',
    ),
    OfflineReadinessCheck(
      label: 'No network required for inference, search, OCR, or PDF generation',
      passed: true,
      detail: 'Network is used only for one-time model downloads.',
    ),
  ]);

  const notReadyReport = OfflineReadinessReport(checks: [
    OfflineReadinessCheck(
      label: 'AI language model',
      passed: false,
      detail: 'Not installed. Download and activate one in Model Manager.',
    ),
    OfflineReadinessCheck(
      label: 'Embedding model (semantic search)',
      passed: true,
      detail: 'embeddinggemma-300m-q8_0.gguf is installed and active.',
    ),
    OfflineReadinessCheck(
      label: 'Speech-to-text model',
      passed: true,
      detail: 'ggml-small.bin is installed and active.',
    ),
  ]);

  void expectNoLeakedImplementationDetail(WidgetTester tester) {
    for (final leaked in [
      'llama.cpp',
      'whisper.cpp',
      'SQLite',
      'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      'embeddinggemma-300m-q8_0.gguf',
      'ggml-small.bin',
      'Embedding model (semantic search)',
      'On-device SQLite',
    ]) {
      expect(find.textContaining(leaked), findsNothing, reason: '"$leaked" leaked to the user-facing screen');
    }
  }

  testWidgets('ready state: friendly banner, plain capability labels, no implementation detail',
      (tester) async {
    await pumpScreen(tester, readyReport);

    expect(find.text('You\'re ready to use the app offline'), findsOneWidget);
    expect(
      find.text('Your required tools are ready. You can use the app without an internet connection.'),
      findsOneWidget,
    );
    expect(find.text('Summaries and AI writing help'), findsOneWidget);
    expect(find.text('Search your saved information'), findsOneWidget);
    expect(find.text('Record and transcribe meetings'), findsOneWidget);
    expect(find.text('Searchable PDF and image scanning'), findsOneWidget);
    expect(find.text('Optional feature. Install this to use it.'), findsOneWidget);
    expect(find.text('OPTIONAL'), findsOneWidget);
    // Always-available, non-AI capabilities are shown regardless of report state.
    expect(find.text('Create and edit resumes'), findsOneWidget);

    expectNoLeakedImplementationDetail(tester);
  });

  testWidgets('not-ready state: says what to do next in plain language, offers a download action',
      (tester) async {
    await pumpScreen(tester, notReadyReport);

    expect(find.text('A few things to set up first'), findsOneWidget);
    expect(
      find.text('Download the required AI tools below to use every feature without an internet connection.'),
      findsOneWidget,
    );
    expect(find.text('Download required to use this feature offline.'), findsOneWidget);
    expect(find.text('Download required tools'), findsOneWidget);

    expectNoLeakedImplementationDetail(tester);
  });

  testWidgets('the download action navigates to the AI models screen', (tester) async {
    await pumpScreen(tester, notReadyReport);

    await tester.tap(find.text('Download required tools'));
    await tester.pumpAndSettle();

    expect(find.text('AI MODELS SCREEN'), findsOneWidget);
  });
}
