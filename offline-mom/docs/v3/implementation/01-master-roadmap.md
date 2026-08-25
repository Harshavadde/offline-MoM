# V3 Master Implementation Roadmap

Implements `docs/v3/01-prd.md` §25 as concrete milestones. Scope, file lists, and acceptance criteria below are taken directly from the PRD — this document does not add, remove, or reinterpret milestone scope; see [11-gap-analysis.md](11-gap-analysis.md) for where the PRD and the actual repository currently differ, and [03-decisions.md](03-decisions.md) for the decisions this ordering depends on.

## How to read this document

Each milestone states: **Objective**, **Depends on**, **Major deliverables**, **Acceptance criteria** (PRD's own wording), **Manual verification** (what no automated test in this environment can confirm), and **Current status** — the status is repository-verified as of this document's own last-updated date (git log/git show/direct file inspection), not inherited from any prior conversational claim.

**Last updated:** 2026-08-10, Milestone 5 finalized (V3 beta hardening complete).

---

## Milestone 0 — Data model & device foundation

**Objective:** Lay the schema/plumbing every later milestone depends on, and close two confirmed pre-existing gaps in the Milestone-1-era (v16) Resume implementation (a dead `target_role` field, no version-restore path). No AI, no templates.

**Depends on:** Nothing — this is the foundation milestone.

**Major deliverables** (PRD §25):
- Migration `v17`: `suggested_edits` table; `resumes.achievements_json`/`.template_id`; `resume_versions.template_id`/`.tailored_for_jd_title`/`.tailored_for_jd_company`.
- `SuggestedEdit` model + `SuggestedEditRepository` (schema/CRUD only at this stage — nothing generated a real suggestion until Milestone 3).
- `DeviceCapabilityService` (real `device_info_plus`-backed implementation + `FakeDeviceCapabilityService`).
- `target_role` wired into the Editor's Profile card.
- Resume-version restore-to-draft flow.

**Acceptance criteria** (PRD §25, verbatim intent): `target_role` is settable and visible in the Editor; a saved version can be restored into an editable draft without corrupting the live composition; `DeviceCapabilityService` has a real and a fake implementation, wired through DI the same way every other service pair in this codebase is. **Met** — confirmed by direct inspection of `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` (Profile card reads/writes `targetRole`), `resume_version_providers.dart` (`restoreToDraft()`), and `lib/services/device/device_capability_service.dart`.

**Manual verification:** real-device RAM read on at least one physical Android device — **still outstanding**, no device available in this implementation environment. `recommendedTierForRamMb`'s 5500MB `highRamDevice` threshold (see `lib/services/device/device_capability_service.dart`) remains uncalibrated against real hardware.

**Current status: ✅ COMPLETE — committed and pushed.**
- Implementation commit: `dd4a03d feat(v3): implement milestone 0 foundation` — 22 files changed, 1508 insertions(+), 14 deletions(-) (`git show --stat --oneline dd4a03d`).
- Documentation commit: `0e47848 docs(v3): add implementation tracking` — the original creation of this `docs/v3/implementation/` directory (12 files).
- Both commits are on `origin/main` (`git ls-remote origin refs/heads/main` reachability confirmed at the time of the Milestone 0 push, and both remain ancestors of the current HEAD `2f92bba`).
- Test results at the time: 56/56 passing across the 6 files this milestone added/extended (`migration_v17_test.dart`, `suggested_edit_test.dart`, `suggested_edit_repository_test.dart`, `device_capability_service_test.dart`, plus the extended `resume_editor_controller_test.dart`/`resume_version_controller_test.dart`) — this is a **milestone-scoped** count, not a full-suite count; see [08-quality-gates.md](08-quality-gates.md) for the distinction. `flutter analyze` was clean at commit time.

---

## Milestone 1 — Template engine

**Objective:** Replace the single hardcoded PDF template with a real template system (layout primitives + design tokens + archetypes), delivering the first 4 of ~10 planned archetypes.

**Depends on:** Milestone 0 (`resumes.template_id`/`resume_versions.template_id` columns must exist for a template choice to be recorded).

**Major deliverables** (PRD §25): `ResumeDesignTokens`, `ResumeTemplateSpec`, `ResumeTemplateCatalog`; layout primitives (header block, section block, entry block, sidebar column, divider); 4 archetypes (Classic Single-Column, Modern Accent-Rule, Two-Column Sidebar, Compact Technical); `ResumeTemplateRenderer` (replacing `ResumePdfExportService`'s rendering internals, atomic-write preserved); template gallery screen; `save_resume_version_use_case.dart` threading `templateId` through.

**Beyond the PRD's literal file list** (see [03-decisions.md](03-decisions.md) D-M1-01): `resume_content_plan.dart`/`resume_content_plan_builder.dart` were added as a shared content/ordering abstraction, and `content_line_renderer.dart` as a shared layout consumer of it — not named individually in PRD §25's Milestone 1 file list, but required to make ATS reading-order genuinely testable without a native PDF-parsing platform channel under `flutter test`.

**Acceptance criteria** (PRD §25): 4 archetypes × 2 token presets (8 templates total) render correctly and pass the ATS round-trip test; no archetype produces image-only text. **Met** — confirmed: `lib/services/resume/template/resume_template_catalog.dart` defines exactly 4 archetypes × 2 presets (`warm`/`cool`) = 8 catalog entries (`ResumeTemplateCatalog.all`); `test/services/resume/template/archetypes/archetypes_test.dart` and `test/services/resume/resume_template_renderer_test.dart` exist and are part of the passing suite.

**Manual verification:** visual review of generated PDFs against the Enhance CV quality bar — **outstanding**, subjective/human-judged, not automatable (see RV3-10, [04-risk-register.md](04-risk-register.md)).

**Current status: ✅ COMPLETE — committed and pushed.**
- Commit: `d67528a feat(v3): implement milestone 1 template engine` — 35 files changed, 2397 insertions(+), 123 deletions(-).
- Test results reported at the time: 457/457 passing (historically reported figure for this milestone's relevant suite at commit time — not independently re-executed against the historical commit in this documentation pass; see [08-quality-gates.md](08-quality-gates.md) for what was and wasn't re-verified). `flutter analyze`: 0 issues reported at the time.
- The two-column pagination approach uses `package:pdf`'s `Partitions`/`Partition` primitives rather than `pw.Row`/`pw.Expanded`, after the latter was found to fail the PRD's own mandatory long-synthetic-resume/page-overflow test (see [03-decisions.md](03-decisions.md) D-M1-02).

---

## Milestone 2 — Deterministic tailoring depth

**Objective:** Extend the existing `ResumeJdAnalyzer` with an additive semantic-embedding matching tier, add deterministic relevance-based prioritization, and close the confirmed analysis→Editor loop-back gap. No LLM rewriting — this milestone is deliberately AI-free beyond the embedding model.

**Depends on:** Milestone 0 (sequenced after it per PRD §25's own ordering, no direct schema dependency). Reuses the existing `EmbeddingEngine` — no new AI infrastructure.

**Major deliverables** (PRD §25): `ResumeJdSemanticMatcher`; `PrioritizeResumeContentUseCase`; `matchSource` field on `ResumeJdAnalyzer`'s result (`MatchSource` enum: `exactKeyword`/`alias`/`semanticEmbedding`/`tokenOverlap`, additive only — never downgrades an existing keyword/alias match); a per-finding "Go to Editor" action on the analysis results screen; `EmbeddingEngine` wired into the analyzer's construction.

**Acceptance criteria** (PRD §25): semantic tier is strictly additive; the analysis screen has a working, tested action per finding. **Met** — confirmed by direct inspection of `lib/services/career/resume_jd_analyzer.dart`'s `_applySemanticTier` (only ever runs on a `MatchLevel.missing` result, upgrades to `partial` + `MatchSource.semanticEmbedding`, never touches an existing exact/partial match) and `resume_jd_analysis_screen.dart`'s per-row `_GoToEditorButton`.

**Manual verification:** none specified beyond automated tests in the PRD.

**Current status: ✅ COMPLETE — committed and pushed.**
- Commit: `30bf491 feat(v3): implement milestone 2 deterministic tailoring depth` — 10 files changed, 1126 insertions(+), 74 deletions(-).
- Full-suite test result at commit time: **1256/1256 passing**, `flutter analyze`: 0 issues — both re-run and confirmed immediately before this commit was made (same session that produced it).
- Semantic-matcher failure (embedding model unavailable/unloaded/fails) degrades gracefully — the deterministic result passes through unchanged; the semantic matcher's own `try`/`catch` and `resumeJdSemanticMatcherProvider`'s construction-time `try`/`catch` both confirmed by direct inspection.
- Prioritization (`PrioritizeResumeContentUseCase`) is scoped to Experience/Projects/Skills only — Education/Certifications are deliberately left in their original order (confirmed: `prioritize_resume_content_use_case.dart` never touches `snapshot.education`/`snapshot.certifications`).

---

## Milestone 3 — AI rewrite suggestions

**Objective:** Build the core tailoring feature — bounded, per-entry LLM rewrite suggestions, generated through the `SuggestedEdit` proposal gate (AC3-02), never written directly to live content. The single most safety-critical milestone in the PRD.

**Depends on:** Milestone 0 (`suggested_edits` table/repository). Milestone 2 (needs deterministic + semantic matching to decide which entries are "relevant but improvable").

**Major deliverables** (PRD §25, as actually built): `ResumeSuggestionPromptBuilder` (`lib/services/resume/resume_suggestion_prompt_builder.dart`); `SuggestionFabricationGuard` (`lib/services/resume/suggestion_fabrication_guard.dart`); `GenerateResumeSuggestionsUseCase` (`lib/features/career/analysis/generate_resume_suggestions_use_case.dart`); `AcceptSuggestedEditUseCase`/`RejectSuggestedEditUseCase` (`lib/features/career/resume/`); `resume_suggestion_review_screen.dart` + `resume_suggestion_providers.dart`; a new `LlmEngine.generateFromPrompt(systemPrompt, userPrompt)` method (the one new engine capability this milestone required — no existing `LlmEngine` method fit a caller-composed, bounded prompt); pending-suggestion-count entry point on the Editor screen; generation trigger on the JD Analysis results screen (see [03-decisions.md](03-decisions.md) D-M3-03 for why generation lives there, not the Editor).

**Acceptance criteria** (PRD §25): the AC3-02 test passes (no code path merges LLM output into live content without an explicit accept); rejected suggestions leave original content byte-identical (dedicated test); every suggestion is individually actionable in the review screen. **Met** — confirmed: `test/features/career/analysis/generate_resume_suggestions_use_case_test.dart`'s "resume remains unchanged during generation (AC3-02)" group asserts the resume's block composition is byte-identical before/after generation; `test/features/career/resume/reject_suggested_edit_use_case_test.dart`'s "resume remains unchanged" group asserts the same for reject; `resume_suggestion_review_screen_test.dart` covers per-suggestion Accept/Reject actions.

**⚠️ Deviation from PRD §6 AC3-03/§22.3 D-08, made explicitly during Milestone 3's review (see [03-decisions.md](03-decisions.md) D-M3-04):** the PRD's own text says `SuggestionFabricationGuard` "flags... never auto-rejects." The implementation matches this exactly — **the guard is flag-only**. It never blocks generation, never blocks acceptance, never prevents a `SuggestedEdit` from being persisted or shown. It inspects `originalValue`/`suggestedValue` (plus, for accept, nothing extra — accept does not re-run the guard) and surfaces a "Review carefully" warning in the review screen when it finds a number or capitalized word-like token in the suggested text with no match anywhere in the grounding text. The word "deviation" above refers only to the fact that an earlier draft of this session's own instructions momentarily proposed a stricter reject-based reading before the flag-only interpretation was confirmed against the PRD text and locked in — the **shipped code has never implemented reject-based blocking**.

**Manual verification:** real-device per-suggestion latency check — outstanding, no device available.

**Current status: ✅ COMPLETE — committed and pushed.**
- Commit: `2f92bba feat(v3): implement milestone 3 ai rewrite suggestions` — 25 files changed, 2533 insertions(+), 7 deletions(-).
- Full-suite test result: **1319/1319 passing**, `flutter analyze`: 0 issues — both freshly re-verified in this documentation session (re-run twice after unrelated environment/connection interruptions corrupted two earlier attempts; both clean re-runs confirmed identical results).
- `origin/main` verified to point at `2f92bba` (`git ls-remote origin refs/heads/main`), identical to local `HEAD`.

---

## Milestone 4 — Import depth, suggestions-while-typing, remaining templates, second model tier

**Objective:** Deepen the import review flow (per-entry editable, not just title-editable), add the two-tier debounced writing-suggestion feature, deliver the remaining ~6 archetypes, and add the opt-in stronger-model catalog entry + upgrade prompt.

**Depends on:** Milestone 1 (template engine/layout primitives must exist for the remaining archetypes to reuse them). Milestone 0 (`device_info_plus`/`DeviceCapabilityService`).

**Major deliverables** (PRD §25, as actually built): `ResumeWritingHeuristics` (Tier 1, deterministic) + `BulletSuggestionField` widget (Tier 1 + Tier 2 debounced trigger, backed by a new non-persisting `GenerateBulletRewriteUseCase`); per-entry-editable import review (`resume_import_screen.dart` rewritten, `ResumeImportController.updateDraft`) plus the PRD §10 optional LLM-assisted import second pass (`GenerateImportSecondPassUseCase`); a second `ModelCatalog` LLM entry (`Qwen2.5-3B-Instruct`, opt-in, never default) + `resume_model_upgrade_prompt_screen.dart` shown once before first entry into the Resume feature (`AppSettings.hasSeenResumeModelUpgradePrompt`); the remaining archetypes, then a dedicated **Beta Template Quality Pass** (see below) and a **beta scope decision** to ship 10 curated templates rather than 20.

**Beta scope decision (explicit product decision, recorded in [03-decisions.md](03-decisions.md) D-M4-04):** the catalog ships **10 genuinely distinct archetypes, one curated token preset each (10 total selectable templates)**, not 10 archetypes × 2 presets (20). This directly satisfies PRD §8's own definition of "~20 templates" as "10 archetypes × 2 presets" while explicitly rejecting a warm/cool color swap as counting toward "genuinely distinct." All 10 archetypes were individually verified structurally distinct (different column layout, content order, header treatment, or heading rhythm - see `resume_design_tokens.dart`'s `SectionHeadingStyle`/`headerCentered`/`nameUsesAccentColor`/`skillsAsChips` tokens, D-M4-01) before this reduction, so no archetype was removed to reach 10 - the reduction is purely the preset multiplier.

**Acceptance criteria** (PRD §25, as adjusted by the beta scope decision above): all 10 beta templates exist and pass the ATS round-trip test; declining the stronger model does not degrade feature availability, only suggestion quality (re-verifies FR3-16, dedicated test); import review is per-entry editable. **Met.**

**Historical note (later Beta Product Validation pass, post-M5):** the gallery/selection UI was narrowed further, from these 10 built archetypes to **5** exposed for beta (`ResumeTemplateCatalog.enabled`) — a distinct, later product decision, not a correction of the M4 decision above. See [11-gap-analysis.md](11-gap-analysis.md) FR3-04 and [10-v3-progress.md](10-v3-progress.md)'s "BETA BASELINE" section for the current, authoritative template count.

**Manual verification:** real-device typing-latency feel-check for the debounced suggestion trigger — **still outstanding**. A limited AI-assisted visual inspection of actual rendered PDFs (not a full human review) was performed during the Beta Template Quality Pass and found/fixed one real defect (a centered-header bug, D-M4/M5) — **a genuine human visual review against the Enhance CV bar has still not been performed** (RV3-10, unchanged).

**Current status: ✅ COMPLETE — committed and pushed.**
- Commit: `7219ac5 feat(v3): finalize milestone 4 beta resume templates`.
- Full-suite test result: **1407/1407 passing** at commit time (down from 1485 mid-session — expected: fewer catalog entries means fewer per-template loop iterations in the archetype/renderer test suites, not a regression). `flutter analyze`: 0 issues.

---

## Milestone 5 — Hardening

**Objective:** Close the module's remaining test/documentation/verification debt rather than add new functionality - make the existing V3 implementation safe and credible enough for beta testing.

**Depends on:** Milestones 0–4 (verifies/backfills everything they built).

**Major deliverables, as actually built:**
- **Privacy/local-data audit** (code-level, not a grep-only check): confirmed zero network-capable symbols anywhere in `lib/features/career/`/`lib/services/resume/`/`lib/services/career/`; confirmed zero logging (`AppLogger`) usage anywhere in the resume/JD feature code, so no resume/JD content is ever logged, even locally; confirmed no crash-reporting/analytics SDK exists in this app at all (`pubspec.yaml` has none); reviewed every exception message surfaced to the user in the resume feature - the one content-adjacent case (`BlockInUseException` showing a resume's own title, e.g. "used in 2 resumes: Backend-Focused, Full-Stack") stays entirely on-device and is a legitimate, expected UX message, not a privacy gap.
- **PDF metadata check** (§14): confirmed by direct source inspection of `package:pdf` 3.11.3 (`Document`'s constructor only builds a `/Info` dictionary if at least one of title/author/creator/subject/keywords/producer is explicitly passed) **and** empirically, against real rendered PDF bytes for all 10 beta templates, that zero identifying metadata keys (`/Info`, `/Producer`, `/Author`, `/Title`, `/Creator`, `/Subject`, `/Keywords`) exist in any generated resume PDF today. No fix was needed. A permanent regression test (`test/services/resume/resume_pdf_metadata_test.dart`) now guards this property against a future dependency upgrade or an accidental `pw.Document(title: ...)` call.
- **AI/model failure hardening**: reviewed all AI-touching paths (semantic matching, suggestion generation, bullet rewrite, import second pass, model upgrade/decline, model loading) against the PRD's ten listed safety properties - all already held true from M3/M4's own architecture (every call wrapped in `try`/`catch`, proposal-only gate, explicit accept/reject, no partial DB writes on failure). No production code change was needed beyond the RAM-sequencing fix below.
- **RAM/device-capability sequencing (RV3-04, D-11) - actually implemented, closing the single clearest "designed in the PRD, never wired up" gap the risk register had flagged since Milestone 0:** `GenerateResumeSuggestionsUseCase` now calls `ModelLifecycleManager.unmanagedUnload(ModelKind.embedding)` on a non-high-RAM-tier device, right after its own embedding-backed analysis pass completes and right before its LLM-backed rewrite loop begins - the one place in the whole pipeline where both passes run back-to-back with no user-interaction gap. Reuses the existing idle-unload/reference-counting machinery (`ModelLifecycleManager`) and `DeviceCapabilityService` unchanged - no new concurrency architecture. 5 dedicated tests cover the policy (low-tier unloads, high-tier skips, unknown-RAM degrades to the safer low-tier behavior, never interrupts a still-in-use caller, never runs before an early return).
- **ATS/PDF validation investigation (RV3-05/RV3-13)**: confirmed by direct inspection that `PdfParser` (`read_pdf_text`) is a genuine platform-channel wrapper with no pure-Dart path - it cannot run under `flutter test` and was not faked. The strongest feasible automated check was added instead: two new tests in `integration_test/app_test.dart` (this project's existing, already-established real-device/emulator test file) that render every beta template to a real PDF and extract it back through the *actual* native `PdfParser` - the literal PRD §23 mechanism. These are statically verified (`flutter analyze` clean) but **could not be executed in this implementation environment** (no Android device/emulator attached) - their result is unverified until the next real-device run.
- **Targeted widget test backfill**: `resume_template_gallery_screen_test.dart` added for the screen most heavily rewritten this session with previously zero coverage (verifies all 10 beta cards render with correct names/ATS-confidence labels, no stale preset-suffix text, and template selection persists `templateId`).

**Acceptance criteria:** PRD §24's full acceptance-criteria list, in aggregate — see [09-definition-of-done.md](09-definition-of-done.md)'s criterion-by-criterion table for the honest current status of each.

**Manual verification, explicitly still outstanding:** real-device RAM detection/performance benchmarking (§19); the new `integration_test/app_test.dart` ATS round-trip tests have never been run on a real device; human visual/PDF review against the Enhance CV bar (RV3-10).

**Current status: ✅ COMPLETE — committed and pushed.**
- Commit: see [07-git-strategy.md](07-git-strategy.md) for the exact hash.
- Full-suite and `flutter analyze` results: see [08-quality-gates.md](08-quality-gates.md).

---

## Status legend

⬜ Not started · 🔄 In progress / implemented but uncommitted · ✅ Done (committed, tested, verified, pushed to `origin/main`)

## Overall V3 status snapshot

M0 ✅ · M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 ✅

**V3 is technically beta-ready** — every milestone's own acceptance criteria are met, `flutter analyze` is clean, and the full test suite passes. This is **not** the same claim as "production ready" or "fully verified": real-device RAM/performance/latency benchmarking, the new native-extraction ATS round-trip test, and a genuine human visual review against the Enhance CV bar are all still outstanding and require a physical device/human reviewer this implementation environment does not have - see [09-definition-of-done.md](09-definition-of-done.md) for the precise, criterion-by-criterion breakdown of what "beta-ready" does and does not mean here.
