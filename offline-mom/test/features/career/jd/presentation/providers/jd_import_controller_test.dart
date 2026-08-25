// Tests JdImportController through a ProviderContainer with only the file
// picker overridden (mirrors resume_import_controller_test.dart's pattern) -
// extraction/parsing here has no database dependency at all (JdParser is
// pure, the extractors are the same unmodified Documents-feature parsers),
// so no repository overrides are needed.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/jd/presentation/providers/jd_import_providers.dart';
import 'package:offline_mom/models/document.dart';
import 'package:offline_mom/providers/app_providers.dart';
import 'package:offline_mom/services/career/jd_import_file_picker_service.dart';

void main() {
  late Directory tempDir;
  late FakeJdImportFilePickerService picker;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jd_import_controller_test_');
    picker = FakeJdImportFilePickerService();
    container = ProviderContainer(
      overrides: [jdImportFilePickerServiceProvider.overrideWithValue(picker)],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<PickedJdImportFile> writePickedFile(String name, String content) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsString(content);
    return PickedJdImportFile(
      filePath: file.path,
      originalFilename: name,
      sourceType: DocumentSourceType.txt,
      fileSizeBytes: await file.length(),
    );
  }

  test('build() starts in JdImportIdle', () {
    expect(container.read(jdImportControllerProvider), isA<JdImportIdle>());
  });

  test('pickAndParse() with a cancelled picker (null result) returns to Idle', () async {
    picker.result = null;
    await container.read(jdImportControllerProvider.notifier).pickAndParse();
    expect(container.read(jdImportControllerProvider), isA<JdImportIdle>());
  });

  test('pickAndParse() with a picked file transitions to Reviewing with a parsed draft', () async {
    picker.result = await writePickedFile('jd.txt', 'REQUIREMENTS\n\n- Python\n');

    await container.read(jdImportControllerProvider.notifier).pickAndParse();

    final state = container.read(jdImportControllerProvider);
    expect(state, isA<JdImportReviewing>());
    expect((state as JdImportReviewing).draft.requirements, ['Python']);
  });

  test('pickAndParse() surfaces a picker failure as JdImportFailed', () async {
    picker.errorToThrow = JdImportPickException('The selected file is empty.');

    await container.read(jdImportControllerProvider.notifier).pickAndParse();

    final state = container.read(jdImportControllerProvider);
    expect(state, isA<JdImportFailed>());
    expect((state as JdImportFailed).message, 'The selected file is empty.');
  });

  test('confirm() only applies while Reviewing, and transitions to Confirmed', () async {
    final notifier = container.read(jdImportControllerProvider.notifier);

    notifier.confirm();
    expect(container.read(jdImportControllerProvider), isA<JdImportIdle>());

    picker.result = await writePickedFile('jd.txt', 'REQUIREMENTS\n\n- SQL\n');
    await notifier.pickAndParse();
    notifier.confirm();

    final state = container.read(jdImportControllerProvider);
    expect(state, isA<JdImportConfirmed>());
    expect((state as JdImportConfirmed).draft.requirements, ['SQL']);
  });

  test('reset() returns to Idle from any state', () async {
    picker.result = await writePickedFile('jd.txt', 'REQUIREMENTS\n\n- Java\n');
    final notifier = container.read(jdImportControllerProvider.notifier);
    await notifier.pickAndParse();
    expect(container.read(jdImportControllerProvider), isA<JdImportReviewing>());

    notifier.reset();

    expect(container.read(jdImportControllerProvider), isA<JdImportIdle>());
  });

  test('parseText() structures pasted JD text with no file/extraction step (R-7 §3)', () {
    final notifier = container.read(jdImportControllerProvider.notifier);

    notifier.parseText('REQUIREMENTS\n\n- Kubernetes\n- Terraform\n');

    final state = container.read(jdImportControllerProvider);
    expect(state, isA<JdImportReviewing>());
    expect((state as JdImportReviewing).draft.requirements, ['Kubernetes', 'Terraform']);
  });

  test('parseText() with blank/whitespace-only text is a no-op', () {
    final notifier = container.read(jdImportControllerProvider.notifier);

    notifier.parseText('   \n  ');

    expect(container.read(jdImportControllerProvider), isA<JdImportIdle>());
  });

  test('pickAndParse() is a no-op while already Processing (double-invocation guard)', () async {
    picker.result = await writePickedFile('jd.txt', 'REQUIREMENTS\n\n- Go\n');
    final notifier = container.read(jdImportControllerProvider.notifier);

    final first = notifier.pickAndParse();
    final second = notifier.pickAndParse();
    await Future.wait([first, second]);

    expect(container.read(jdImportControllerProvider), isA<JdImportReviewing>());
  });
}
