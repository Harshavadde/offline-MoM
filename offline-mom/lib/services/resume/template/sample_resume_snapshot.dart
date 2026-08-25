import '../../../models/resume_snapshot.dart';
import '../../../models/skill_entry.dart';

/// A single, canonical, clearly-synthetic [ResumeSnapshot] used to render
/// real template previews (Beta Product Validation phase,
/// docs/v3/implementation/03-decisions.md) - the Template Gallery's
/// preview cards and the template selection detail screen both pass this
/// through the exact same [ResumeTemplateRenderer] the real "Save
/// version"/"Preview" flow uses, never a second, fake preview
/// implementation.
///
/// Deliberately not a real person - the name/company/school below are
/// obviously placeholder ("Arjun Mehta" is this project's own established
/// convention for synthetic sample data elsewhere in the codebase; see
/// docs/v3/implementation/03-decisions.md's prior preview-data
/// discussions) - and every field is invented for illustration, never
/// derived from or resembling a real user's data. Deliberately *not*
/// generated fresh per call: a `const`-like singleton keeps every
/// template's preview comparable against identical content, and avoids
/// rebuilding the same object on every grid cell render.
///
/// Content is sized to make template differences visible without forcing
/// unrepresentative pagination in a one-page preview: two experience
/// entries (enough to show entry rhythm/spacing), one project, one
/// certification, one education entry, and skills spanning technical/
/// tool/soft categories (exercises `groupSkillsByCategory`, Balanced
/// Two-Column's own distinguishing feature).
ResumeSnapshot buildSampleResumeSnapshot() {
  final now = DateTime(2026, 1, 1);
  return ResumeSnapshot(
    resumeId: -1,
    compiledAt: now,
    profile: const ResumeSnapshotProfile(
      fullName: 'Arjun Mehta',
      email: 'arjun.mehta@example.com',
      phone: '+1 (555) 010-2938',
      location: 'Seattle, WA',
      roleTagline: 'DevOps Engineer',
    ),
    experience: const [
      ResolvedExperienceEntry(
        sourceBlockId: -1,
        role: 'DevOps Engineer',
        company: 'Northlake Cloud Systems',
        startDate: '2022-03',
        bullets: [
          'Automated CI/CD pipelines across 12 microservices, cutting release time by 45%.',
          'Migrated on-prem infrastructure to Kubernetes on AWS EKS.',
          'Reduced monthly cloud spend by 22% through right-sized autoscaling policies.',
        ],
      ),
      ResolvedExperienceEntry(
        sourceBlockId: -2,
        role: 'Systems Engineer',
        company: 'Brightpath Analytics',
        startDate: '2019-06',
        endDate: '2022-02',
        bullets: [
          'Maintained CI pipelines for a 20-engineer team using Jenkins and Docker.',
          'Built internal monitoring dashboards with Prometheus and Grafana.',
        ],
      ),
    ],
    education: const [
      ResolvedEducationEntry(
        sourceBlockId: -1,
        institution: 'State University',
        degree: 'B.S.',
        fieldOfStudy: 'Computer Science',
        startDate: '2015-09',
        endDate: '2019-05',
      ),
    ],
    projects: const [
      ResolvedProjectEntry(
        sourceBlockId: -1,
        name: 'Infra Cost Dashboard',
        bullets: [
          'Built an internal tool visualizing per-team cloud spend, adopted company-wide.',
        ],
      ),
    ],
    certifications: const [
      ResolvedCertificationEntry(
        sourceBlockId: -1,
        name: 'AWS Certified DevOps Engineer',
        issuer: 'Amazon Web Services',
        issuedDate: '2023',
      ),
    ],
    skills: const [
      ResolvedSkillEntry(sourceBlockId: -1, name: 'Kubernetes', category: SkillCategory.technical),
      ResolvedSkillEntry(sourceBlockId: -2, name: 'Terraform', category: SkillCategory.technical),
      ResolvedSkillEntry(sourceBlockId: -3, name: 'AWS', category: SkillCategory.technical),
      ResolvedSkillEntry(sourceBlockId: -4, name: 'Docker', category: SkillCategory.tool),
      ResolvedSkillEntry(sourceBlockId: -5, name: 'Jenkins', category: SkillCategory.tool),
      ResolvedSkillEntry(sourceBlockId: -6, name: 'Communication', category: SkillCategory.soft),
    ],
  );
}
