// Exercises ToolkitFilesScreen (P0-9, File-Manager Parity - replaces
// toolkit_recent_files_screen_test.dart's coverage, ported onto the new
// tabbed All Files/Recent/Favorites/Folders structure, plus new scenarios
// for search/sort/folders/multi-select/bulk-delete/missing-file/
// duplicate-name). Mirrors chat_history_screen_test.dart's runAsync +
// bounded real-time pump loop pattern.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/student_toolkit/presentation/screens/toolkit_files_screen.dart';
import 'package:offline_mom/models/toolkit_file.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/repositories/toolkit_file_repository.dart';
import 'package:offline_mom/repositories/toolkit_folder_repository.dart';

import '../../test_helpers/test_database.dart';

// This screen embeds `printing`'s PdfPreview directly for .pdf files, which
// calls the 'net.nfet.printing' MethodChannel unconditionally, before its
// own Printing.info() future resolves - see
// resume_template_detail_screen_test.dart's identical comment/pattern.
// Answering 'printingInfo' with canRaster:false makes PdfPreview show its
// own onError builder instead of crashing or falling back to Flutter's
// default (release-mode-textless) ErrorWidget.
const MethodChannel _printingChannel = MethodChannel('net.nfet.printing');

Future<void> settle(WidgetTester tester, {int iterations = 20}) async {
  for (var i = 0; i < iterations; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  Widget buildApp(ToolkitFileRepository fileRepository, SqfliteToolkitFolderRepository folderRepository) {
    return ProviderScope(
      overrides: [
        toolkitFileRepositoryProvider.overrideWithValue(fileRepository),
        toolkitFolderRepositoryProvider.overrideWithValue(folderRepository),
      ],
      child: const MaterialApp(home: ToolkitFilesScreen()),
    );
  }

  Future<int> insertFile(
    ToolkitFileRepository repository, {
    required String title,
    required String outputPath,
    DateTime? createdAt,
    bool isFavorite = false,
    int fileSizeBytes = 50000,
  }) {
    final now = createdAt ?? DateTime.now();
    return repository.insert(
      ToolkitFile(
        id: null,
        toolType: ToolkitToolType.imageCompress,
        title: title,
        outputPath: outputPath,
        fileSizeBytes: fileSizeBytes,
        originalFileSizeBytes: 200000,
        isFavorite: isFavorite,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  testWidgets('shows the empty state when there are no saved files yet', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());

      await tester.pumpWidget(buildApp(SqfliteToolkitFileRepository(db), SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      expect(find.text('No files yet'), findsOneWidget);
    });
  });

  testWidgets('the Recent tab lists a saved file under the Today header with its reduction '
      'percentage', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      final tempFile = await File(
        '${Directory.systemTemp.path}/toolkit_files_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      await insertFile(repository, title: 'passport_photo', outputPath: tempFile.path);

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);
      await tester.tap(find.text('Recent'));
      await settle(tester);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('passport_photo'), findsOneWidget);
      expect(find.text('-75%'), findsOneWidget);
    });
  });

  testWidgets('renaming a file (via the overflow menu) updates the visible title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      final tempFile = await File(
        '${Directory.systemTemp.path}/toolkit_files_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      await insertFile(repository, title: 'Draft name', outputPath: tempFile.path);

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField), 'Final name');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Final name'), findsOneWidget);
      expect(find.text('Draft name'), findsNothing);
    });
  });

  testWidgets('tapping the favorite star toggles it filled/outlined', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      final tempFile = await File(
        '${Directory.systemTemp.path}/toolkit_files_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
      ).writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });
      await insertFile(repository, title: 'photo', outputPath: tempFile.path);

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      expect(find.byIcon(Icons.star_outline_rounded), findsOneWidget);

      await tester.tap(find.byTooltip('Favorite'));
      await settle(tester);

      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      expect(find.byIcon(Icons.star_outline_rounded), findsNothing);
    });
  });

  testWidgets('the Favorites tab shows only starred files', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Starred', outputPath: '/nonexistent/starred.jpg', isFavorite: true);
      await insertFile(repository, title: 'Not starred', outputPath: '/nonexistent/other.jpg');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);
      await tester.tap(find.text('Favorites'));
      await settle(tester);

      expect(find.text('Starred'), findsOneWidget);
      expect(find.text('Not starred'), findsNothing);
    });
  });

  testWidgets('search filters the All Files tab by title', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Scholarship Form', outputPath: '/nonexistent/a.jpg');
      await insertFile(repository, title: 'Passport Photo', outputPath: '/nonexistent/b.jpg');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      await tester.tap(find.byTooltip('Search'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'photo');
      await settle(tester);

      expect(find.text('Passport Photo'), findsOneWidget);
      expect(find.text('Scholarship Form'), findsNothing);
    });
  });

  testWidgets('sort reorders the All Files tab by name (A-Z)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Zebra', outputPath: '/nonexistent/z.jpg', createdAt: DateTime(2026, 1, 1));
      await insertFile(repository, title: 'Apple', outputPath: '/nonexistent/a.jpg', createdAt: DateTime(2026, 1, 2));

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);
      // Default sort (newest first) - Apple was created later, so it's on top.
      expect(tester.getTopLeft(find.text('Apple')).dy, lessThan(tester.getTopLeft(find.text('Zebra')).dy));

      await tester.tap(find.byTooltip('Sort'));
      await settle(tester);
      await tester.tap(find.text('Name (A-Z)'));
      await settle(tester);

      expect(tester.getTopLeft(find.text('Apple')).dy, lessThan(tester.getTopLeft(find.text('Zebra')).dy));
    });
  });

  testWidgets('two files may share the same title (duplicate names are simply allowed, not an '
      'error)', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Duplicate', outputPath: '/nonexistent/one.jpg');
      await insertFile(repository, title: 'Duplicate', outputPath: '/nonexistent/two.jpg');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      expect(find.text('Duplicate'), findsNWidgets(2));
    });
  });

  testWidgets('a file whose underlying output was deleted outside the app shows "Missing" '
      'instead of crashing, and tapping it does not attempt to open it', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Ghost file', outputPath: '/definitely/does/not/exist.jpg');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      expect(find.text('Missing'), findsOneWidget);

      await tester.tap(find.text('Ghost file'));
      await settle(tester);

      expect(find.textContaining('could not be found'), findsOneWidget);
      // No preview dialog should have opened.
      expect(find.text('Close'), findsNothing);
    });
  });

  testWidgets('Folders: create a folder, it starts empty, then a file can be moved into it and '
      'is found there', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'Report', outputPath: '/nonexistent/report.pdf');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      await tester.tap(find.text('Folders'));
      await settle(tester);
      expect(find.text('No folders yet'), findsOneWidget);

      await tester.tap(find.text('New folder'));
      await settle(tester);
      await tester.enterText(find.byType(TextFormField), 'Coursework');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('Coursework'), findsOneWidget);
      expect(find.text('0 files'), findsOneWidget);

      await tester.tap(find.text('Coursework'));
      await settle(tester);
      expect(find.text('This folder is empty'), findsOneWidget);

      await tester.tap(find.byTooltip('Back to folders'));
      await settle(tester);

      // Move "Report" into the folder from the All Files tab.
      await tester.tap(find.text('All Files'));
      await settle(tester);
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      await tester.tap(find.text('Move to folder'));
      await settle(tester);
      await tester.tap(find.text('Coursework'));
      await settle(tester);

      await tester.tap(find.text('Folders'));
      await settle(tester);
      expect(find.text('1 file'), findsOneWidget);
      await tester.tap(find.text('Coursework'));
      await settle(tester);
      expect(find.text('Report'), findsOneWidget);
    });
  });

  testWidgets('multi-select: selecting two files and bulk-deleting removes both after '
      'confirmation', (tester) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      addTearDown(() => db.close());
      final repository = SqfliteToolkitFileRepository(db);
      await insertFile(repository, title: 'First', outputPath: '/nonexistent/first.jpg');
      await insertFile(repository, title: 'Second', outputPath: '/nonexistent/second.jpg');

      await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
      await settle(tester);

      await tester.tap(find.byTooltip('Select'));
      await settle(tester);
      await tester.tap(find.byType(Checkbox).first);
      await settle(tester);
      await tester.tap(find.byType(Checkbox).last);
      await settle(tester);

      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete selected'));
      await settle(tester);
      // showDestructiveConfirmDialog's default confirm button label.
      await tester.tap(find.text('Delete'));
      await settle(tester);

      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
      expect(await repository.getAll(), isEmpty);
    });
  });

  group('Toolkit productization pass, P0-1 ("shows blank when preview" fix)', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        _printingChannel,
        (call) async => call.method == 'printingInfo' ? <String, dynamic>{'canRaster': false} : null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_printingChannel, null);
    });

    testWidgets(
      'opening a PDF file\'s preview when raster is unavailable (canRaster: false) shows a real, '
      'readable message instead of Flutter\'s default textless ErrorWidget',
      (tester) async {
        await tester.runAsync(() async {
          final db = await openTestDatabase();
          addTearDown(() => db.close());
          final repository = SqfliteToolkitFileRepository(db);
          final tempFile = await File(
            '${Directory.systemTemp.path}/toolkit_files_test_${DateTime.now().microsecondsSinceEpoch}.pdf',
          ).writeAsBytes([1, 2, 3]);
          addTearDown(() async {
            if (await tempFile.exists()) await tempFile.delete();
          });
          await insertFile(repository, title: 'scanned_form', outputPath: tempFile.path);

          await tester.pumpWidget(buildApp(repository, SqfliteToolkitFolderRepository(db)));
          await settle(tester);

          await tester.tap(find.text('scanned_form'));
          await settle(tester, iterations: 40);

          expect(find.text('Preview unavailable'), findsOneWidget);
          expect(find.byType(ErrorWidget), findsNothing);
        });
      },
    );
  });
}
