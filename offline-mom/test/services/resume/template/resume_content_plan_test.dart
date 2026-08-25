import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/template/resume_content_plan.dart';

void main() {
  test('mainLines returns only main-column lines, in order', () {
    const plan = ResumeContentPlan([
      ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe', column: ResumeContentColumn.sidebar),
      ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
      ResumeContentLine(ResumeContentLineKind.entryTitle, 'Engineer - Acme'),
    ]);

    expect(plan.mainLines.map((l) => l.text), ['Experience', 'Engineer - Acme']);
  });

  test('sidebarLines returns only sidebar-column lines, in order', () {
    const plan = ResumeContentPlan([
      ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe', column: ResumeContentColumn.sidebar),
      ResumeContentLine(ResumeContentLineKind.contact, 'jane@x.com', column: ResumeContentColumn.sidebar),
      ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
    ]);

    expect(plan.sidebarLines.map((l) => l.text), ['Jane Doe', 'jane@x.com']);
  });

  test('hasSidebar is false when every line is in the main column', () {
    const plan = ResumeContentPlan([ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe')]);
    expect(plan.hasSidebar, isFalse);
  });

  test('hasSidebar is true when at least one line is in the sidebar column', () {
    const plan = ResumeContentPlan([
      ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe', column: ResumeContentColumn.sidebar),
    ]);
    expect(plan.hasSidebar, isTrue);
  });

  test('sectionHeadingsInOrder returns only heading lines, preserving order across columns', () {
    const plan = ResumeContentPlan([
      ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe', column: ResumeContentColumn.sidebar),
      ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Skills', column: ResumeContentColumn.sidebar),
      ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Experience'),
      ResumeContentLine(ResumeContentLineKind.entryTitle, 'Engineer - Acme'),
      ResumeContentLine(ResumeContentLineKind.sectionHeading, 'Education'),
    ]);

    expect(plan.sectionHeadingsInOrder, ['Skills', 'Experience', 'Education']);
  });

  test('a default-column ResumeContentLine is main', () {
    const line = ResumeContentLine(ResumeContentLineKind.name, 'Jane Doe');
    expect(line.column, ResumeContentColumn.main);
  });
}
