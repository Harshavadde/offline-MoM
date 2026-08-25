// Tests GenerateImportSecondPassUseCase
// (lib/features/career/resume/generate_import_second_pass_use_case.dart) -
// a pure orchestration use case over a FakeLlmEngine plus the real
// (deterministic) ResumeImportParser, no database. Mirrors
// generate_bullet_rewrite_use_case_test.dart's shape.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/generate_import_second_pass_use_case.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';
import 'package:offline_mom/services/resume/resume_import_parser.dart';

import '../../../test_helpers/fake_ai_engines.dart';

void main() {
  GenerateImportSecondPassUseCase buildUseCase({String? answer, Object? errorToThrow}) {
    return GenerateImportSecondPassUseCase(
      llmEngine: FakeLlmEngine(answer: answer, errorToThrow: errorToThrow),
      llmRequestQueue: DefaultLlmRequestQueue(),
    );
  }

  test('returns the draft unchanged, without calling the model, when there is nothing unclassified', () async {
    final engine = FakeLlmEngine(answer: 'Should never be used.');
    final useCase = GenerateImportSecondPassUseCase(
      llmEngine: engine,
      llmRequestQueue: DefaultLlmRequestQueue(),
    );
    const draft = ParsedResumeDraft(fullName: 'Jane Doe');

    final result = await useCase.call(draft);

    expect(result, draft);
    expect(engine.promptCalls, isEmpty);
  });

  test('structures a previously-unclassified block once the model adds a recognized section header',
      () async {
    final useCase = buildUseCase(answer: 'Skills\nDart, Flutter, SQL');
    const draft = ParsedResumeDraft(unclassifiedText: ['Dart, Flutter, SQL']);

    final result = await useCase.call(draft);

    expect(result.skills.map((s) => s.name), containsAll(['Dart', 'Flutter', 'SQL']));
    expect(result.unclassifiedText, isEmpty);
  });

  test('leaves a block unclassified when the model does not recognize any section for it', () async {
    final useCase = buildUseCase(answer: 'Just some leftover text, unlabeled.');
    const draft = ParsedResumeDraft(unclassifiedText: ['Just some leftover text, unlabeled.']);

    final result = await useCase.call(draft);

    expect(result.unclassifiedText, ['Just some leftover text, unlabeled.']);
    expect(result.experience, isEmpty);
    expect(result.education, isEmpty);
    expect(result.skills, isEmpty);
  });

  test('returns the draft unchanged rather than throwing when the model is unavailable', () async {
    final useCase = buildUseCase(errorToThrow: StateError('model not downloaded'));
    const draft = ParsedResumeDraft(unclassifiedText: ['Some leftover text.']);

    final result = await useCase.call(draft);

    expect(result, draft);
  });

  test('returns the draft unchanged for an empty model response', () async {
    final useCase = buildUseCase(answer: '');
    const draft = ParsedResumeDraft(unclassifiedText: ['Some leftover text.']);

    final result = await useCase.call(draft);

    expect(result, draft);
  });

  test('never overwrites contact info already determined by the first pass', () async {
    final useCase = buildUseCase(answer: 'Skills\nDart');
    const draft = ParsedResumeDraft(fullName: 'Jane Doe', email: 'jane@example.com', unclassifiedText: ['Dart']);

    final result = await useCase.call(draft);

    expect(result.fullName, 'Jane Doe');
    expect(result.email, 'jane@example.com');
  });
}
