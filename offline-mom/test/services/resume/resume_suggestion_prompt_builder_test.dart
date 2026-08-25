// Tests ResumeSuggestionPromptBuilder
// (lib/services/resume/resume_suggestion_prompt_builder.dart) - a pure,
// stateless prompt-construction step. No LLM, no database, no Riverpod.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/resume/resume_suggestion_prompt_builder.dart';

void main() {
  const builder = ResumeSuggestionPromptBuilder();

  group('content inclusion', () {
    test('the entry context label appears in the user prompt', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.userPrompt, contains('Backend Engineer at Acme Corp'));
    });

    test('the JD requirement appears in the user prompt', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes orchestration experience',
      );

      expect(prompt.userPrompt, contains('Kubernetes orchestration experience'));
    });

    test('the original resume text appears verbatim in the user prompt', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Deployed services using Docker.\nWrote integration tests.',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.userPrompt, contains('Deployed services using Docker.'));
      expect(prompt.userPrompt, contains('Wrote integration tests.'));
    });
  });

  group('fabrication instructions', () {
    test('the system prompt explicitly forbids inventing facts not already present', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.systemPrompt, contains('Never invent or assume'));
    });

    test('the system prompt explicitly forbids adding employers/dates/certifications/metrics', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.systemPrompt, contains('employers'));
      expect(prompt.systemPrompt, contains('certifications'));
      expect(prompt.systemPrompt, contains('metrics'));
    });

    test('the system prompt requires structured, one-bullet-per-line output with no preamble', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.systemPrompt, contains('one per line'));
      expect(prompt.systemPrompt, contains('no preamble'));
    });
  });

  group('deterministic structure', () {
    test('identical inputs produce a byte-identical prompt across calls', () {
      ResumeSuggestionPrompt build() => builder.build(
            entryContextLabel: 'Backend Engineer at Acme Corp',
            originalText: 'Built services.',
            jdRequirement: 'Kubernetes',
          );

      final first = build();
      final second = build();

      expect(first.systemPrompt, second.systemPrompt);
      expect(first.userPrompt, second.userPrompt);
    });

    test('the system prompt never changes with the input - only the user prompt varies', () {
      final promptA = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: 'Kubernetes',
      );
      final promptB = builder.build(
        entryContextLabel: 'Data Analyst at Globex',
        originalText: 'Built dashboards.',
        jdRequirement: 'SQL',
      );

      expect(promptA.systemPrompt, promptB.systemPrompt);
      expect(promptA.userPrompt, isNot(promptB.userPrompt));
    });

    test('one call never leaks another call\'s entry content - proves statelessness', () {
      final promptA = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services with Docker.',
        jdRequirement: 'Kubernetes',
      );
      final promptB = builder.build(
        entryContextLabel: 'Data Analyst at Globex',
        originalText: 'Built dashboards with Tableau.',
        jdRequirement: 'SQL',
      );

      expect(promptA.userPrompt, isNot(contains('Globex')));
      expect(promptA.userPrompt, isNot(contains('Tableau')));
      expect(promptB.userPrompt, isNot(contains('Acme Corp')));
      expect(promptB.userPrompt, isNot(contains('Docker')));
    });
  });

  group('missing data handled safely', () {
    test('an empty original text does not crash and produces a valid, non-empty prompt', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: '',
        jdRequirement: 'Kubernetes',
      );

      expect(prompt.userPrompt, isNotEmpty);
      expect(prompt.userPrompt, contains('(empty)'));
    });

    test('an empty JD requirement does not crash and falls back to a wording-only instruction', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: '',
      );

      expect(prompt.userPrompt, isNotEmpty);
      expect(prompt.userPrompt, contains('improve the wording only'));
    });

    test('a whitespace-only JD requirement is treated the same as empty', () {
      final prompt = builder.build(
        entryContextLabel: 'Backend Engineer at Acme Corp',
        originalText: 'Built services.',
        jdRequirement: '   ',
      );

      expect(prompt.userPrompt, contains('improve the wording only'));
    });
  });
}
