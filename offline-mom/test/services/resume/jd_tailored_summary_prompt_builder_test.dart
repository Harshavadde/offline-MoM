// Tests JdTailoredResumeSummaryPromptBuilder
// (lib/services/resume/jd_tailored_summary_prompt_builder.dart) - pure
// prompt-shape assertions, mirrors resume_suggestion_prompt_builder_test.dart's
// own style.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/jd_tailored_summary_prompt_builder.dart';

void main() {
  const builder = JdTailoredResumeSummaryPromptBuilder();

  test('the system prompt forbids inventing facts and requires a bounded, plain summary', () {
    final prompt = builder.build(targetRoleLabel: 'Data Entry Operator');

    expect(prompt.systemPrompt, contains('Never invent or assume'));
    expect(prompt.systemPrompt, contains('specific number of years'));
    expect(prompt.systemPrompt, contains('Output ONLY the summary text'));
  });

  test('only the facts actually passed in appear in the user prompt', () {
    final prompt = builder.build(
      targetRoleLabel: 'Data Entry Operator',
      confirmedSkillNames: ['MS Excel', 'Typing'],
      educationLabel: 'B.Com',
      experienceOneLiners: ['Intern at Acme Corp'],
      existingProjectNames: ['Inventory Tracker'],
    );

    expect(prompt.userPrompt, contains('Data Entry Operator'));
    expect(prompt.userPrompt, contains('MS Excel'));
    expect(prompt.userPrompt, contains('Typing'));
    expect(prompt.userPrompt, contains('B.Com'));
    expect(prompt.userPrompt, contains('Intern at Acme Corp'));
    expect(prompt.userPrompt, contains('Inventory Tracker'));
  });

  test('empty optional inputs produce a sane prompt, not a crash', () {
    final prompt = builder.build(targetRoleLabel: 'General Fresher');

    expect(prompt.userPrompt, contains('Target role: General Fresher'));
    expect(prompt.userPrompt, isNot(contains('Confirmed skills:')));
    expect(prompt.userPrompt, isNot(contains('Education:')));
    expect(prompt.userPrompt, isNot(contains('Experience:')));
    expect(prompt.userPrompt, isNot(contains('Existing projects:')));
  });
}
