// Tests RoleCategoryMatcher (lib/services/career/beginner/role_category_matcher.dart)
// - R-10's deterministic (no AI, no network) mapping from free text to the
// closest RoleCategory. Pure function, no I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mom/services/career/beginner/role_category_catalog.dart';
import 'package:offline_mom/services/career/beginner/role_category_matcher.dart';

void main() {
  const matcher = RoleCategoryMatcher();

  group('exact match', () {
    test('matches a category by its exact display name', () {
      expect(matcher.match('Sales Executive').id, RoleCategoryCatalog.salesExecutive.id);
    });

    test('matches a category by an exact alias, case-insensitively', () {
      expect(matcher.match('BDE').id, RoleCategoryCatalog.businessDevelopmentExecutive.id);
      expect(matcher.match('bde').id, RoleCategoryCatalog.businessDevelopmentExecutive.id);
    });
  });

  group('alias matching (the exact aliases named in the R-10 spec)', () {
    final expectations = {
      'sales': RoleCategoryCatalog.salesExecutive,
      'sales executive': RoleCategoryCatalog.salesExecutive,
      'bde': RoleCategoryCatalog.businessDevelopmentExecutive,
      'business development': RoleCategoryCatalog.businessDevelopmentExecutive,
      'customer support': RoleCategoryCatalog.customerSupportExecutive,
      'call center': RoleCategoryCatalog.customerSupportExecutive,
      'data entry': RoleCategoryCatalog.dataEntryOperator,
      'back office': RoleCategoryCatalog.dataEntryOperator,
      'admin': RoleCategoryCatalog.officeAdminAssistant,
      'office assistant': RoleCategoryCatalog.officeAdminAssistant,
      'hr': RoleCategoryCatalog.hrRecruitmentAssistant,
      'recruiter': RoleCategoryCatalog.hrRecruitmentAssistant,
      'marketing': RoleCategoryCatalog.marketingExecutive,
      'accounts': RoleCategoryCatalog.accountsAssistant,
      'finance': RoleCategoryCatalog.bankingFinanceFresher,
      'banking': RoleCategoryCatalog.bankingFinanceFresher,
      'technical support': RoleCategoryCatalog.itTechnicalSupport,
      'it support': RoleCategoryCatalog.itTechnicalSupport,
      'software': RoleCategoryCatalog.softwareItFresher,
      'developer': RoleCategoryCatalog.softwareItFresher,
      'operations': RoleCategoryCatalog.operationsExecutive,
      'retail': RoleCategoryCatalog.retailExecutive,
    };

    expectations.forEach((alias, expected) {
      test('"$alias" -> ${expected.displayName}', () {
        expect(matcher.match(alias).id, expected.id);
      });
    });
  });

  group('substring/noisy input', () {
    test('matches a title embedded in extra text', () {
      expect(
        matcher.match('Urgent hiring: Data Entry Operator').id,
        RoleCategoryCatalog.dataEntryOperator.id,
      );
    });

    test('matches with trailing qualifiers', () {
      expect(
        matcher.match('Sales Executive - Fresher').id,
        RoleCategoryCatalog.salesExecutive.id,
      );
    });
  });

  group('General Fresher fallback', () {
    test('unrecognized text never fails - falls back to General Fresher', () {
      expect(matcher.match('Astronaut').id, RoleCategoryCatalog.generalFresher.id);
      expect(matcher.match('xyzzy plugh').id, RoleCategoryCatalog.generalFresher.id);
    });

    test('empty/whitespace-only text falls back to General Fresher', () {
      expect(matcher.match('').id, RoleCategoryCatalog.generalFresher.id);
      expect(matcher.match('   ').id, RoleCategoryCatalog.generalFresher.id);
    });
  });

  test('every catalog category is reachable via its own display name', () {
    for (final category in RoleCategoryCatalog.all) {
      expect(
        matcher.match(category.displayName).id,
        category.id,
        reason: '"${category.displayName}" should match itself',
      );
    }
  });
}
