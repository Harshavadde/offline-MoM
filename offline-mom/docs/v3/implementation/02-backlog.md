# V3 Engineering Backlog

Converts [01-master-roadmap.md](01-master-roadmap.md)'s milestone deliverables into individually trackable tasks, derived directly from `docs/v3/01-prd.md` §25. No task below is speculative — every one traces to a specific file the PRD names for its milestone, or (where the repository genuinely diverged from the PRD's literal file list) the real file that ended up serving that purpose, cross-referenced to [03-decisions.md](03-decisions.md).

**Status legend:** ⬜ Not started · 🔄 Implemented, uncommitted · ✅ Done (committed + tested + pushed)

## Milestone 0 — Data model & device foundation — ✅ ALL DONE

Commits: `dd4a03d` (implementation), `0e47848` (this documentation directory's original creation).

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M0-T01 | Migration v17: `suggested_edits` table + additive `resumes`/`resume_versions` columns | `lib/database/migrations/v17.dart` | None | ✅ Done |
| M0-T02 | Register migration v17 in the real and test database bootstrap paths | `lib/database/app_database.dart`, `lib/core/constants/app_constants.dart` (`sqliteDbVersion` → 17), `test/test_helpers/test_database.dart` | M0-T01 | ✅ Done. Note: the PRD names `lib/database/test_database.dart` for this — that file does not exist; the real helper is `test/test_helpers/test_database.dart` (see [03-decisions.md](03-decisions.md) ID-01) |
| M0-T03 | `SuggestedEdit` model (schema/CRUD DTO) | `lib/models/suggested_edit.dart` | M0-T01 | ✅ Done |
| M0-T04 | `SuggestedEditRepository` (real Sqflite implementation) | `lib/repositories/suggested_edit_repository.dart` | M0-T01, M0-T03 | ✅ Done |
| M0-T05 | `DeviceCapabilityService` (real `device_info_plus` implementation + `FakeDeviceCapabilityService` + `recommendedTierForRamMb`) | `lib/services/device/device_capability_service.dart`, `pubspec.yaml` (`device_info_plus` dependency) | None | ✅ Done |
| M0-T06 | Extend `Resume`/`ResumeVersion` table constants and models for the new columns | `lib/database/tables.dart`, `lib/models/resume.dart`, `lib/models/resume_version.dart` | M0-T01 | ✅ Done |
| M0-T07 | Wire `target_role` into the Editor's Profile card (closes the pre-existing dead-field gap) | `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` | M0-T06 | ✅ Done. `resume_editor_providers.dart` did not need modification (see [03-decisions.md](03-decisions.md) ID-02) |
| M0-T08 | Resume-version restore-to-draft flow | `lib/features/career/resume/presentation/providers/resume_version_providers.dart` (`restoreToDraft()`), `lib/features/career/resume/presentation/screens/resume_versions_screen.dart` ("Restore" action) | M0-T06 | ✅ Done |
| M0-T09 | Register new providers in the composition root | `lib/providers/app_providers.dart` (`suggestedEditRepositoryProvider`, `deviceCapabilityServiceProvider`) | M0-T04, M0-T05 | ✅ Done |

**Milestone 0 total:** 9/9 tasks done.

## Milestone 1 — Template engine — ✅ ALL DONE

Commit: `d67528a`.

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M1-T01 | `ResumeDesignTokens` (type scale, spacing scale, color roles, page rules) | `lib/services/resume/template/resume_design_tokens.dart` | None | ✅ Done |
| M1-T02 | `ResumeTemplateSpec` (archetype id + token preset id + metadata) | `lib/services/resume/template/resume_template_spec.dart` | None | ✅ Done |
| M1-T03 | `ResumeTemplateCatalog` (static list of specs — 4 archetypes × 2 presets = 8 entries, confirmed by direct inspection) | `lib/services/resume/template/resume_template_catalog.dart` | M1-T01, M1-T02 | ✅ Done |
| M1-T04 | Layout primitives (header block, section block, entry block, sidebar column, divider) | `lib/services/resume/template/layout/header_block.dart`, `section_block.dart`, `entry_block.dart`, `sidebar_column.dart`, `divider.dart` | M1-T01 | ✅ Done |
| M1-T04b | *(beyond PRD's literal list, see D-M1-01)* `ResumeContentPlan`/`ResumeContentPlanBuilder`/`content_line_renderer.dart` — shared content/ordering abstraction enabling ATS-testable reading order | `lib/services/resume/template/resume_content_plan.dart`, `resume_content_plan_builder.dart`, `template/layout/content_line_renderer.dart` | M1-T04 | ✅ Done |
| M1-T05 | Archetype: Classic Single-Column | `lib/services/resume/template/archetypes/classic_single_column.dart` | M1-T04 | ✅ Done |
| M1-T06 | Archetype: Modern Accent-Rule | `lib/services/resume/template/archetypes/modern_accent_column.dart` | M1-T04 | ✅ Done |
| M1-T07 | Archetype: Two-Column Sidebar (pagination via `package:pdf` `Partitions`/`Partition`, not `pw.Row`/`pw.Expanded` — see D-M1-02) | `lib/services/resume/template/archetypes/two_column_sidebar.dart` | M1-T04 | ✅ Done |
| M1-T08 | Archetype: Compact Technical | `lib/services/resume/template/archetypes/compact_technical.dart` | M1-T04 | ✅ Done |
| M1-T09 | `ResumeTemplateRenderer`; refactor `ResumePdfExportService`'s internals onto it (atomic-write preserved; default archetype = Classic Single-Column for pre-Milestone-1 versions) | `lib/services/resume/resume_template_renderer.dart`, `lib/services/resume/resume_pdf_export_service.dart` | M1-T03, M1-T05..T08 | ✅ Done |
| M1-T10 | Thread `templateId` through version-saving | `lib/features/career/resume/save_resume_version_use_case.dart` | M1-T09 | ✅ Done |
| M1-T11 | Template gallery screen + providers | `lib/features/career/resume/presentation/screens/resume_template_gallery_screen.dart`, `lib/features/career/resume/presentation/providers/resume_template_providers.dart` | M1-T03 | ✅ Done |
| M1-T12 | Template-picker entry point in the Editor | `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` | M1-T11 | ✅ Done |
| M1-T13 | Gallery route registration | `lib/core/router/route_paths.dart`, `lib/core/router/app_router.dart` | M1-T11 | ✅ Done |
| M1-T14 | DI registration for new providers | `lib/providers/app_providers.dart` | M1-T01..T13 | ✅ Done |
| M1-T15 | ATS extraction round-trip test per archetype | `test/services/resume/resume_template_renderer_test.dart`, `test/services/resume/template/*` | M1-T05..T09 | ✅ Done |

**Milestone 1 total:** 16/16 tasks done (15 from the original breakdown + 1 beyond-PRD addition).

## Milestone 2 — Deterministic tailoring depth — ✅ ALL DONE

Commit: `30bf491`.

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M2-T01 | `ResumeJdSemanticMatcher` — cosine-similarity lookup via `EmbeddingEngine`, catches failure and returns null (never throws) | `lib/services/career/resume_jd_semantic_matcher.dart` | Existing `EmbeddingEngine` | ✅ Done |
| M2-T02 | `matchSource` field (`MatchSource` enum: `exactKeyword`/`alias`/`semanticEmbedding`/`tokenOverlap`) on `ResumeJdAnalyzer`'s result, additive semantic tier | `lib/services/career/resume_jd_analyzer.dart`, `lib/models/resume_jd_analysis_result.dart` | M2-T01 | ✅ Done |
| M2-T03 | `PrioritizeResumeContentUseCase` — deterministic re-rank of Experience/Projects/Skills by requirement-match density; Education/Certifications left untouched | `lib/features/career/analysis/prioritize_resume_content_use_case.dart` | None | ✅ Done |
| M2-T04 | Per-finding "Go to Editor" action on the analysis results screen | `lib/features/career/analysis/presentation/screens/resume_jd_analysis_screen.dart` | None | ✅ Done |
| M2-T05 | Wire `EmbeddingEngine`/semantic matcher into the analyzer's DI construction | `lib/providers/app_providers.dart` | M2-T01, M2-T02 | ✅ Done |

**Milestone 2 total:** 5/5 tasks done. Full-suite result at commit time: 1256/1256, `flutter analyze` 0 issues.

## Milestone 3 — AI rewrite suggestions — ✅ ALL DONE

Commit: `2f92bba`.

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M3-T01 | `LlmEngine.generateFromPrompt(systemPrompt, userPrompt)` — new engine method, no existing method fit a caller-composed bounded prompt | `lib/services/ai/llm_engine.dart`, `lib/services/ai/llamadart_llm_engine.dart` | None | ✅ Done |
| M3-T02 | `ResumeSuggestionPromptBuilder` — pure, stateless, bounded (one entry + one requirement) prompt construction | `lib/services/resume/resume_suggestion_prompt_builder.dart` | None | ✅ Done |
| M3-T03 | `SuggestionFabricationGuard` — deterministic lexical flag (new numbers/proper nouns vs. grounding text); **flag-only, never blocks** (see D-M3-04) | `lib/services/resume/suggestion_fabrication_guard.dart` | Reuses `normalizeResumeText` promoted from `resume_jd_analyzer.dart` | ✅ Done |
| M3-T04 | `GenerateResumeSuggestionsUseCase` — reuses M2's analyzer output, bounded per-entry calls via `LlmRequestQueue`, persists via `SuggestedEditRepository`; never mutates resume content | `lib/features/career/analysis/generate_resume_suggestions_use_case.dart` | M3-T01, M3-T02, M2-T01..T05 | ✅ Done |
| M3-T05 | `AcceptSuggestedEditUseCase` — re-validates pending status, target-block attachment, and current-content match before applying via `ResumeBlockRepository.setOverride` | `lib/features/career/resume/accept_suggested_edit_use_case.dart` | M0's `SuggestedEditRepository`, existing `ResumeCompilerService`/`ResumeBlockRepository` | ✅ Done |
| M3-T06 | `RejectSuggestedEditUseCase` — status-only change, idempotent on already-rejected, throws on already-accepted | `lib/features/career/resume/reject_suggested_edit_use_case.dart` | M0's `SuggestedEditRepository` | ✅ Done |
| M3-T07 | Suggestion review screen + providers (pending list, lazily-computed fabrication flag, accept/reject controller) | `lib/features/career/resume/presentation/screens/resume_suggestion_review_screen.dart`, `lib/features/career/resume/presentation/providers/resume_suggestion_providers.dart` | M3-T04..T06 | ✅ Done |
| M3-T08 | Generation trigger on the JD Analysis results screen (not the Editor — see D-M3-03) | `lib/features/career/analysis/presentation/screens/resume_jd_analysis_screen.dart` | M3-T04 | ✅ Done |
| M3-T09 | Pending-suggestion-count badge/entry point on the Editor screen | `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` | M3-T07 | ✅ Done |
| M3-T10 | Route registration for the review screen | `lib/core/router/route_paths.dart`, `lib/core/router/app_router.dart` | M3-T07 | ✅ Done |
| M3-T11 | DI registration for all new use cases/services | `lib/providers/app_providers.dart` | M3-T01..T09 | ✅ Done |

**Milestone 3 total:** 11/11 tasks done. Full-suite result: 1319/1319, `flutter analyze` 0 issues (both re-verified fresh in this documentation session).

## Milestone 4 — Import depth, suggestions-while-typing, remaining templates, second model tier — ✅ ALL DONE

Commit: `7219ac5 feat(v3): finalize milestone 4 beta resume templates`.

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M4-T01 | `ResumeWritingHeuristics` (Tier 1, deterministic weak-verb/measurable-detail detection) | `lib/services/resume/resume_writing_heuristics.dart` | None | ✅ Done |
| M4-T02 | `BulletSuggestionField` widget (Tier 1 always-on + Tier 2 debounced model-backed trigger) | `lib/features/career/resume/presentation/widgets/bullet_suggestion_field.dart`, `generate_bullet_rewrite_use_case.dart` | M4-T01, M3-T01..T04 (Tier 2 reuses the LLM path, deliberately not the `SuggestedEdit` pipeline - see D-M4 in [03-decisions.md](03-decisions.md)) | ✅ Done |
| M4-T03 | Remaining archetypes: Executive Summary-Led, Minimalist Monochrome, Entry-Level/Student, Government/Public-Sector Dense, Creative/Visual-First, Two-Column (Right Sidebar) | `lib/services/resume/template/archetypes/executive_summary_led.dart`, `minimalist_monochrome.dart`, `entry_level_student.dart`, `government_dense.dart`, `creative_visual.dart`, `two_column_right.dart` | M1's layout primitives | ✅ Done |
| M4-T03b | *(beyond the PRD's literal ask, Beta Template Quality Pass)* Structural/typographic differentiation tokens + beta-scope catalog reduction to 10 curated templates | `resume_design_tokens.dart`, `resume_template_catalog.dart`, `template/layout/{header_block,entry_block,section_block,chip_list}.dart` | M4-T03 | ✅ Done - see D-M4-01/D-M4-04, [03-decisions.md](03-decisions.md) |
| M4-T04 | Per-entry-editable import review + PRD §10 optional LLM-assisted second pass | `lib/features/career/resume/presentation/screens/resume_import_screen.dart`, `resume_import_providers.dart`, `generate_import_second_pass_use_case.dart` | None | ✅ Done |
| M4-T05 | Second `ModelCatalog` LLM tier | `lib/services/ai/model_catalog.dart` | None | ✅ Done |
| M4-T06 | Model-upgrade prompt before first Resume-feature entry | `lib/features/career/resume/presentation/screens/resume_model_upgrade_prompt_screen.dart`, `resume_list_screen.dart` (surfacing point), `AppSettings.hasSeenResumeModelUpgradePrompt` | M4-T05, M0's `DeviceCapabilityService` | ✅ Done |

**Milestone 4 total:** 7/7 tasks done (6 from the original breakdown + 1 beyond-PRD quality/scope addition).

## Milestone 5 — Hardening — ✅ ALL DONE

Commit: see [07-git-strategy.md](07-git-strategy.md) for the exact hash.

| ID | Task | Relevant files | Dependency | Status |
|---|---|---|---|---|
| M5-T01 | Privacy/local-data code audit (network calls, logging, error-message content, crash reporting) | No production files changed - audit found no gap | None | ✅ Done |
| M5-T02 | PDF metadata check - inspected `package:pdf` defaults, verified empirically against real rendered bytes, added a permanent regression test | `test/services/resume/resume_pdf_metadata_test.dart` | None | ✅ Done - no fix needed, see [04-risk-register.md](04-risk-register.md) RV3-07 |
| M5-T03 | AI/model failure-hardening review across all AI-touching paths | No production files changed - all ten listed safety properties already held | None | ✅ Done |
| M5-T04 | RAM/device-capability sequencing (RV3-04) - actually wire `DeviceCapabilityService`/`ModelLifecycleManager` into the tailoring pipeline | `lib/features/career/analysis/generate_resume_suggestions_use_case.dart`, `lib/providers/app_providers.dart` | M0's `DeviceCapabilityService`/`ModelLifecycleManager` (already existed, previously unconsumed) | ✅ Done, 5 dedicated tests |
| M5-T05 | ATS/PDF validation investigation - confirm `PdfParser` cannot run under `flutter test`, add the strongest feasible real-device test instead | `integration_test/app_test.dart` | None | ✅ Done, statically verified; execution requires a real device (outstanding) |
| M5-T06 | Targeted widget-test backfill for the highest-risk previously-uncovered screen | `test/features/career/resume/presentation/screens/resume_template_gallery_screen_test.dart` | None | ✅ Done |
| M5-T07 | Full regression suite + `flutter analyze`, run once after all changes | N/A (verification only) | M5-T01..T06 | ✅ Done - see [08-quality-gates.md](08-quality-gates.md) |
| M5-T08 | Documentation sync across all 12 implementation-tracking files | `docs/v3/implementation/*.md` | M5-T01..T07 | ✅ Done (this pass) |

**Milestone 5 total:** 8/8 tasks done. Explicitly **not** done as part of M5 (both require resources this implementation environment does not have, disclosed rather than skipped): real-device RAM/performance benchmarking (PRD §19); a genuine human visual review against the Enhance CV bar (RV3-10); formal `ADR-0XX`-numbered decision entries in V2's exact historical format (the decision log itself - [03-decisions.md](03-decisions.md) - is complete and current, just not renumbered into that specific format, since doing so would not change any decision's actual content).
