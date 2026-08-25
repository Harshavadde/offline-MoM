// Tests ResumePreviewScreen - Part J (template gallery/preview - "shows
// blank when preview" fix). This screen embeds `printing`'s PdfPreview
// directly, the exact same package widget resume_template_detail_screen.dart
// uses - see that file's own doc comment on why an unset `onError` falls
// back to Flutter's default `ErrorWidget`, whose message text is stripped
// entirely in release builds, leaving a bare textless box exactly matching
// the reported "blank preview" symptom. Mirrors
// resume_template_detail_screen_test.dart's exact `canRaster: false` mock
// pattern, since `Printing.raster`'s platform channel has no implementation
// under `flutter test`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/presentation/screens/resume_preview_screen.dart';
import 'package:offline_mom/models/resume.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/certification_block_repository.dart';
import 'package:offline_mom/repositories/education_block_repository.dart';
import 'package:offline_mom/repositories/experience_block_repository.dart';
import 'package:offline_mom/repositories/project_block_repository.dart';
import 'package:offline_mom/repositories/resume_block_repository.dart';
import 'package:offline_mom/repositories/resume_repository.dart';
import 'package:offline_mom/repositories/skill_entry_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../../test_helpers/test_database.dart';

const MethodChannel _printingChannel = MethodChannel('net.nfet.printing');

Future<void> settle(WidgetTester tester, {int iterations = 40}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ResumeRepository resumeRepository;

  setUp(() async {
    db = await openTestDatabase();
    resumeRepository = SqfliteResumeRepository(db);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _printingChannel,
      (call) async => call.method == 'printingInfo' ? <String, dynamic>{'canRaster': false} : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_printingChannel, null);
    return db.close();
  });

  List<Override> baseOverrides() {
    return [
      resumeRepositoryProvider.overrideWithValue(resumeRepository),
      resumeBlockRepositoryProvider.overrideWithValue(SqfliteResumeBlockRepository(db)),
      experienceBlockRepositoryProvider.overrideWithValue(SqfliteExperienceBlockRepository(db)),
      educationBlockRepositoryProvider.overrideWithValue(SqfliteEducationBlockRepository(db)),
      projectBlockRepositoryProvider.overrideWithValue(SqfliteProjectBlockRepository(db)),
      certificationBlockRepositoryProvider.overrideWithValue(SqfliteCertificationBlockRepository(db)),
      skillEntryRepositoryProvider.overrideWithValue(SqfliteSkillEntryRepository(db)),
    ];
  }

  Future<int> insertResume() {
    final now = DateTime(2026, 1, 1);
    return resumeRepository.insert(
      Resume(id: null, title: 'Test Resume', fullName: 'Jane Doe', createdAt: now, updatedAt: now),
    );
  }

  testWidgets(
    'Part J (template gallery/preview - "shows blank when preview" fix): when raster is '
    'unavailable (canRaster: false), the screen shows a real, readable message instead of '
    'Flutter\'s default textless ErrorWidget',
    (tester) async {
      await tester.runAsync(() async {
        final resumeId = await insertResume();
        await tester.pumpWidget(
          ProviderScope(
            overrides: baseOverrides(),
            child: MaterialApp(home: ResumePreviewScreen(resumeId: resumeId)),
          ),
        );
        await settle(tester);

        expect(find.text('Preview unavailable'), findsOneWidget);
        expect(find.byType(ErrorWidget), findsNothing);
      });
    },
  );
}
