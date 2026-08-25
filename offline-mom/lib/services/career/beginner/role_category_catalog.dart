import '../../../models/skill_entry.dart';
import 'role_category.dart';

/// A small, curated set of entry-level job categories the Beginner Resume
/// flow (R-10, docs/v3/implementation/03-decisions.md) can give conservative,
/// deterministic guidance for - never a growing "every possible job title"
/// database. Deliberately static Dart data (no AI, no network, no
/// database), mirroring [ResumeTemplateCatalog]'s own "hand-authored,
/// version-controlled catalog" shape: the beginner flow must work with no
/// AI model installed at all, and this catalog is exactly what makes that
/// true - role guidance (a summary focus phrase + suggested skills) comes
/// from here, unconditionally, regardless of whether an LLM is available.
///
/// Every skill listed under [RoleCategory.suggestedSkills] is a *common*
/// skill for that kind of role, never a specific claim, tool-proficiency
/// level, or measurable result ("Excel" is listed; "Expert in Excel" or
/// "processed 10,000+ records" never is) - see
/// `CreateBeginnerResumeUseCase`'s own doc comment for how a suggestion
/// only ever becomes part of a resume if the user explicitly confirms it.
class RoleCategoryCatalog {
  const RoleCategoryCatalog._();

  static const generalFresher = RoleCategory(
    id: 'general_fresher',
    displayName: 'General Fresher',
    aliases: {'fresher', 'entry level', 'entry-level', 'any role', 'general'},
    summaryFocus: 'an entry-level role',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('Basic computer skills', SkillCategory.technical),
      SuggestedSkill('Teamwork', SkillCategory.soft),
      SuggestedSkill('Time management', SkillCategory.soft),
      SuggestedSkill('Willingness to learn', SkillCategory.soft),
    ],
  );

  static const salesExecutive = RoleCategory(
    id: 'sales_executive',
    displayName: 'Sales Executive',
    aliases: {'sales', 'sales executive', 'sales rep', 'sales representative'},
    summaryFocus: 'sales and customer relationship-building',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Customer interaction', SkillCategory.soft),
      SuggestedSkill('Lead follow-up', SkillCategory.soft),
      SuggestedSkill('Basic sales knowledge', SkillCategory.technical),
      SuggestedSkill('Negotiation', SkillCategory.soft),
      SuggestedSkill('Relationship management', SkillCategory.soft),
      SuggestedSkill('MS Office', SkillCategory.tool),
    ],
  );

  static const businessDevelopmentExecutive = RoleCategory(
    id: 'business_development_executive',
    displayName: 'Business Development Executive',
    aliases: {'bde', 'business development', 'business development executive'},
    summaryFocus: 'business development and client outreach',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Lead generation', SkillCategory.soft),
      SuggestedSkill('Client outreach', SkillCategory.soft),
      SuggestedSkill('Market research', SkillCategory.technical),
      SuggestedSkill('Negotiation', SkillCategory.soft),
      SuggestedSkill('MS Office', SkillCategory.tool),
    ],
  );

  static const customerSupportExecutive = RoleCategory(
    id: 'customer_support_executive',
    displayName: 'Customer Support Executive',
    aliases: {'customer support', 'call center', 'call centre', 'customer service', 'support executive'},
    summaryFocus: 'customer support and query resolution',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Customer service', SkillCategory.soft),
      SuggestedSkill('Problem solving', SkillCategory.soft),
      SuggestedSkill('Email handling', SkillCategory.technical),
      SuggestedSkill('CRM basics', SkillCategory.tool),
      SuggestedSkill('MS Office', SkillCategory.tool),
    ],
  );

  static const dataEntryOperator = RoleCategory(
    id: 'data_entry_operator',
    displayName: 'Data Entry Operator',
    aliases: {'data entry', 'back office', 'data entry operator', 'data entry executive'},
    summaryFocus: 'data entry and back-office support',
    suggestedSkills: [
      SuggestedSkill('Basic computer operations', SkillCategory.technical),
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('MS Excel', SkillCategory.tool),
      SuggestedSkill('Data entry', SkillCategory.technical),
      SuggestedSkill('Typing', SkillCategory.technical),
      SuggestedSkill('Attention to detail', SkillCategory.soft),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('Communication', SkillCategory.soft),
    ],
  );

  static const officeAdminAssistant = RoleCategory(
    id: 'office_admin_assistant',
    displayName: 'Office/Admin Assistant',
    aliases: {'admin', 'office assistant', 'admin assistant', 'administrative assistant', 'office admin'},
    summaryFocus: 'office administration and coordination',
    suggestedSkills: [
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('Scheduling', SkillCategory.technical),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Organization', SkillCategory.soft),
      SuggestedSkill('Basic computer skills', SkillCategory.technical),
    ],
  );

  static const hrRecruitmentAssistant = RoleCategory(
    id: 'hr_recruitment_assistant',
    displayName: 'HR/Recruitment Assistant',
    aliases: {'hr', 'recruiter', 'recruitment', 'hr assistant', 'human resources'},
    summaryFocus: 'HR support and recruitment coordination',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Candidate screening basics', SkillCategory.technical),
      SuggestedSkill('Interview scheduling', SkillCategory.technical),
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('Interpersonal skills', SkillCategory.soft),
    ],
  );

  static const marketingExecutive = RoleCategory(
    id: 'marketing_executive',
    displayName: 'Marketing Executive',
    aliases: {'marketing', 'marketing executive', 'digital marketing'},
    summaryFocus: 'marketing support and brand promotion',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Social media basics', SkillCategory.tool),
      SuggestedSkill('Content support', SkillCategory.technical),
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('Market research', SkillCategory.technical),
      SuggestedSkill('Creativity', SkillCategory.soft),
    ],
  );

  static const accountsAssistant = RoleCategory(
    id: 'accounts_assistant',
    displayName: 'Accounts Assistant',
    aliases: {'accounts', 'accounts assistant', 'accounting'},
    summaryFocus: 'accounts support and bookkeeping',
    suggestedSkills: [
      SuggestedSkill('Basic accounting knowledge', SkillCategory.technical),
      SuggestedSkill('MS Excel', SkillCategory.tool),
      SuggestedSkill('Data entry', SkillCategory.technical),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('Attention to detail', SkillCategory.soft),
      SuggestedSkill('MS Office', SkillCategory.tool),
    ],
  );

  static const bankingFinanceFresher = RoleCategory(
    id: 'banking_finance_fresher',
    displayName: 'Banking/Finance Fresher',
    aliases: {'banking', 'finance', 'bank', 'banking fresher', 'finance fresher'},
    summaryFocus: 'banking and financial services',
    suggestedSkills: [
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Basic finance knowledge', SkillCategory.technical),
      SuggestedSkill('MS Excel', SkillCategory.tool),
      SuggestedSkill('Data entry', SkillCategory.technical),
      SuggestedSkill('Customer service', SkillCategory.soft),
      SuggestedSkill('Attention to detail', SkillCategory.soft),
    ],
  );

  static const itTechnicalSupport = RoleCategory(
    id: 'it_technical_support',
    displayName: 'IT/Technical Support',
    aliases: {'technical support', 'it support', 'tech support', 'helpdesk', 'help desk'},
    summaryFocus: 'IT/technical support and troubleshooting',
    suggestedSkills: [
      SuggestedSkill('Basic troubleshooting', SkillCategory.technical),
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Operating systems basics', SkillCategory.technical),
      SuggestedSkill('Customer support', SkillCategory.soft),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('MS Office', SkillCategory.tool),
    ],
  );

  static const softwareItFresher = RoleCategory(
    id: 'software_it_fresher',
    displayName: 'Software/IT Fresher',
    aliases: {'software', 'developer', 'software fresher', 'it fresher', 'programmer'},
    summaryFocus: 'software development and IT',
    suggestedSkills: [
      SuggestedSkill('Basic programming knowledge', SkillCategory.technical),
      SuggestedSkill('Problem solving', SkillCategory.soft),
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Willingness to learn', SkillCategory.soft),
      SuggestedSkill('Teamwork', SkillCategory.soft),
    ],
  );

  static const operationsExecutive = RoleCategory(
    id: 'operations_executive',
    displayName: 'Operations Executive',
    aliases: {'operations', 'ops', 'operations executive'},
    summaryFocus: 'operations and process coordination',
    suggestedSkills: [
      SuggestedSkill('Coordination', SkillCategory.soft),
      SuggestedSkill('MS Office', SkillCategory.tool),
      SuggestedSkill('Documentation', SkillCategory.technical),
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Problem solving', SkillCategory.soft),
      SuggestedSkill('Time management', SkillCategory.soft),
    ],
  );

  static const retailExecutive = RoleCategory(
    id: 'retail_executive',
    displayName: 'Retail Executive',
    aliases: {'retail', 'store executive', 'retail executive', 'sales associate'},
    summaryFocus: 'retail and in-store customer service',
    suggestedSkills: [
      SuggestedSkill('Customer service', SkillCategory.soft),
      SuggestedSkill('Communication', SkillCategory.soft),
      SuggestedSkill('Billing basics', SkillCategory.technical),
      SuggestedSkill('Inventory basics', SkillCategory.technical),
      SuggestedSkill('Teamwork', SkillCategory.soft),
    ],
  );

  /// Every category, in the order shown to the user - [generalFresher]
  /// last since it's the deliberate fallback, not the first thing to pick.
  static const List<RoleCategory> all = [
    salesExecutive,
    businessDevelopmentExecutive,
    customerSupportExecutive,
    dataEntryOperator,
    officeAdminAssistant,
    hrRecruitmentAssistant,
    marketingExecutive,
    accountsAssistant,
    bankingFinanceFresher,
    itTechnicalSupport,
    softwareItFresher,
    operationsExecutive,
    retailExecutive,
    generalFresher,
  ];
}
