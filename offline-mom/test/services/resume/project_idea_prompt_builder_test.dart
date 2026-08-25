// Tests ProjectIdeaPromptBuilder
// (lib/services/resume/project_idea_prompt_builder.dart) - pure
// prompt-shape assertions. The deterministic completed-tense *rejection*
// itself is covered in generate_jd_tailored_draft_use_case_test.dart, since
// that check lives in the use case, not this pure builder.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/project_idea_prompt_builder.dart';

void main() {
  const builder = ProjectIdeaPromptBuilder();

  test('the system prompt forbids completed-tense language and demands idea-framing', () {
    final prompt = builder.build(jdTitle: 'Python Developer', topRequirements: const ['Django']);

    expect(prompt.systemPrompt, contains('NEVER use first-person or completed-tense language'));
    expect(prompt.systemPrompt, contains('"I built"'));
    expect(prompt.systemPrompt, contains('idea'));
  });

  test('the system prompt requires the exact fixed 3-line output format', () {
    final prompt = builder.build(jdTitle: 'Python Developer', topRequirements: const ['Django']);

    expect(prompt.systemPrompt, contains('Title:'));
    expect(prompt.systemPrompt, contains('Technologies:'));
    expect(prompt.systemPrompt, contains('Features:'));
  });

  test('the given role, requirements, and confirmed skills all appear in the user prompt', () {
    final prompt = builder.build(
      jdTitle: 'Python Developer',
      topRequirements: const ['Django', 'PostgreSQL'],
      confirmedSkillNames: const ['Python'],
    );

    expect(prompt.userPrompt, contains('Python Developer'));
    expect(prompt.userPrompt, contains('Django'));
    expect(prompt.userPrompt, contains('PostgreSQL'));
    expect(prompt.userPrompt, contains('Python'));
  });

  test('empty requirements/skills still produce a usable prompt, not a crash', () {
    final prompt = builder.build(jdTitle: 'General Role', topRequirements: const []);

    expect(prompt.userPrompt, contains('General Role'));
    expect(prompt.userPrompt, contains('(general requirements for this role)'));
    expect(prompt.userPrompt, contains('(none given)'));
  });
}
