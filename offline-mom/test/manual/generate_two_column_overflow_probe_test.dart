// Manual diagnostic script (Physical-Mobile-First Validation phase, task
// #131) - isolates the Balanced Two-Column overflow question with
// maximally distinguishable content: a short right rail (one Education
// entry) and a long left column (10 experience entries, guaranteed to
// overflow onto a second page), each bullet/line prefixed with a marker so
// column WIDTH on the continuation page is trivially readable from the
// rendered PDF's own text-wrapping, without relying on eyeballing a
// rendered image.
//
// Run with: flutter test test/manual/generate_two_column_overflow_probe_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/models/resume_snapshot.dart';
import 'package:offline_mom/services/resume/resume_template_renderer.dart';
import 'package:offline_mom/services/resume/template/resume_template_catalog.dart';

const _outputDir =
    r'C:\Users\azadmin\AppData\Local\Temp\claude\C--Projects-college-project\cf2d1868-b8a9-4a37-9334-ff68adc6154d\scratchpad\pdfs';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('probe: does the right rail stay reserved (blank) and the left column keep its narrower '
      'width on a Balanced Two-Column continuation page, or does the layout truly go full-width?',
      () async {
    final snapshot = ResumeSnapshot(
      resumeId: 1,
      compiledAt: DateTime(2026, 1, 1),
      profile: const ResumeSnapshotProfile(fullName: 'Probe Candidate', email: 'probe@example.com'),
      experience: [
        for (var i = 0; i < 10; i++)
          ResolvedExperienceEntry(
            sourceBlockId: i,
            role: 'LEFTCOLUMNMARKER Role $i LEFTCOLUMNMARKER',
            company: 'Company $i',
            startDate: '20${10 + i}-01',
            endDate: '20${11 + i}-01',
            bullets: [
              'LEFTCOLUMNMARKER bullet one for role $i describing a long enough sentence to wrap onto a second visual line if the column is narrow, which is exactly the point of this probe.',
              'LEFTCOLUMNMARKER bullet two for role $i, same purpose, more filler text to guarantee overflow onto additional pages for this synthetic long-career resume.',
            ],
          ),
      ],
      education: const [
        ResolvedEducationEntry(
          sourceBlockId: 100,
          institution: 'RIGHTCOLUMNMARKER University',
          degree: 'RIGHTCOLUMNMARKER B.S.',
          startDate: '2005',
          endDate: '2009',
        ),
      ],
    );

    const renderer = ResumeTemplateRenderer();
    final spec = ResumeTemplateCatalog.specById('two-column-right-warm');
    final bytes = await renderer.render(snapshot, spec);
    expect(bytes, isNotEmpty);

    final outDir = Directory(_outputDir)..createSync(recursive: true);
    final file = File('${outDir.path}/probe_two_column_overflow.pdf');
    await file.writeAsBytes(bytes);
    // ignore: avoid_print
    print('Wrote ${file.path} (${bytes.length} bytes)');
  });
}
