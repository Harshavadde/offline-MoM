// Tests showResumeModelUpgradePromptDialog
// (lib/features/career/resume/presentation/screens/resume_model_upgrade_prompt_screen.dart)
// and ResumeListScreen's own gate for it (docs/v3/01-prd.md §13, FR3-15/
// FR3-16, Milestone 4) - in particular the model-upgrade-declined-still-
// fully-functional requirement the PRD names directly: declining must never
// block or degrade access to the Resume feature, only suggestion quality.
// Mirrors resume_suggestion_review_screen_test.dart's precedent of real,
// Sqflite-backed repositories (openTestDatabase()) run inside
// tester.runAsync(), rather than mocking the DI graph.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_list_screen.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_model_upgrade_prompt_screen.dart';
import 'package:offline_mom/models/app_settings.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/installed_model_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/settings_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:offline_mom/services/device/device_capability_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

/// A minimal in-memory [SettingsRepository] - this feature has no existing
/// fake for it (only the real Hive-backed implementation), so this test
/// provides its own small one, mirroring
/// resume_suggestion_review_screen_test.dart's own local-fake precedent.
class _InMemorySettingsRepository implements SettingsRepository {
  _InMemorySettingsRepository(this._settings);
  AppSettings _settings;

  @override
  AppSettings getSettings() => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    _settings = settings;
  }
}

class _DialogHost extends ConsumerWidget {
  const _DialogHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showResumeModelUpgradePromptDialog(context, ref),
          child: const Text('Open prompt'),
        ),
      ),
    );
  }
}

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  late Database db;
  late _InMemorySettingsRepository settingsRepository;

  setUp(() async {
    db = await openTestDatabase();
    settingsRepository = _InMemorySettingsRepository(const AppSettings());
  });

  tearDown(() => db.close());

  List<Override> baseOverrides() {
    return [
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      resumeRepositoryProvider.overrideWithValue(SqfliteResumeRepository(db)),
      resumeBlockRepositoryProvider.overrideWithValue(SqfliteResumeBlockRepository(db)),
      experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
      educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
      projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
      certificationBlockRepositoryProvider.overrideWithValue(SqfliteCertificationBlockRepository(db)),
      skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
      installedModelRepositoryProvider.overrideWithValue(SqfliteInstalledModelRepository(db)),
      deviceCapabilityServiceProvider.overrideWithValue(FakeDeviceCapabilityService(ramMb: 3000)),
    ];
  }

  group('showResumeModelUpgradePromptDialog', () {
    testWidgets('shows the exact PRD-worded explanation and offers to decline', (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: const MaterialApp(home: _DialogHost()),
          ),
        );
        await tester.tap(find.text('Open prompt'));
        await settle(tester);

        expect(
          find.textContaining(
            'For better resume results, you can download the recommended model',
          ),
          findsOneWidget,
        );
        expect(find.text('Not now'), findsOneWidget);
        expect(find.text('Download'), findsOneWidget);
      });
    });

    testWidgets(
        'declining (Not now) closes the dialog, marks the prompt seen, and never touches the '
        'active model - re-verifies FR3-16 directly', (tester) async {
      late ProviderContainer container;
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const MaterialApp(home: _DialogHost());
              },
            ),
          ),
        );
        await tester.tap(find.text('Open prompt'));
        await settle(tester);
        expect(container.read(settingsControllerProvider).hasSeenResumeModelUpgradePrompt, isFalse);

        await tester.tap(find.text('Not now'));
        await settle(tester);

        final settings = container.read(settingsControllerProvider);
        expect(settings.hasSeenResumeModelUpgradePrompt, isTrue);
        // The baseline model remains active - declining never silently
        // switches, downloads, or otherwise changes which model is used.
        expect(settings.activeLlmModelId, isNull);
        expect(find.text('Get better resume results'), findsNothing);
      });
    });
  });

  group('ResumeListScreen model-upgrade gate', () {
    testWidgets(
        'once the prompt has already been seen, the Resume feature is fully usable with no '
        'dialog and no dependency on the upgrade tier - FR3-16 at the actual entry point',
        (tester) async {
      settingsRepository = _InMemorySettingsRepository(
        const AppSettings(hasSeenResumeModelUpgradePrompt: true),
      );

      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: const MaterialApp(home: ResumeListScreen()),
          ),
        );
        await settle(tester);

        expect(find.text('Get better resume results'), findsNothing);
        expect(find.text('No resumes yet'), findsOneWidget);
        expect(find.text('New resume'), findsWidgets);
      });
    });
  });
}
