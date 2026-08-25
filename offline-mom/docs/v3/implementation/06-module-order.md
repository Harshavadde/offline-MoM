# V3 In-Milestone Module Order

Answers "what should be implemented first, second, third" inside each milestone — [05-dependency-graph.md](05-dependency-graph.md) covers the milestone-to-milestone order; this document covers the order *within* one milestone. Principle, consistent throughout: **service/model layer before UI, tests alongside the layer that makes them meaningful, DI wiring only after the components it wires already exist.**

**Last updated:** 2026-08-10 — Milestones 0–5 below are all now recorded as **what actually happened**, confirmed against each milestone's own commit (`git show --stat` for M0–M4; Milestone 5's own diff for M5), not a plan.

## Milestone 0 (as actually built)

1. Schema first: migration v17 (`M0-T01`), registered in both real and test database bootstraps (`M0-T02`).
2. Models: `SuggestedEdit` (`M0-T03`), extended `Resume`/`ResumeVersion` (`M0-T06`).
3. Repository: `SuggestedEditRepository` (`M0-T04`).
4. Independent service: `DeviceCapabilityService` (`M0-T05`) — no dependency on the above.
5. UI/controller wiring last: `target_role` field (`M0-T07`), version restore (`M0-T08`).
6. DI registration (`M0-T09`) — last.

## Milestone 1 (as actually built)

