// Tests GenerateBulletRewriteUseCase
// (lib/features/career/resume/generate_bullet_rewrite_use_case.dart) - a
// pure orchestration use case with a FakeLlmEngine, no database.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/features/career/resume/generate_bullet_rewrite_use_case.dart';
import 'package:offline_mom/services/ai/default_llm_request_queue.dart';

import '../../../test_helpers/fake_ai_engines.dart';

void main() {
  GenerateBulletRewriteUseCase buildUseCase({String? answer, Object? errorToThrow}) {
    return GenerateBulletRewriteUseCase(
      llmEngine: FakeLlmEngine(answer: answer, errorToThrow: errorToThrow),
      llmRequestQueue: DefaultLlmRequestQueue(),
    );
  }

  group('valid output', () {
    test('returns the rewritten text when it differs from the original', () async {
      final useCase = buildUseCase(answer: 'Orchestrated Docker container deployments.');

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker containers.',
      );

      expect(result, 'Orchestrated Docker container deployments.');
    });

    test('joins a multi-line model response with newlines', () async {
      final useCase = buildUseCase(answer: 'First bullet.\nSecond bullet.');

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Old first.\nOld second.',
      );

      expect(result, 'First bullet.\nSecond bullet.');
    });
  });

  group('no-op / malformed output', () {
    test('returns null for empty original text, without calling the model', () async {
      final useCase = buildUseCase(answer: 'Anything');

      final result = await useCase.call(entryContextLabel: 'Anything', originalText: '');

      expect(result, isNull);
    });

    test('returns null when the model echoes the original text unchanged', () async {
      final useCase = buildUseCase(answer: 'Deployed services using Docker containers.');

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker containers.',
      );

      expect(result, isNull);
    });

    test('returns null for an empty model response', () async {
      final useCase = buildUseCase(answer: '');

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker containers.',
      );

      expect(result, isNull);
    });

    test('returns null for a whitespace-only model response', () async {
      final useCase = buildUseCase(answer: '   \n  ');

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker containers.',
      );

      expect(result, isNull);
    });
  });

  group('model unavailable / generation failure', () {
    test('returns null rather than throwing when the model is unavailable', () async {
      final useCase = buildUseCase(errorToThrow: StateError('model not downloaded'));

      final result = await useCase.call(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker containers.',
      );

      expect(result, isNull);
    });
  });

  group('no persistence', () {
    test('the use case never touches any repository - it only returns a plain string', () async {
      // A structural assertion: GenerateBulletRewriteUseCase's constructor
      // accepts only an LlmEngine and an LlmRequestQueue, no
      // SuggestedEditRepository - there is nothing for this use case to
      // persist with, by construction, not merely by convention.
      final useCase = buildUseCase(answer: 'Rewritten.');

      final result = await useCase.call(entryContextLabel: 'Context', originalText: 'Original.');

      expect(result, 'Rewritten.');
    });
  });
}
