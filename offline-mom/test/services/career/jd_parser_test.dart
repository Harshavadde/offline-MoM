// Tests JdParser (lib/services/career/jd_parser.dart) - a pure, offline,
// deterministic heuristic with no I/O and no AI model. Mirrors
// resume_import_parser_test.dart's style exactly: a const service
// instance, plain string fixtures, no database.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/career/jd_parser.dart';

void main() {
  const parser = JdParser();

  group('title/company detection', () {
    test('detects an explicit "Job Title:" / "Company:" label', () {
      final jd = parser.parse('Job Title: Senior Backend Engineer\nCompany: Acme Corp\n');
      expect(jd.title, 'Senior Backend Engineer');
      expect(jd.company, 'Acme Corp');
    });

    test('falls back to the first short, non-sentence preamble line as the title', () {
      final jd = parser.parse('Senior Backend Engineer\n\nREQUIREMENTS\n\n- Python\n');
      expect(jd.title, 'Senior Backend Engineer');
    });

    test('does not guess a title from a sentence-like first line', () {
      final jd = parser.parse('We are looking for a talented engineer to join our team.\n');
      expect(jd.title, isNull);
    });

    test('never fabricates a company without an explicit label', () {
      final jd = parser.parse('Senior Backend Engineer\n\nREQUIREMENTS\n\n- Python\n');
      expect(jd.company, isNull);
    });
  });

  group('section detection', () {
    test('recognizes Requirements/Responsibilities/Education/Certifications headers', () {
      final jd = parser.parse(
        'REQUIREMENTS\n\n- Python\n- SQL\n\n'
        'RESPONSIBILITIES\n\n- Build features\n- Review code\n\n'
        'EDUCATION\n\n- Bachelor\'s degree in Computer Science\n\n'
        'CERTIFICATIONS\n\n- AWS Certified Developer\n',
      );

      expect(jd.requirements, ['Python', 'SQL']);
      expect(jd.responsibilities, ['Build features', 'Review code']);
      expect(jd.educationRequirements, ["Bachelor's degree in Computer Science"]);
      expect(jd.certificationRequirements, ['AWS Certified Developer']);
    });

    test('warns when no requirements/responsibilities/education sections were detected', () {
      final jd = parser.parse('Just a plain paragraph with no structure whatsoever.');
      expect(jd.warnings, isNotEmpty);
      expect(jd.requirements, isEmpty);
    });

    test('is case-insensitive for header variants', () {
      final jd = parser.parse('qualifications\n\n- Docker\n');
      expect(jd.requirements, ['Docker']);
    });
  });

  group('skills/requirements extraction - never split or reworded', () {
    test('preserves a compound term like "CI/CD" verbatim, never splitting on "/"', () {
      final jd = parser.parse('REQUIREMENTS\n\n- Kubernetes\n- Docker\n- Terraform\n- Azure\n- CI/CD\n');
      expect(jd.requirements, ['Kubernetes', 'Docker', 'Terraform', 'Azure', 'CI/CD']);
    });

    test('strips different bullet marker styles', () {
      final jd = parser.parse('REQUIREMENTS\n\n* Python\n• SQL\n1. Java\n');
      expect(jd.requirements, ['Python', 'SQL', 'Java']);
    });
  });

  group('experience requirement detection', () {
    test('detects "N+ years" phrasing', () {
      final jd = parser.parse('REQUIREMENTS\n\n- 3+ years of experience with Python\n');
      expect(jd.experienceRequirement, isNotNull);
      expect(jd.experienceRequirement!.minYears, 3);
      expect(jd.experienceRequirement!.maxYears, isNull);
    });

    test('detects a "N-M years" range', () {
      final jd = parser.parse('REQUIREMENTS\n\n- 2-4 years of relevant experience\n');
      expect(jd.experienceRequirement!.minYears, 2);
      expect(jd.experienceRequirement!.maxYears, 4);
    });

    test('detects "minimum N years" phrasing', () {
      final jd = parser.parse('REQUIREMENTS\n\n- minimum 2 years in a related field\n');
      expect(jd.experienceRequirement!.minYears, 2);
    });

    test('is null (never guessed) when no years-of-experience statement exists', () {
      final jd = parser.parse('REQUIREMENTS\n\n- Strong communication skills\n');
      expect(jd.experienceRequirement, isNull);
      expect(jd.warnings, isNotEmpty);
    });
  });

  group('non-fabrication and content preservation', () {
    test('an empty string produces an empty, non-fabricated result', () {
      final jd = parser.parse('');
      expect(jd.hasAnyStructuredContent, isFalse);
      expect(jd.requirements, isEmpty);
    });

    test('rawText always preserves the full original text, regardless of '
        'how much structure was detected', () {
      const original = 'Some ambiguous job description text with no clear structure.';
      final jd = parser.parse(original);
      expect(jd.rawText, original);
    });

    test('unrecognized content is preserved in unclassifiedText, never dropped', () {
      const stray = 'A very specific unstructured sentence that must survive verbatim.';
      final jd = parser.parse(stray);
      expect(jd.unclassifiedText, contains(stray));
    });

    test('repeated parses of the same text produce structurally equivalent results', () {
      const text = 'REQUIREMENTS\n\n- Python\n- SQL\n';
      final first = parser.parse(text);
      final second = parser.parse(text);
      expect(first.requirements, second.requirements);
    });
  });

  group('malformed/ambiguous content', () {
    test('a section header with no content under it yields an empty list, not an error', () {
      final jd = parser.parse('REQUIREMENTS\n\nRESPONSIBILITIES\n\n- Ship things\n');
      expect(jd.requirements, isEmpty);
      expect(jd.responsibilities, ['Ship things']);
    });

    test('content appearing before any recognized header is preserved as unclassified', () {
      final jd = parser.parse('Some intro paragraph.\n\nREQUIREMENTS\n\n- Python\n');
      expect(jd.unclassifiedText, contains('Some intro paragraph.'));
    });
  });

  group('special characters and non-Latin text', () {
    test('special characters (C++, C#, .NET) are preserved verbatim', () {
      final jd = parser.parse('REQUIREMENTS\n\n- C++\n- C#\n- .NET\n');
      expect(jd.requirements, ['C++', 'C#', '.NET']);
    });

    test('non-Latin text is preserved unchanged', () {
      final jd = parser.parse('職務内容\n\nREQUIREMENTS\n\n- 日本語能力\n- Строительство\n');
      expect(jd.requirements, containsAll(['日本語能力', 'Строительство']));
    });
  });
}