1. `ResumeDesignTokens` and `ResumeTemplateSpec` — pure data/value types, no dependency on anything else.
2. Layout primitives (header/section/entry/sidebar/divider) — depend only on tokens.
3. `ResumeContentPlan`/`ResumeContentPlanBuilder` (D-M1-01, beyond the PRD's literal file list) — the shared ordering abstraction both the renderer and the ATS-round-trip tests consume.
4. `ResumeTemplateCatalog` — depends on `ResumeTemplateSpec`.
5. One archetype at a time (Classic Single-Column → Modern Accent-Rule → Two-Column Sidebar → Compact Technical), each followed by its own render + ATS round-trip + long-synthetic-resume test before starting the next — this order is exactly what caught the `pw.Row`/`pw.Expanded` pagination bug (D-M1-02) on the Two-Column Sidebar archetype specifically, before it could be silently duplicated into a later archetype's own composition.
6. `ResumeTemplateRenderer` + `ResumePdfExportService` refactor — only once real archetypes existed to render against.
7. Thread `templateId` through `save_resume_version_use_case.dart`.
8. UI last: gallery screen + providers, Editor entry point, router registration.
9. DI registration — last.

## Milestone 2 (as actually built)

1. `ResumeJdSemanticMatcher` — pure service, depends only on the pre-existing `EmbeddingEngine` interface; built and unit-tested (including its own failure-handling) before touching `ResumeJdAnalyzer` at all.
2. `MatchSource` enum + field added to `ResumeJdAnalysisResult`/`SkillMatchResult`/`RequirementCheckResult` — a model change, made before the analyzer logic that populates it, so the analyzer's own changes had a real type to return.
3. `ResumeJdAnalyzer._applySemanticTier` — the additive semantic pass, added as a strictly-optional constructor parameter (`ResumeJdAnalyzer({ResumeJdSemanticMatcher? semanticMatcher})`) so every pre-existing call site kept compiling unchanged.
4. `PrioritizeResumeContentUseCase` — independent of the above three; built and tested as its own pure use case.
5. UI last: per-finding "Go to Editor" action on `resume_jd_analysis_screen.dart`.
6. DI registration (`resumeJdSemanticMatcherProvider`, updated `resumeJdAnalyzerProvider`, `prioritizeResumeContentUseCaseProvider`) — last, including the construction-time failure handling added after a real regression was found in a pre-existing test (D-M2-02).

## Milestone 3 (as actually built)

1. `LlmEngine.generateFromPrompt` (real `LlamaDartLlmEngine` implementation + `FakeLlmEngine` test double) — the one new low-level capability every other M3 component depends on; built and verified first, including updating the 3 other local test-fakes of `LlmEngine` the interface change touched.
2. `ResumeSuggestionPromptBuilder` — pure, stateless, no dependency on the engine itself, built and unit-tested independently (deterministic-structure/fabrication-instructions/missing-data tests) before any generation code called it.
3. `SuggestionFabricationGuard` — independent of the above two; built and unit-tested (including promoting `resume_jd_analyzer.dart`'s private `_normalize` to the shared `normalizeResumeText`) before being wired into the review-list provider.
4. `GenerateResumeSuggestionsUseCase` — the orchestrator, depends on steps 1–3 plus the pre-existing `ResumeJdAnalyzer`/`ResumeCompilerService`/`SuggestedEditRepository`/`LlmRequestQueue`; its dedicated AC3-02 test (resume-unchanged-during-generation) was written alongside it, not after.
5. `AcceptSuggestedEditUseCase`/`RejectSuggestedEditUseCase` — built after generation existed, since Accept's re-validation logic needed real `SuggestedEdit` rows to test against.
6. UI/providers last: `resume_suggestion_providers.dart` (generation-trigger controller, review-list provider, accept/reject controller), `resume_suggestion_review_screen.dart`, the JD-analysis-screen generation trigger, the Editor's pending-count entry point.
7. Routing (`route_paths.dart`/`app_router.dart`) — once the screen existed to route to.
8. DI registration (`app_providers.dart`) — last.

## Milestone 4 (as actually built)

1. `ResumeWritingHeuristics` (Tier 1, deterministic, zero-cost) — built and unit-tested first, independent of any AI/UI dependency, mirroring the "deterministic logic before AI-touching code" rule.
2. `BulletSuggestionField` (Tier 2, debounced LLM-backed) — depends on Tier 1 existing as its always-available fallback; built and tested (including debounce-timing behavior) before wiring into any block editor screen.
3. The 6 additional archetypes — each depends only on M1's existing tokens/primitives, built and individually re-verified structurally distinct (D-M4-01) before moving to the next.
4. Per-entry-editable import review — extends the pre-existing, unchanged-since-before-V3 import review screen; independent of the above.
5. Second LLM tier + model-upgrade-prompt screen — depends on `ModelCatalog`'s existing tier mechanism and `DeviceCapabilityService` (M0, its first real consumer) for the tier recommendation shown in the prompt copy.
6. UI/DI wiring last, as in every prior milestone.
7. Manual PDF inspection against the Enhance CV bar (AI-assisted spot-check, not a substitute for human review) — performed after all archetypes existed, catching and fixing D-M4-02/D-M4-03.

## Milestone 5 (as actually built)

Milestone 5 inverted the usual "new logic first" order, since it is a verification/hardening pass, not new-feature construction — the actual order followed the PRD's own phase numbering:

1. Read PRD + all `docs/v3/implementation/*.md` to build an internal checklist (Phase 1) — no code touched yet.
2. Privacy/local-data code audit (Phase 2) — read-only investigation, zero code changes.
3. PDF metadata inspection (Phase 3) — read-only investigation (source + empirical probe); a regression test was added, no renderer code changed since none was needed.
4. AI/model failure hardening verification (Phase 4) — read-only investigation across every AI code path; no code changes needed, since all 10 required safety properties already held.
5. RAM/device-capability sequencing (Phase 5) — the one genuine code change this milestone made: `_releaseEmbeddingModelIfLowTier()` inserted into `GenerateResumeSuggestionsUseCase.call()`, with its own 5 tests, following the general rule (logic change + tests before anything downstream depends on it — nothing does, since this is an internal sequencing detail with no new UI).
6. ATS/PDF real validation (Phase 6) — 2 new tests added to the existing `integration_test/app_test.dart`, no production code changed.
7. Widget-test backfill (Phase 7) — `resume_template_gallery_screen_test.dart` added against the already-existing, unmodified gallery screen.
8. Full regression + `flutter analyze`, once (Phase 8).
9. Documentation sync (Phase 10) — last, after every code/test change above was final.

## General rule for every later milestone (post-beta)

1. Any new deterministic/service-layer logic (no AI, no UI) first, with its own unit tests.
2. Any new AI-touching use case next, with a fake-engine-backed test proving its contract before any screen depends on it.
3. UI/controller wiring after the logic it displays already exists and is tested.
4. DI registration in `app_providers.dart` last.
5. Widget/UI tests for the new screen, plus continued backfill for any pre-existing screen still without coverage (RV3-15, [04-risk-register.md](04-risk-register.md), narrowed but not closed by Milestone 5).

This is the same order Milestones 0–4 were actually built in, confirmed retroactively against each milestone's own commit; Milestone 5 is the one exception, following its own verification-phase order instead, documented separately above.
