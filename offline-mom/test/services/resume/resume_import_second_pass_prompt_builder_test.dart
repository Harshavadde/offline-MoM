// Tests ResumeImportSecondPassPromptBuilder
// (lib/services/resume/resume_import_second_pass_prompt_builder.dart) - a
// pure, stateless prompt builder, mirrors
// resume_suggestion_prompt_builder_test.dart's shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/resume_import_second_pass_prompt_builder.dart';

void main() {
  const builder = ResumeImportSecondPassPromptBuilder();

  test('system prompt names every recognizable section and forbids rewriting content', () {
    final prompt = builder.build(unclassifiedBlocks: const ['Some block.']);

    expect(prompt.systemPrompt, contains('Experience'));
    expect(prompt.systemPrompt, contains('Education'));
    expect(prompt.systemPrompt, contains('Projects'));
    expect(prompt.systemPrompt, contains('Certifications'));
    expect(prompt.systemPrompt, contains('Skills'));
    expect(prompt.systemPrompt, contains('unchanged'));
  });

  test('user prompt includes every block, separated by blank lines', () {
    final prompt = builder.build(unclassifiedBlocks: const ['First block.', 'Second block.']);

    expect(prompt.userPrompt, contains('First block.'));
    expect(prompt.userPrompt, contains('Second block.'));
    expect(prompt.userPrompt, contains('First block.\n\nSecond block.'));
  });

  test('is pure - the same input always produces byte-identical output', () {
    final a = builder.build(unclassifiedBlocks: const ['Same block.']);
    final b = builder.build(unclassifiedBlocks: const ['Same block.']);

    expect(a.systemPrompt, b.systemPrompt);
    expect(a.userPrompt, b.userPrompt);
  });
}
