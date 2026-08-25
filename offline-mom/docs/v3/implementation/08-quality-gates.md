# V3 Quality Gates

Explicit pass/fail gates per milestone, in the same spirit as [docs/v2/implementation/08-quality-gates.md](../../v2/implementation/08-quality-gates.md). The AI safety gates (AC3-01 through AC3-06) apply from Milestone 3 onward — they are the PRD's own named hard constraints (§6), not ordinary test coverage.

**Last updated:** 2026-08-10, Milestone 5 finalized.

## Gate structure (every milestone)

- **Required tests:** every new/modified file in that milestone's own file list has a passing test exercising its behavior (not merely "compiles").
- **`flutter analyze`:** 0 issues, project-wide, re-run after the milestone's changes.
- **Full regression suite:** the entire `flutter test` suite, not just the milestone's own new tests — the number below is the actual `+N: All tests passed!` total from a real `flutter test` run.
- **Acceptance criteria:** the specific criteria PRD §25 states for that milestone, verified against actual test/analyze output.
- **Manual verification:** the milestone's own manual-verification item (mostly real-device checks) is explicitly logged as outstanding, never silently skipped.
- **Commit gate:** `git status`/`git diff --stat` reviewed to confirm the staged set is exactly that milestone's files before committing.

**A note on what "N/N tests" means below, since the two milestone pairs were measured differently:**
- **Milestone 0's "56/56"** is a *milestone-scoped* count — the 6 test files M0 added/extended, run in isolation, not the whole suite.
- **Milestone 1's "457/457"** is reported from the original implementation session as a broader regression-suite figure at that point in the project's history; it was **not independently re-executed against the historical `d67528a` commit during this documentation pass** (doing so would require checking out a historical commit, outside this pass's documentation-only scope) — it is recorded here as a historically-reported result, not freshly re-verified.
- **Milestone 2's "1256/1256" and Milestone 3's "1319/1319" are both full-suite (`flutter test`, no path filter) totals**, and **both were freshly re-run and re-confirmed in this exact documentation session** (Milestone 3's run was re-executed twice after unrelated environment/connection interruptions corrupted two earlier attempts mid-run — both clean re-runs produced the identical 1319/1319 result). These two numbers carry the highest confidence of any figure in this document set.

## Milestone 0 — ✅ Gates passed, committed, pushed

- Required tests: `migration_v17_test.dart`, `suggested_edit_test.dart`, `suggested_edit_repository_test.dart`, `device_capability_service_test.dart`, plus the extended `resume_editor_controller_test.dart`/`resume_version_controller_test.dart` — **56/56 passing** (milestone-scoped count, see note above).
- `flutter analyze`: 0 issues at commit time.
- Acceptance criteria (PRD §25): met — see [01-master-roadmap.md](01-master-roadmap.md).
- Manual verification: real-device RAM read — **still outstanding**.
- Commit gate: `dd4a03d` — file set matched exactly.

## Milestone 1 — ✅ Gates passed, committed, pushed

- Required tests: one test file per new archetype/primitive/token/catalog/content-plan file, plus `resume_template_renderer_test.dart`'s ATS round-trip and long-synthetic-resume tests.
- **ATS extraction round-trip, as actually implemented:** render → build `ResumeContentPlan` → assert expected section headings/reading order (see D-M1-01, [03-decisions.md](03-decisions.md)) — **not** the PRD's literal "extract via `PdfParser`" native-extraction mechanism (RV3-13, [04-risk-register.md](04-risk-register.md)).
- Historically-reported result: 457/457 (see the measurement note above — not re-executed this session).
- `flutter analyze`: 0 issues, historically reported.
- Acceptance criteria (PRD §25): met — 4 archetypes × 2 presets = 8 catalog entries, confirmed by direct inspection of `resume_template_catalog.dart` this session.
- Manual verification: visual review against the Enhance CV quality bar — **still outstanding, no human review has occurred**.
- Commit gate: `d67528a` — file set matched exactly.

## Milestone 2 — ✅ Gates passed, committed, pushed

- Required tests: `resume_jd_semantic_matcher_test.dart`, `prioritize_resume_content_use_case_test.dart`, extended `resume_jd_analyzer_test.dart`, extended `resume_jd_analysis_screen_test.dart` (the module's first widget test).
- **Full suite: 1256/1256 passing**, freshly re-run at commit time (same session that produced the commit).
- `flutter analyze`: 0 issues, freshly re-run at commit time.
- Acceptance criteria (PRD §25): met — semantic tier strictly additive (verified in code, D-M2-01), per-finding "Go to Editor" action tested.
- Manual verification: none specified by the PRD for this milestone.
- Commit gate: `30bf491` — file set matched exactly.

## Milestone 3 — ✅ Gates passed, committed, pushed

- Required tests: `resume_suggestion_prompt_builder_test.dart`, `suggestion_fabrication_guard_test.dart`, `generate_resume_suggestions_use_case_test.dart` (11 tests, including the dedicated AC3-02 "resume remains unchanged during generation" test), `accept_suggested_edit_use_case_test.dart` (9 tests), `reject_suggested_edit_use_case_test.dart` (7 tests), `resume_suggestion_review_screen_test.dart` (7 widget tests).
- **Full suite: 1319/1319 passing**, freshly re-run and re-confirmed twice in this documentation session (each re-run identical).
- `flutter analyze`: 0 issues, freshly re-confirmed twice in this documentation session.
- Acceptance criteria (PRD §25): met — the AC3-02 test passes; the reject-side "resume remains unchanged" test passes; every suggestion is individually actionable (Accept/Reject) in the review screen.
- Manual verification: real-device per-suggestion latency check — **still outstanding**.
- Commit gate: `2f92bba` — file set matched exactly (verified via `git show --stat` containing zero `docs/` files).

## Milestone 4 — ✅ Gates passed, committed, pushed

- Required tests: 6 new archetype test files, extended `resume_writing_heuristics_test.dart`, `bullet_suggestion_field_test.dart` (debounce behavior), extended import-review tests (per-entry editability), extended model-catalog/upgrade-prompt tests.
- **Full suite: 1407/1407 passing**, at commit time.
- `flutter analyze`: 0 issues, at commit time.
- Acceptance criteria (PRD §25): met for the beta-scope catalog — 10 archetypes built, each individually re-verified structurally distinct (never density/color alone), of which **5 are exposed in the beta gallery UI** (Beta Product Validation pass; see [11-gap-analysis.md](11-gap-analysis.md) FR3-04); model-upgrade opt-in offered once, declinable, baseline model remains fully functional; per-entry import review; debounced writing-quality suggestions.
- Manual verification: genuine human visual review against the Enhance CV bar — **not performed** (only an AI-assisted spot-check of sample renders occurred, which found and fixed one real defect — D-M4-03 — but is explicitly not a substitute for human review, see RV3-10).
- Commit gate: `7219ac5` — file set matched exactly.

## Milestone 5 — ✅ Gates passed, staged for a single commit (beta hardening)

- Required work, per PRD-specified phase, not a fixed file list (this milestone is verification/hardening, not new-feature construction):
  - Privacy/local-data audit — real code-level, not grep-only (Phase 2). No fixes needed; findings documented in [04-risk-register.md](04-risk-register.md).
  - PDF metadata check (Phase 3) — `test/services/resume/resume_pdf_metadata_test.dart` (10 cases, one per catalog template), verifying zero identifying metadata in any generated PDF. No fix needed (verified, not assumed).
  - AI/model failure hardening (Phase 4) — verification-only against the PRD's 10 named safety properties; all already true by construction.
  - RAM/device-capability sequencing (Phase 5, RV3-04) — `_releaseEmbeddingModelIfLowTier()` in `generate_resume_suggestions_use_case.dart`, 5 dedicated tests in the extended `generate_resume_suggestions_use_case_test.dart`.
  - ATS/PDF real validation (Phase 6, RV3-13/RV3-05) — 2 new tests in `integration_test/app_test.dart`, statically verified, execution deferred to a real device.
  - Widget-test backfill (Phase 7, RV3-15) — `test/features/career/resume/presentation/screens/resume_template_gallery_screen_test.dart` (3 tests).
- **Full suite: 1425/1425 passing**, freshly run once after all Milestone 5 changes landed.
- `flutter analyze`: 0 issues, freshly re-run after all Milestone 5 changes landed.
- Acceptance criteria (PRD §14/§23/§25 Milestone 5 scope): met — see the phase-by-phase list above and [09-definition-of-done.md](09-definition-of-done.md)'s full criterion table.
- Manual verification: real-device RAM sequencing/ATS-extraction execution and genuine human visual review — both **explicitly still outstanding**, disclosed rather than silently claimed complete (see [09-definition-of-done.md](09-definition-of-done.md)'s three-item caveat list).
- Commit gate: staged for exactly one commit, `feat(v3): complete milestone 5 beta hardening` — hash recorded in [07-git-strategy.md](07-git-strategy.md) once pushed.

## AI safety gates (apply from Milestone 3 onward — the PRD's own named hard constraints, §6)

| Gate | Requirement | Verified how | Status |
|---|---|---|---|
| AC3-01 (fabrication ban) | No prompt ever asks the model to work from more than the one target entry's existing content | Code review of `ResumeSuggestionPromptBuilder.build()` — takes exactly one `entryContextLabel`/`originalText`/`jdRequirement`, no list parameters; `resume_suggestion_prompt_builder_test.dart`'s "one call never leaks another call's entry content" test | ✅ Implemented, code-reviewed. No automated test can fully verify model *behavior* (whether the LLM actually obeys the instruction), only prompt *scope* — this is a disclosed limitation, not a gap in verification effort |
| AC3-02 (proposal-only) | No code path writes LLM output directly into a `resume_blocks`/library-block row | Dedicated architectural test: `generate_resume_suggestions_use_case_test.dart`'s "resume remains unchanged during generation (AC3-02)" group asserts `ResumeBlockRef.overrideJson` is unchanged (and null) before/after a full generation run | ✅ Implemented and tested |
| AC3-03 (deterministic backstop) | Every suggestion passes `SuggestionFabricationGuard` before being shown, **flags, never auto-rejects** | Unit tests on the guard (`suggestion_fabrication_guard_test.dart`, 17 tests): flags a genuinely new number/proper noun, does not false-positive on content present in the input/`additionalGroundingText`; `resume_suggestion_review_screen_test.dart` confirms the "Review carefully" warning renders for a flagged suggestion and does not render for a safe one | ✅ Implemented and tested. **Flag-only confirmed** — see D-M3-04, [03-decisions.md](03-decisions.md) |
| AC3-04 (bounded scope) | No generative call includes more than one entry + one requirement | `ResumeSuggestionPromptBuilder`'s signature itself enforces this structurally (no list parameters); `GenerateResumeSuggestionsUseCase._firstMatchingRequirement` picks exactly one requirement per entry even when multiple could match (D-M3-02) | ✅ Implemented and tested |
| AC3-05 (graceful degradation) | Tailoring completes through deterministic stages even if the LLM/embedding model is unavailable | `resume_jd_analyzer_test.dart`'s "semantic matching" group (embedding failure → deterministic fallback); `generate_resume_suggestions_use_case_test.dart`'s "model unavailable"/"generation failure" groups (LLM failure → zero suggestions, no exception, no crash) | ✅ Implemented and tested |
| AC3-06 (transparency) | Suggestion provenance (accepted vs. user-authored) is never lost | `SuggestedEditRepository.resolve()` only ever updates `status`/`resolved_at`, never `original_value`/`suggested_value` — a rejected or accepted row remains queryable via `getForResume()` indefinitely, confirmed by `suggested_edit_repository_test.dart` (M0) and exercised again by `reject_suggested_edit_use_case_test.dart`'s "not deleted, remains retrievable" test (M3) | ✅ Implemented and tested |

All six AI safety gates are now implemented and covered by passing tests, unchanged in status through Milestones 4 and 5 (neither milestone touched the tailoring-pipeline architecture these gates cover — Milestone 5 Phase 4 was a verification pass that confirmed all six remain true, not a rebuild). This does **not** mean the underlying risks they mitigate (fabrication, low-RAM performance, real-device latency) are eliminated — see [04-risk-register.md](04-risk-register.md) for the honest distinction between "a test exists and passes" and "the risk is resolved."

## Explicit non-claims (per this document's own instruction not to overstate what automated tests prove)

- **No automated test proves visual resume quality.** The Enhance-CV-bar comparison (PRD §25 Milestone 1) requires human judgment and has still not been performed as of Milestone 5's close — only an AI-assisted spot-check of sample renders has occurred (Milestone 4), which is explicitly not a substitute.
- **No automated test proves real-device ATS extraction behavior.** Two real round-trip tests were added in Milestone 5 (`integration_test/app_test.dart`) that verify against the actual native `PdfParser` extraction pipeline rather than `ResumeContentPlan` — but they have not been executed, since no Android device/emulator is available in this environment (RV3-13). Even once executed, this would only prove *this project's own* extraction succeeds, never a specific third-party ATS product's actual behavior (RV3-06, accepted by design).
- **No automated test proves tailoring pipeline performance, or RAM-sequencing correctness, on a real low-RAM device.** RV3-03/RV3-04/RV3-12 remain open — RV3-04's sequencing fix is implemented and unit-tested (Milestone 5), but not device-verified under real memory pressure.
- **No automated test proves physical Android-backgrounding download-resume behavior.** RV3-20's fix (Whisper onboarding download now delegates to the already-resumable `HttpModelDownloadService`) is implemented and covered by 4 new unit tests (`FakeModelDownloadService`), but not device-verified — no physical Android device is available in this environment. Diagnostic logging was added specifically to enable that verification during real beta testing.

## Real-Device Findings Remediation Pass (post-BETA-BASELINE)

A real Android phone install with the user's own actual resume (not a synthetic persona) surfaced real import data loss the entire prior validation history had never caught — see RV3-19, [04-risk-register.md](04-risk-register.md), and `10-v3-progress.md`'s "Post-Beta-Baseline: Real-Device Findings Remediation" section for the full narrative.

| Gate | Result |
|---|---|
| `flutter analyze` (project-wide) | **0 issues.** The only 2 lint `info`s found anywhere are inside `test/manual/*.dart` (this pass's own throwaway diagnostic scripts, excluded from git) |
| `flutter test` (full suite) | **1528/1528 passing**, run once after all of Phases 1–9's changes landed together |
| Release build | **Succeeds with a genuinely unmasked, non-piped exit-code check** (`REAL_EXIT_CODE=0`) — required `--target-platform android-arm,android-arm64` be added to the build command; see RV3-21/D-M7-05. Both ABI APKs re-confirmed at their expected sizes and native-library composition (llama.cpp/Whisper/FFmpeg present, LiteRT-LM/model-weight files absent) |
| Real-resume import fidelity | Re-verified against the user's actual resume text: name, full Work Experience, full Education, coherent Summary, and Indian ("Hyderabad, Telangana") location all now import and render correctly across all 5 beta templates (RV3-19, RESOLVED) |
| Whisper onboarding download resumability | Code/unit-test verified (RV3-20, RESOLVED at that level) — **not** physical-device verified, explicitly disclosed |
| JD tailoring | Revalidated after the parser/template changes above — all 46 relevant tests (fabrication guard, profile-protection guard, `SuggestedEdit` gate) pass unchanged |

## Reliability-Overhaul Pass (post-`636eeb8`)

The 25-phase reliability specification's own final validation — see `10-v3-progress.md`'s "Reliability-Overhaul Pass" section for the full narrative, and this session's own final report for the exact final test count.

| Gate | Result |
|---|---|
| `flutter analyze` (project-wide, after every change in this pass) | **0 issues** at every incremental check; final full-repo run: 1 info-level lint (`avoid_print`, `test/manual/verify_real_device_import_fix_test.dart` — untracked, excluded from commits), zero issues in any tracked/committed file |
| `flutter test` (new/changed test files) | Import completeness (14 tests) + existing parser tests: 68/68. Offline readiness: 5/5. Template acceptance matrix (Phase 6/7/8/20/21): 45/45. Onboarding overlapping-call regression: 3/3 (new file, previously zero coverage existed for `OnboardingSetupController`; the initial "orphaned download" hypothesis was disproved by its own first test, corrected before landing — see D-M8-04). `activate()` verify-before-switch: existing tests updated + 1 new regression test, all passing |
| `flutter test` (full suite) | Final count recorded in this session's own final report — no existing test was deleted or weakened; two existing tests were strengthened (given a real on-disk file matching new verify-before-switch behavior) |
| Import completeness | `ResumeImportCompletenessReport` proves, on every real import, that every block the parser identified became either a structured entry or a flagged review item — never silently neither. See D-M8-01, `03-decisions.md` |
| Template acceptance matrix | 45/45 (8 datasets × 5 templates = 40 render combinations, plus 5 further distinguishability/content-completeness tests) — no crash, no empty output, valid `%PDF-` magic bytes, every template pairwise byte-distinguishable from every other (Phase 6), every source entry present in the pre-render content plan (Phase 8) |
| Model download reliability | Investigated a suspected onboarding-download race condition; the specific "orphaned download" mechanism was disproved by direct testing, but a real, narrower re-entrancy risk (overlapping calls to `downloadModels()`) was found and fixed — see D-M8-04 |
| Model activation integrity | Speech-to-text models now verified (file/hash) before becoming active; LLM/embedding models deliberately not (network-cost trade-off, disclosed as RV3-22) — see D-M8-05 |
| Offline readiness | New `OfflineReadinessService`/screen + a direct network audit confirming the only real network code anywhere in `lib/` is the two model-download paths — see D-M8-06 |
| Release build | Not re-run this pass at the time of writing this table — see this session's own final report for the actual APK build/inspection result |

**Explicitly not covered by this pass's gates** (see D-M8-07/D-M8-08, `03-decisions.md`): a new reference-matching 6th template, and Documents/folder-manager search/sort/multi-select/preview. Both reviewed and confirmed out of scope for this pass's remaining time, not silently skipped.

## Product-Quality Remediation Pass (post-`a1ac9ed`)

A second, independent specification (Parts A-L) explicitly instructing not to assume the prior pass's "all phases complete" report without re-verifying against the real generated APK/output. See `03-decisions.md`'s `D-M9-*` entries and `04-risk-register.md`'s `RV3-23`/`RV3-24` for the full per-item narrative.

| Gate | Result |
|---|---|
| A5: sub-project nesting | Migration v20 (additive, backward-compatible), parser/model/compiler/renderer/editor all updated, verified against the real Harshavardhan resume (SciLab/ByHeart/Crossword render as distinct nested sub-projects in the generated PDF, directly visually inspected) |
| B: template quality (real-data stress test) | 4/5 templates render cleanly with no orphaned headings, no clipping, no huge blank areas. Balanced Two-Column has a genuine, reproducible pagination defect (RV3-24) — root-caused as far as static analysis allows, disclosed rather than blindly patched without a reliable reproduction to verify a fix against |
| C: reference-matching template | Executive Summary-Led's Skills section now renders grouped by category (D-M9-02) — the smallest safe gap identified against the reference resume, without a 6th template |
| D: document manager | Real search + sort added (D-M9-03), operating on the same persisted rows every other part of the screen already reads. Thumbnail/preview and multi-select remain a disclosed, not-yet-built gap |
| E: multi-model management | 9 of 10 explicit requirements were already correctly implemented; 5 new regression tests close the 2 genuine, previously-unverified gaps (real end-to-end download resume, active-model-survives-restart) — see D-M9-04 |
| F: offline readiness | Found and fixed a real inaccuracy: `OfflineReadinessService`'s own network-usage detail text claimed network was used for "an optional update check" — no such feature has ever existed anywhere in `lib/`, confirmed by a direct repo-wide grep (no `http`/`dio`/Firebase/analytics package in `pubspec.yaml`; the only 2 real network-capable files anywhere in `lib/` remain `model_download_service.dart` and `connectivity_check.dart`, both scoped to model downloads only) |
| H: JD tailoring re-verification | Sub-project content (D-M9-01) made visible to JD matching/prioritization (read-only paths); AI-suggestion generation deliberately kept scoped to top-level bullets only (no write-back path for sub-projects) — see D-M9-06 |
| I: import completeness stress-testing | 5 previously-untested shapes (multi-role-same-company, sub-projects, zero-bullet entries, non-Indian international locations, mixed bullet markers) all already worked; found and fixed one real bug (a `"\|"`-joined header line redundantly flagged as unclassified after every segment was already extracted) — see D-M9-07 |
| J: template gallery/preview "shows blank" | Root-caused to a missing `PdfPreview` `onError` callback — Flutter's default `ErrorWidget` fallback strips its own message text in release builds, leaving a bare textless box. Fixed on both `ResumeTemplateDetailScreen` and `ResumePreviewScreen` — see D-M9-08 |
| K: release APK build + inspection | Built for real: `REAL_EXIT_CODE=0`, both ABI APKs produced at expected sizes (arm64-v8a 127.9MB, armeabi-v7a 110.4MB), zero LiteRT/tflite/bundled-model-weight traces, debug-keystore signing confirmed. Found one new, genuine, previously-unverified-per-ABI gap: the `armeabi-v7a` APK has zero llama.cpp native libraries at all (an upstream `llamadart` package constraint, not a project misconfiguration) — every LLM/embedding feature is unavailable on that ABI, though it degrades gracefully rather than crashing — see RV3-25 (`04-risk-register.md`) and D-M9-09 |

**Explicitly not re-run this pass at the time of writing this table:** full-repo `flutter analyze`/`flutter test` (batched per-directory instead — see this pass's own final report for the exact aggregate count and why: this environment's `flutter test`/`flutter analyze` crash with a Windows `DartWorker` thread/memory-exhaustion error when run as one monolithic invocation against the whole repo, reproduced twice; targeted, sequential per-directory runs are the reliable substitute used throughout this pass), and Part L's own remaining scope (final documentation sync, full-suite run, git checkpoint).

## Physical-Device Test Plan (Parts F1 and K)

**Not executed as of this document's own last update — no physical Android device or emulator is available in this implementation environment.** Every claim in this repository about airplane-mode/offline behavior, real download interruption/resume under OS backgrounding, and on-device build installation is **CODE VERIFIED** (unit/widget-tested against real local infrastructure — real SQLite, a real local loopback HTTP server, a real Hive box — never a live physical device) and explicitly **NOT** claimed as physical-device verified. This is the literal distinction Part F1/K's own instruction requires: "Code audit can prove absence of obvious network calls. It cannot replace physical-device validation." The steps below are the plan to close that gap the next time a physical Android device is available - each should be checked off individually, not assumed from the others passing.

1. Fresh install of the release APK on a physical Android device (not an emulator) with no prior app data.
2. Complete first-run onboarding; download the recommended models over a real Wi-Fi/cellular connection.
3. Kill the app (swipe away from recent apps, or force-stop via Settings) mid-download; reopen the app.
4. Confirm the download resumes from where it left off (not from 0%) — the `Range`-header/validator-sidecar mechanism this pass's own `model_download_service_test.dart` code-verifies end-to-end against a real local server, now under genuine OS process teardown rather than a simulated interruption.
5. Download a second, different model (e.g. an embedding model alongside the LLM) — confirm both track independent progress with no visible cross-contamination in the Model Manager UI, matching this pass's own `model_download_controller_test.dart` concurrency coverage.
6. Switch the active model in Model Manager; confirm the UI reflects the new active model immediately and a subsequent AI action (chat/tailoring) actually uses it.
7. Force-close and reopen the app; confirm the active model selected in step 6 is still shown as active (this pass's own `installed_models_controller_test.dart` restart-persistence test code-verifies the same claim against real persisted storage, not a live device).
8. Enable Airplane Mode.
9. Force-close and reopen the app while still in Airplane Mode.
10. Navigate through every major screen (Home, Documents, Resume Builder, Chat, Settings, Offline Readiness) — confirm no screen shows a network error, spinner-that-never-resolves, or crash.
11. Import an existing resume file (PDF/DOCX) while in Airplane Mode; confirm parsing completes and every section (Experience, sub-projects, Education, Skills, Projects, custom sections, links) appears correctly in the editor.
12. Generate/export a PDF for that resume, in Airplane Mode, for all 5 beta templates; confirm each opens correctly and matches its gallery preview.
13. Run a local transcription (record or import audio) in Airplane Mode; confirm it completes using the on-device Whisper model.
14. Run a local LLM action (chat, resume tailoring suggestion) in Airplane Mode; confirm it completes using the on-device model, with no network-error surfaced.
15. Run embeddings/retrieval (semantic search, JD matching) in Airplane Mode; confirm results return without error.
16. Open the Documents manager; confirm previously-imported documents are still listed, searchable, and sortable (this pass's own Part D additions), and that opening one still works.
17. Perform an offline full-text search across stored documents/meetings; confirm results return.
18. Use offline Chat (workspace/meeting/document-scoped) in Airplane Mode; confirm an answer is generated with no network dependency surfaced.
19. Open Settings and the Offline Readiness screen specifically; confirm it reports "ready" (all three required model kinds active) and that its stated claims match what was just observed in steps 8-18.
20. Disable Airplane Mode; confirm no functionality broke or behaves differently now that connectivity is back (the app should not have depended on the network reappearing).

**Do not mark any of the above as passed without actually performing it on a physical device.** A future pass that runs this plan should update this section directly with the date, device model/Android version, and pass/fail per step — not merely restate that the plan exists.
