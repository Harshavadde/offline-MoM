// Exercises ImageCompressScreen end-to-end: pick -> configure (preset) ->
// compress -> result -> save. Mirrors test/features/chat/chat_history_screen_test.dart's
// runAsync + bounded real-time pump loop pattern for genuinely-real async
// I/O (sqflite, compute()) under AutomatedTestWidgetsFlutterBinding, plus
// storage_providers_test.dart's fake path_provider (save() writes a real
// file via newToolkitOutputPath()).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:offline_mom/features/student_toolkit/presentation/screens/image_compress_screen.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/services/toolkit/toolkit_image_picker_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../test_helpers/test_database.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this._path);
  final String _path;

  @override
  Future<String?> getApplicationDocumentsPath() async => _path;
}

Uint8List _syntheticPhotoBytes({int width = 400, int height = 300}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixelRgb(x, y, x * 255 ~/ width, y * 255 ~/ height, (x ^ y) % 256);
    }
  }
  return img.encodeJpg(image, quality: 100);
}

Future<void> settle(WidgetTester tester, {int iterations = 30}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Widget buildApp({
    required ToolkitFileRepository repository,
    required FakeToolkitImagePickerService picker,
  }) {
    return ProviderScope(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(repository),
        toolkitImagePickerServiceProvider.overrideWithValue(picker),
      ],
      child: const MaterialApp(home: ImageCompressScreen()),
    );
  }

  testWidgets('shows the pick prompt with no image selected yet', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(buildApp(
        repository: SqfliteToolkitFileRepository(db),
        picker: FakeToolkitImagePickerService(),
      ));
      await settle(tester, iterations: 5);

      expect(find.text('Choose from Gallery'), findsOneWidget);
      expect(find.text('Take a Photo'), findsOneWidget);
    });
  });

  testWidgets(
      'full flow: pick from gallery -> compress with a preset -> save writes a Recent Files row',
      (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      final docsDir = await Directory.systemTemp.createTemp('image_compress_screen_test_');
      addTearDown(() async {
        if (await docsDir.exists()) await docsDir.delete(recursive: true);
      });
      PathProviderPlatform.instance = _FakePathProviderPlatform(docsDir.path);

      // Tall enough that the configure/result steps' scrollable content
      // (preview image, preset chips, action button) all fit without
      // needing a manual scroll gesture to reach it.
      await tester.binding.setSurfaceSize(const Size(412, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final picker = FakeToolkitImagePickerService(
        galleryResult:
            PickedToolkitImage(fileName: 'passport.jpg', bytes: _syntheticPhotoBytes()),
      );

      await tester.pumpWidget(buildApp(repository: repository, picker: picker));
      await settle(tester, iterations: 5);

      await tester.tap(find.text('Choose from Gallery'));
      await settle(tester);

      // Now on the configure step, Presets mode by default with Passport
      // pre-selected.
      expect(find.text('Compress'), findsOneWidget);

      await tester.tap(find.text('Compress'));
      await settle(tester);

      // Result step: reduction chip + Save button.
      expect(find.textContaining('% size'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Saved'), findsOneWidget);
      final rows = await repository.getAll();
      expect(rows, hasLength(1));
      expect(rows.single.title, 'passport');
      expect(await File(rows.single.outputPath).exists(), isTrue);
    });
  });
}
