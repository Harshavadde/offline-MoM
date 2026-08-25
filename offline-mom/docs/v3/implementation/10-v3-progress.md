# V3 Implementation Progress Dashboard

Single place to look for "where does V3 actually stand right now" — mirrors [docs/v2/implementation/10-v2-progress.md](../../v2/implementation/10-v2-progress.md)'s role. Every claim below is repository-verified this session (`git log`, `git show --stat`, direct file/code inspection, fresh `flutter test`/`flutter analyze` runs) — not inherited from any prior conversational report without re-checking.

**Legend:** ⬜ Not Started · 🔄 In Progress / implemented-uncommitted · ✅ Done (committed + tested + pushed to `origin/main`)

**Last updated:** 2026-08-22, **R-6 / R-7 / R-8 product-quality passes + R-10 Beginner Resume Flow** (below, new final section). `origin/main` remains at `3188c9b feat: establish beta baseline for resume builder` — every commit from `636eeb8` (Reliability-Overhaul Pass) through `9d0e63d` (R-9, Gradle memory fix) is local-only, not pushed, per standing "do not push unless explicitly told to" instruction. R-10 (Beginner Resume Flow) is implemented, tested, and analyzed clean but **deliberately left uncommitted**, per that feature's own explicit "DO NOT COMMIT" instruction — only this documentation-synchronization pass's own doc/comment changes are committed.

Everything from "Beta Validation Pass" through "Reliability-Overhaul Pass" (below) is prior-session history, preserved as written. The new final section, "Product-Quality Remediation Pass (Parts A-L)," is this pass's own record.

**Verification vocabulary used throughout this file and this pass's own docs (`03-decisions.md`, `04-risk-register.md`, `08-quality-gates.md`):**
- **AUTOMATED VERIFIED** — a `flutter test` assertion actually passed and is part of the tracked regression suite.
- **CODE VERIFIED** — confirmed by direct source/config/dependency-package inspection (grep, reading the actual installed package source, reading the actual build config), no test exists or one isn't practical.
- **VISUAL VERIFIED** — a real generated artifact (a rendered PDF, a built APK's contents) was directly inspected (read/viewed/`unzip -l`'d), not merely asserted by a test.
- **PHYSICAL-DEVICE VERIFIED** — observed running on a real Android device or emulator. **None of this pass's claims carry this tag** — no physical device or emulator is available in this implementation environment, disclosed consistently rather than assumed from the other three tiers passing.
- **PENDING** — not yet verified by any of the above; a disclosed, open gap.

---

## 🏁 BETA BASELINE — PRE-PHYSICAL-DEVICE VALIDATION (2026-08-11)

This is the repository checkpoint immediately before the first install onto a real Android phone. Everything in this box is **AUTOMATED VALIDATION** (static analysis, unit/widget tests, direct build/APK inspection) — none of it is **PHYSICAL DEVICE VALIDATION**, which has not started yet.

| Area | Status |
|---|---|
| Beta template catalog | **5 templates** selectable in the gallery UI (Classic, Modern Accent, Executive Summary-Led, Minimalist Monochrome, Balanced Two-Column) |
| Automated test suite | **1497/1497 passing**, 0 failures (superseded — see "Post-Beta-Baseline" section below for the current 1528/1528 count after this pass) |
| `flutter analyze` | **Clean — No issues found** |
| Release build | **Succeeds** — `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64` (the `--target-platform` flag is required; see D-M7-05 below for why the bare `--split-per-abi` invocation this row originally documented always exits 1) |
| arm64-v8a APK | `offlinemomai-22-arm64-v8a-release.apk` — **127.8 MB** |
| armeabi-v7a APK | `offlinemomai-22-armeabi-v7a-release.apk` — **110.3 MB** |
| APK signing | **Debug keystore** (no `android/key.properties`) — sideloading/testing only, not Play Store-ready |
| LiteRT-LM native runtime | **Removed** (`pubspec.yaml`'s `hooks.user_defines.llamadart.llamadart_native_runtimes: [llama_cpp]`) |
| llama.cpp native runtime | **Retained** — the only inference runtime now bundled |
| FFmpeg | **Retained**, unchanged |
| Model weights in APK | **Not bundled** — confirmed via direct APK content inspection (`unzip -l`), no `.gguf`/`.tflite`/`.onnx`/`.bin`/`.model` found |
| Model acquisition | Downloaded **after install**, unchanged first-run flow |
| Offline inference | **Preserved** — no AI inference code path makes a network call; `INTERNET` permission remains scoped to model download only |
| **Physical-device testing** | **NOT YET COMPLETED.** No Android device/emulator exists in this implementation environment. This checkpoint exists specifically so the next step can be: install the arm64-v8a APK above on a real phone and begin beta testing |

## Milestone snapshot

| Milestone | Status | Commit(s) |
|---|---|---|
| M0 — Data model & device foundation | ✅ COMPLETE | `dd4a03d` (impl), `0e47848` (docs) |
| M1 — Template engine | ✅ COMPLETE | `d67528a` |
| M2 — Deterministic tailoring depth | ✅ COMPLETE | `30bf491` |
| M3 — AI rewrite suggestions | ✅ COMPLETE | `2f92bba` |
| M4 — Import depth, suggestions-while-typing, beta template catalog, second model tier | ✅ COMPLETE | `7219ac5` |
| M5 — Beta hardening (privacy/PDF/AI-failure/RAM/ATS/widget-test/docs) | ✅ COMPLETE | recorded in [07-git-strategy.md](07-git-strategy.md) once pushed |

## PRD status

- `docs/v3/01-prd.md` exists, tracked, committed (`5a06f89`), pushed. **Unchanged throughout M4 and M5** — confirmed via `git diff -- docs/v3/01-prd.md` (no output) at the start of this pass. No implementation contradiction requiring a PRD change was found in Milestone 5.

---

## Milestones 0–3 — see prior sessions, unchanged this pass

Full detail for M0–M3 is preserved as it was written after Milestone 3 (implementation summaries, key files, known deviations, remaining limitations at that point) — nothing about M0–M3's own implementation changed during M4 or M5. Consult git history of this file for that detail if needed; this revision focuses on M4/M5, the two milestones this pass covers, plus the current overall snapshot below.

**Brief recap:** M0 laid the schema/device-detection foundation. M1 built the template rendering engine (archetypes × design tokens). M2 added additive semantic-embedding JD matching and deterministic content prioritization. M3 built the core AI tailoring loop — bounded per-entry suggestion generation, gated by an explicit `SuggestedEdit` accept/reject flow, with a flag-only fabrication guard.

---

## Milestone 4 — Import depth, suggestions-while-typing, beta template catalog, second model tier

**Purpose:** Close the PRD's remaining functional gaps (FR3-01, FR3-04, FR3-15, FR3-17) and reach a genuinely usable, visually credible beta product — reprioritized mid-milestone from "~20 templates" to **10 high-quality templates**, an explicit product-owner decision (D-M4-04) that quality/distinctiveness matters more than count.

**Implementation summary:**
- `ResumeWritingHeuristics` (Tier 1, deterministic, zero-cost) + `BulletSuggestionField` (Tier 2, debounced LLM-backed) — writing-quality suggestions while typing, on the block editor screens (FR3-17).
- Per-entry-editable import review — the resume/JD import review screen no longer only allows editing the title; each parsed entry is directly correctable before it's committed (FR3-01).
- 6 additional archetypes built (Executive Summary-Led, Minimalist Monochrome, Entry-Level/Student, Government/Public-Sector Dense, Creative Visual, plus the two-column-right variant), bringing the catalog to 10 total — every archetype re-verified structurally distinct from every other (never density/color alone, D-M4-01), each carrying one curated token preset rather than a warm/cool pair (D-M4-04, the beta-scope reduction from the PRD's "~20" language).
- Second LLM tier added to `ModelCatalog` as an explicit, declinable opt-in, offered once before first entering the Resume feature (FR3-15) — the baseline model remains fully functional and is the default if declined (FR3-16, now meaningfully testable since a real second tier exists to decline).
- Header-centering fix (D-M4-03) and unified title/date-row layout (D-M4-02) applied across all archetypes as quality-bar fixes, found via manual PDF inspection against the Enhance CV reference.

**Key files:** `lib/services/resume/resume_writing_heuristics.dart`, `lib/features/career/resume/presentation/widgets/bullet_suggestion_field.dart`, `lib/services/resume/template/archetypes/*.dart` (6 new), `lib/services/resume/template/resume_template_catalog.dart`, model-upgrade-prompt screen and `ModelCatalog` second-tier entry, import review screen per-entry editing.

**Tests:** **1407/1407 full-suite**, `flutter analyze` 0 issues (both at commit time).

**Known deviations:** the catalog ships **10 templates (10 archetypes × 1 curated preset each)**, not the PRD's literal "~20" (10 archetypes × 2 presets) — an explicit, disclosed beta-scope decision (D-M4-04), not a silent shortfall. The dual-preset mechanism itself (`ResumeTokenPresetIds`) was kept, not deleted, so a future milestone could reintroduce it without an architecture change.

**Remaining limitations at M4's close (carried into M5, see below):** no genuine human visual review against the Enhance CV bar had occurred (only AI-assisted spot-checks); `DeviceCapabilityService` still had zero consumers in the tailoring path (RV3-04); PDF metadata had not been checked (RV3-07); the ATS round-trip test still verified against `ResumeContentPlan`, not real native extraction (RV3-13); privacy/local-data behavior had not been audited beyond design intent; widget-test coverage remained at 2 of ~15 screens.

---

## Milestone 5 — Beta hardening

**Purpose:** Make the existing V3 implementation safe and credible for beta testing — no new features, no template-count growth, no PRD changes. Directly targets the specific gaps M4's own closing notes and the risk register left open.

**Implementation summary, per phase:**

- **Privacy/local-data audit (Phase 2):** real code-level audit, not a superficial "grep for http" pass. Confirmed zero network calls anywhere in the resume/JD code paths; confirmed `AppLogger` (`lib/core/logging/app_logger.dart`) wraps only `dart:developer.log()` (local DevTools sink, never persisted/transmitted) and has zero usage anywhere under `lib/features/career/`, `lib/services/resume/`, `lib/services/career/`; confirmed no crash-reporting/analytics SDK exists in the app at all; traced every user-facing exception-display path, finding and triaging one benign case (`BlockInUseException.toString()` embeds resume *titles*, the user's own chosen labels, in an on-device-only SnackBar — not resume body content, not transmitted). No fixes were needed; findings are documented, not assumed.
- **PDF metadata (Phase 3, RV3-07 → RESOLVED, D-M5-02):** both source-inspected `package:pdf` 3.11.3's `Document`/`PdfInfo` construction logic (an `/Info` dictionary is only written if title/author/creator/subject/keywords/producer is explicitly passed — `ResumeTemplateRenderer` passes none) and empirically probed raw rendered PDF bytes for all 10 catalog templates. Zero identifying metadata found; no code change needed. A permanent regression test (`test/services/resume/resume_pdf_metadata_test.dart`, 10 cases) now guards this going forward.
- **AI/model failure hardening (Phase 4):** inspected every AI path (semantic matching, suggestion generation, model loading/unloading, second-tier decline) against the PRD's 10 specific safety properties. All 10 were already true by construction from M2/M3/M4's existing architecture (graceful `try`/`catch` degradation at every model-touching boundary, the `SuggestedEdit` proposal gate, revalidation before Accept) — verification-only, no code changes needed.
- **RAM/device-capability sequencing (Phase 5, RV3-04 → MITIGATED, D-M5-01):** `GenerateResumeSuggestionsUseCase.call()` now calls a new private `_releaseEmbeddingModelIfLowTier()` between its internal embedding-backed analysis pass and its LLM-backed generation loop, unloading the embedding model via `ModelLifecycleManager.unmanagedUnload()` on any tier other than `highRamDevice`. Reuses `DeviceCapabilityService`/`ModelLifecycleManager` exactly as D-11 specified — no new concurrency architecture. 5 dedicated tests added.
- **Real ATS/PDF validation (Phase 6, RV3-13/RV3-05, D-M5-03):** since the native `PdfParser` platform channel genuinely cannot run under `flutter test`, two real round-trip tests were added to the existing `integration_test/app_test.dart` (device/emulator-only) file instead of faking the result: full-catalog heading-survival, and two-column sidebar/right reading-order verification, both through the actual native extraction pipeline. Written and statically verified (`flutter analyze` clean); execution requires a real device, not available in this environment — explicitly disclosed as outstanding, not claimed complete.
- **Widget-test backfill (Phase 7, RV3-15, D-M5-04):** `resume_template_gallery_screen_test.dart` added (3 tests) — the screen judged highest-risk among the uncovered set (Milestone 4's most heavily rewritten screen, zero prior coverage). Full backfill of every remaining uncovered screen was judged disproportionate to beta-readiness risk and explicitly not attempted, per the PRD's own "prioritize beta-critical behavior over percentage" instruction.
- **Full regression (Phase 8):** run once after all above changes.
- **Documentation sync (Phase 10):** all 12 `docs/v3/implementation/*.md` files updated for M4 and M5 together (M4-specific updates had not yet been written into several of these files prior to this pass).

**Key files:** `lib/features/career/analysis/generate_resume_suggestions_use_case.dart`, `lib/providers/app_providers.dart`, `test/services/resume/resume_pdf_metadata_test.dart` (new), `test/features/career/resume/presentation/screens/resume_template_gallery_screen_test.dart` (new), `test/features/career/analysis/generate_resume_suggestions_use_case_test.dart`, `integration_test/app_test.dart`.

**Tests:** **1425/1425 full-suite passing** (`flutter test`), `flutter analyze` — **0 issues**. (The two new `integration_test/app_test.dart` cases are additional to this count — that file is not part of the default `flutter test` run and requires a device/emulator.)

**Known deviations:** none from the PRD — no template count increase, no PRD text change, no scope beyond beta hardening.

**Remaining limitations — explicitly still open after Milestone 5 (see [04-risk-register.md](04-risk-register.md) for full detail):**
- No real Android device/emulator is available in this implementation environment. This leaves several items **implemented and unit/statically verified, but not device-verified**: RAM-tier sequencing under actual memory pressure (RV3-04/RV3-12), the two new ATS native-extraction integration tests (RV3-13/RV3-05), and RAM-tier detection itself (RV3-03, unchanged since M0).
- **No genuine human visual review against the Enhance CV bar has ever been performed** — only AI-assisted spot-checks of sample renders (M4) have occurred. This remains explicitly open (RV3-10).
- Widget-test coverage is improved but not exhaustive — 9 of ~15 Resume/Career screens still have none (RV3-15, narrowed not closed).
- The fabrication guard remains lexical-only and flag-only, by design (RV3-14, ACCEPTED) — not a defect, a disclosed limitation.
- A per-entry generation failure remains silent in the UI (RV3-16, unchanged, low severity).

---

## Beta Validation Pass (post-Milestone 5)

A separate validation activity against the finished Milestone 5 build — **not a new milestone, no implementation code changed as a result of this pass** (per its own explicit instructions: validate whether V3 is genuinely good enough for beta users, don't keep developing indefinitely). Full checklist/comparison/classification lives in the conversation that produced this pass; this section records what was actually done and what it found, for the same reason every other section of this file does.

**Method, honestly scoped:** no Android device or emulator is available in this environment (confirmed via `flutter devices`: only Windows desktop/Chrome/Edge), and no real on-device LLM/embedding model can run here either. Rather than skip real-content validation entirely, three realistic personas (fresher/student, mid-level DevOps engineer, senior/lead engineer — real names, real Indian-market contact formatting, realistic multi-entry work histories, realistic JDs) were built and pushed through the **real** production pipeline end-to-end: real Sqflite-backed repositories, the real `ResumeCompilerService`, the real `ResumeJdAnalyzer` (including its semantic tier), the real `PrioritizeResumeContentUseCase`, the real `GenerateResumeSuggestionsUseCase`, the real `AcceptSuggestedEditUseCase`/`RejectSuggestedEditUseCase`, and the real `ResumeTemplateRenderer`. Only the two genuinely model-backed steps (semantic embedding, LLM suggestion text) used `FakeEmbeddingEngine`/`FakeLlmEngine` test doubles, the same convention the permanent test suite already uses — this is disclosed as a real, structural limitation (see below), not glossed over. All 10 beta templates were rendered against this realistic content and every one was **visually inspected directly** (not just structurally tested) by reading the actual generated PDFs.

**What this pass confirmed working well:**
- The full tailoring pipeline runs correctly end-to-end with zero exceptions across all three personas: import/build → deterministic+semantic match → prioritize → generate → accept/reject → recompile → export.
- Deterministic matching, prioritization, accept, and reject all behaved exactly as documented — rejected suggestions never touched stored content; the one accepted suggestion in each of two personas correctly replaced only its own field's text and nothing else.
- The one real fabrication check exercised (persona 1's accepted suggestion) was correctly assessed as safe (no new numbers/proper nouns introduced) — consistent with, not a replacement for, `SuggestionFabricationGuard`'s existing 17 dedicated unit tests.
- All 10 templates rendered without error, without clipped/garbled/missing content, and are genuinely visually distinct from each other — confirmed by direct inspection, not inferred from structural specs alone. Archetypes whose whole differentiator is content ordering did reorder correctly with real content (Entry-Level/Student: Education before Experience; Executive Summary-Led: Skills before Experience).
- No crash, no data loss, and no silent AI-modification-without-consent occurred anywhere across any persona.

**What this pass found — see [04-risk-register.md](04-risk-register.md) for full detail (RV3-17, RV3-18, and updated RV3-10):**
- **RV3-17 (new, BETA IMPROVEMENT):** both two-column archetypes wrap the header contact-info line awkwardly mid-phone-number in the narrow sidebar column — purely cosmetic, confirmed by direct visual inspection.
- **RV3-18 (new, BETA IMPROVEMENT):** when a persona's JD-relevant content lives mostly in skill/certification tokens rather than embedded bullet prose (a realistic pattern for senior/lead resumes), `GenerateResumeSuggestionsUseCase` can produce zero suggestions even though several partial matches were shown on the JD Analysis screen — the review screen's empty state renders correctly but doesn't explain why. Root cause is D-M3-02's documented bounded-scope design, not a bug.
- **RV3-10 (updated, still OPEN):** the previously-known large-bottom-whitespace observation was independently re-confirmed with real content across multiple archetypes — still cosmetic, still not a substitute for genuine human review against the Enhance CV bar, which remains not performed.
- **Not exercised this pass:** a live case of `SuggestionFabricationGuard` actually flagging a fabricated suggestion in the realistic-persona run — one persona's JD/resume pairing happened to produce zero eligible suggestions at all (see RV3-18), so a deliberately-fabricating fake LLM response prepared for that persona was never reached. The guard's flagging behavior itself remains verified by its own 17 dedicated unit tests (Milestone 3), unaffected by this gap.

**Zero BLOCKER-classified findings.** Every finding above is BETA IMPROVEMENT (worth fixing, doesn't block beta) or reconfirms an already-disclosed POST-BETA item (human visual review, real-device validation). Nothing found in this pass changes the Milestone 5 beta-readiness verdict below — it strengthens the evidence behind it.

---

## Visual-Quality Redesign Pass (post-beta-validation)

Product-owner feedback after reviewing the beta validation pass's own rendered PDFs, plus user-supplied Enhance CV reference resumes/screenshots, judged the templates "technically correct but visually not good enough for a real user-facing beta." This pass is a template-presentation-only redesign in direct response — **explicitly not a new milestone**, no change to the AI tailoring pipeline, import flow, fabrication guard, or offline architecture, and no change to the 10-archetype count.

**Method:** studied the reference resumes for their underlying design principles (typography hierarchy, header treatment, whitespace control, section-heading treatment, alignment, bullet structure), compared them against the existing 10 archetypes, made targeted code-level changes to the shared layout primitives and per-archetype token wiring (never per-archetype duplicated widget code), then re-rendered all 10 templates against the same 3 realistic personas from the beta validation pass plus a 4th long-career-history persona (added specifically to inspect page-2/page-break behavior) and visually inspected every rendered PDF again.

**What changed, all in `lib/services/resume/template/`:**
- **Justified bullet text** (`pw.TextAlign.justify` in `buildEntryBlock`) — bullets now read as typeset paragraphs with clean edges on both sides, not ragged-right text.
- **Two-tone entry titles** (D-M5-07) — "Role" renders bold/ink, "- Company" renders in a softer tone, applied uniformly via a new `_buildEntryTitle` helper in `entry_block.dart`; falls back to plain bold text when there's no `" - "` to split on.
- **Refined bullet markers** — small solid squares in a soft tone, replacing the default large black circles, with slightly increased line spacing for breathing room within multi-line bullets.
- **A new `SectionHeadingStyle.centeredFlanked`** (D-M5-06) — heading text centered between two rules that fill the remaining row width via `pw.Expanded`, reproducing the reference resumes' own centered/rule-flanked heading motif as a layout technique. Applied to Executive Summary-Led and Government Dense (both already the catalog's "formal" identities); the other 8 archetypes keep their existing `ruleBelow`/`label`/`ruleAbove` treatments for continued differentiation.
- **A header-separator rule** (`ResumeDesignTokens.headerDivider`) for the archetypes that previously had no visual break between the header and the first section (Classic, Compact Technical, Minimalist Monochrome, Entry-Level/Student) — archetypes that already draw their own bespoke accent bar there (Modern Accent, Executive Summary-Led, Creative Visual) were left alone to avoid a doubled-up rule.
- **Fixed RV3-17** (D-M5-05) — `ResumeDesignTokens.headerContactStacked` stacks the sidebar header's contact items one per line instead of a single `" | "`-joined line that didn't fit the ~140pt column at realistic content widths.
- **A moderate, considered rhythm increase** (D-M5-08) — every density profile's `sectionGap`/`entryGap`/`lineGap` increased roughly 15-25%, preserving each profile's relative density ranking (Compact Technical/Government Dense remain the tightest, Minimalist remains the most generous), directly targeting the "large accidental-looking empty area at the bottom of the page" finding.
- Executive Summary-Led's own hand-rolled accent bar was updated to render centered (`pw.Center`), matching its now-centered header — previously left-aligned, which would have looked visibly misaligned under a centered name/contact block.

**Visual findings after the redesign, from direct PDF inspection (not test output) of all 10 templates plus a page-2 check:**
- RV3-17 confirmed fixed by direct comparison against the same realistic persona that originally reproduced it — contact items now stack cleanly, no mid-phone-number wrapping.
- The long-career-history page-break check (6 experience entries × 4 bullets, both Classic Single-Column and Two-Column Sidebar) found **no orphaned headings, no bullets splitting awkwardly across the page boundary, and no sidebar content bleeding onto page 2** — `pw.MultiPage`'s and `pw.Partitions`'s existing pagination behavior continues to hold correctly with the new spacing/typography.
- Executive Summary-Led and Government Dense's new centered/flanked heading treatment reads as a genuinely distinct, more formal "letterhead" identity, directly recognizable as reproducing the reference's own signature move without being a pixel copy.
- Bottom-of-page whitespace on short/light resumes is **reduced but not eliminated** — an inherent property of fixed-page, content-driven layout with no fabricated filler content, disclosed as a remaining limitation, not claimed solved (see D-M5-08).
- No new visual defects were introduced: no clipped text, no broken alignment, no overlapping elements, no missing content, across any of the 10 templates or the long-history page-2 render.

**Quality gates:** `flutter analyze` clean (project-wide). Full `flutter test` suite result recorded in [08-quality-gates.md](08-quality-gates.md)/the session's own final report — no permanent test assertions needed updating, since every existing test in this area asserts on structural properties (renders without throwing, correct `ResumeContentPlan` ordering, correct `pw.Partitions` composition) that this pass's purely typographic/spacing changes don't touch.

**Still explicitly not done:** a genuine human visual review against the Enhance CV bar. This pass is a second, more targeted round of AI-assisted visual inspection directly informed by the user's own reference material — a stronger signal than the prior rounds, but still not a substitute for one, and RV3-10 remains OPEN on that basis.

---

## Reference-Driven Redesign Pass (5 real Enhance CV resumes)

The user supplied 5 real Enhance CV resume outputs as the explicit **primary visual reference** (not vague inspiration) and asked for a second redesign pass mapping concrete, observed reference principles onto the same 10 archetypes. Explicitly scoped, same as the prior pass: template presentation only, no AI/import/fabrication-guard/offline changes, no template-count change.

**What was learned from the references (most visible in the one full-detail reference, a senior Business Development Director resume; the other 4 were lower-resolution thumbnails, so confidence is highest for the principles below and correspondingly lower for anything not listed):**
- Role name and employer name are visually distinguished — role carries more color/weight emphasis, employer is subordinate.
- A thin dashed rule separates consecutive entries within one section, distinct from the heavier solid rule used at section boundaries.
- Typography itself (the actual typeface) reads as considered and modern — not a generic default.
- A two-column "wide-left / narrow-right-rail" layout exists in the fullest reference, with Summary and Key Achievements callouts in the right rail — noted, but not built this pass (see below).
- Skills-as-proficiency-bars and language-proficiency dots appear in one other reference — noted as a real technique observed, but not reusable without a data-model change to track proficiency levels, which is out of this pass's scope and would risk inventing a signal the app doesn't actually collect.

**What changed, all in `lib/services/resume/template/` (plus `assets/fonts/`, `pubspec.yaml`):**
- **Embedded the Inter typeface** (D-M5-09/D-M5-10) — investigated custom font embedding properly rather than declaring it impossible: confirmed this development environment has real network access (a separate question from the shipped app's own offline runtime requirement), located Inter's official release (SIL Open Font License 1.1, fully permissive for bundling/embedding), verified the license text directly, and embedded Regular/Bold/Italic static weights (~1.25MB total) as bundled Flutter assets loaded via `rootBundle` + `pw.Font.ttf()` + `pw.ThemeData.withFont()` on `ResumeTemplateRenderer`'s `pw.Document`. This is the single highest-leverage typography change available and was the biggest visible difference in the before/after PDF inspection.
- **Role-color hierarchy** (D-M5-12) — for the 3 archetypes that already opt into an accent identity (Modern Accent, Executive Summary-Led, Creative Visual), the role/degree segment of an entry title now renders in the archetype's accent color, matching the reference's own role-emphasis convention; the other 7 neutral archetypes are unchanged (still bold ink) to avoid contradicting their own restrained identity.
- **Dashed inter-entry dividers** (D-M5-13) — a new `buildDashedDivider` primitive (`layout/divider.dart`, via `package:pdf`'s built-in `BorderStyle.dashed`), wired into 5 mid-density archetypes (Classic, Modern Accent, Executive Summary-Led, Entry-Level/Student, Minimalist Monochrome); deliberately left off the tightest 2 archetypes, both two-column archetypes, and Creative Visual, each for a stated reason (see D-M5-13).

**What was considered and explicitly not built, with reasons (D-M5-14, D-M5-15):**
- A Summary/objective section and an Achievements-callout section — neither exists in the current `Resume`/`ResumeSnapshot` content model (`Resume` has no summary field; `Resume.achievements` exists in the schema but is never populated by any UI or read by `ResumeCompilerService`). Building either would mean new content-collection work, out of this pass's "template rendering only" scope, and rendering them with no real content would mean either an empty section or fabricated placeholder text — both rejected.
- A third two-column "wide-left/narrow-right-rail" layout shape — a materially larger structural change than "smallest clean architectural change" allows, and would either require a new archetype (explicitly prohibited) or restructuring an existing one's already-established identity.

**Visual findings after this pass, from direct PDF inspection of all 10 templates plus the long-history page-2 re-check:**
- The Inter font renders cleanly and legibly across every archetype and density profile — no glyph/encoding issues, no clipped text.
- Role-colored titles are clearly visible and read as a deliberate hierarchy signal, not decoration, in all 3 archetypes they were applied to.
- Dashed dividers render correctly between entries, visually lighter than section-boundary rules, in all 5 archetypes they were applied to; correctly absent from the other 5.
- The long-career-history page-break re-check (same 6-entry/4-bullet persona as the prior pass) confirms the font swap introduced no wrapping/clipping/orphaning regression — entries and dashed dividers both continue to flow correctly across the page 1→2 boundary.
- Combined with the prior pass's changes (justified text, two-tone titles, centered-flanked headings, rhythm increase), the templates now read as substantially closer to a considered, typeset commercial document — this is a genuine, cumulative, visually-verified improvement, not merely additional structural changes.

**Quality gates:** `flutter analyze` clean (project-wide, re-confirmed after this pass). Full `flutter test` suite result and the exact count are in this session's own final report. 5 test files required a one-line fix (`TestWidgetsFlutterBinding.ensureInitialized()`) after the font change introduced `rootBundle` asset loading, which a plain `test()` block doesn't initialize on its own — discovered by actually running the suite, not assumed (D-M5-11).

**Still explicitly not done:** a genuine human visual review against the Enhance CV bar remains the one gate this pass cannot close on its own — see RV3-10, [04-risk-register.md](04-risk-register.md).

---

## Product Redesign Pass (structural entry-header architecture)

The user rejected both prior passes as "supporting details, not the redesign itself" and explicitly authorized architectural refactoring of the template/layout code (not the content model, not AI/import/business logic) if the visual result required it. This pass ran the required Design Audit (A–F) before writing any code, then made the one structural change the audit identified as load-bearing: every entry in the prior two passes still rendered as a single flattened string (`"$role - $company"`) re-split by the layout layer, which is why two-tone titles and column-narrow layouts kept producing awkward wraps no amount of token tuning could fix.

**Design audit summary (delivered in full in-chat before implementation, per the user's required process):**
- **(A) Strongest reference patterns:** structural separation of role/company/date/location as independent visual elements (not a joined string), a two-tone title (role emphasized, company subordinate), thin dashed inter-entry rules distinct from section rules, and a genuinely asymmetric two-column composition (not a mirrored sidebar).
- **(B) Biggest current problems:** `ResumeContentLine.text` was the *only* thing the entry-title renderer had to work with — role/company were already split apart in `ResumeSnapshot`'s model but got rejoined into one string before the layout layer ever saw them, so any layout wanting independent control over role vs. company vs. date was re-parsing a string it shouldn't have needed to.
- **(C) Blocking architectural assumption:** `buildEntryBlock` accepted `title`/`meta` as opaque strings. Fixing this required a real content-plan change, not a token.
- **(D) Proposed final 10 identities:** kept all 10 existing archetypes; identified Two-Column Right as the one archetype not yet carrying a genuinely distinguishing structure (see D-M5-18 below).
- **(E) Change classification:** structural (content-plan + layout primitive rewrite), not cosmetic — matches what the user asked for.
- **(F) Reference-to-template mapping:** the stacked/two-tone entry-header pattern maps onto Executive Summary-Led, Government Dense, and the restructured Balanced Two-Column (Two-Column Right) — the three archetypes whose own identity already implies more vertical room per entry (executive presentation, dense-but-organized government format, asymmetric column layout).

**What changed, all in `lib/services/resume/template/`:**
- **Structured entry data** (D-M5-16) — `ResumeContentLine` gained `primaryText`/`secondaryText` fields carrying the real, already-separate role/company/degree/institution/date/location values from `ResumeSnapshot`; the flattened `.text` string is kept as-is for backward compatibility (nothing downstream that reads `.text` directly changed behavior).
- **`EntryHeaderStyle.inline` / `.stacked` token** (D-M5-17) — `inline` (unchanged default: title row + right-aligned date, one line) stays the shape for 7 archetypes; `stacked` (role, then company, then date/location, each its own line) is new and applied to Executive Summary-Led, Government Dense, and Balanced Two-Column, the three archetypes whose density profile and audience genuinely benefit from the extra vertical structure.
- **Two-Column Right renamed "Balanced Two-Column," rail restructured** (D-M5-18) — the design audit's own finding was that Two-Column Right was functionally identical to Two-Column Sidebar except mirrored, a real redundancy by the user's own stated bar. Rather than remove the archetype (risking orphaned `templateId` references in any already-saved resume), its column-*content* assignment was restructured: Education and Certifications now join Skills in the rail, leaving the wide main column to Experience and Projects only — a genuinely asymmetric wide-prose/narrow-list composition, not a mirror.
- **Stacked mode applied archetype-wide to Balanced Two-Column** (D-M5-19) — direct visual inspection of the rail in `inline` mode surfaced a real wrapping defect: entry titles like "B.Tech - Vellore Institute of Technology" orphaned a trailing "B.Tech -" on its own line at the ~140pt rail width. This was the deciding evidence for `stacked`, not a hypothetical — documented explicitly as visual-inspection-driven, not inferred.
- **Why the other 9 archetypes were not renamed to match the user's example identity list** (D-M5-20) — the user's list (Professional Classic, Modern Corporate, etc.) was explicitly given as an example set, not a mandate; the existing 10 identities already cover the same design space and renaming them without a corresponding structural change would be cosmetic churn against the user's own "not another typography/spacing pass" instruction.

**Self-caught defect during implementation:** the first attempt at wiring `entryHeaderStyle: stacked` landed on Two-Column Sidebar instead of Two-Column Right/Balanced Two-Column — both archetypes share byte-identical token-call text, and the `Edit` anchor uniquely matched the wrong one. Caught by re-rendering and visually inspecting the PDF (Two-Column Right showed no change), confirmed via direct `grep`/`sed` inspection, and fixed by reverting the erroneous edit and re-anchoring on Two-Column Right's unique `displayName` line. Verified afterward via `grep -n "entryHeaderStyle"` (3 occurrences, each spot-checked) and a second visual re-render confirming both archetypes now render correctly (Sidebar unaffected/inline, Balanced Two-Column stacked and no longer wrapping).

**Visual findings from this pass's full 10-archetype sweep** (4 personas — fresher, mid-level DevOps, senior lead, long-career — rendered via a temporary, non-committed test harness, PDFs opened and inspected directly, not just "rendered successfully"):
- All 10 archetypes render cleanly with no wrapping, clipping, or hierarchy defects, including the 7 archetypes that received no direct token change this pass (confirming the shared `entry_block.dart`/`content_line_renderer.dart` rewrite introduced no regression).
- Balanced Two-Column's rail now wraps cleanly at every persona's data, including the long-career persona's denser certification/education entries — the defect that motivated `stacked` is gone.
- Executive Summary-Led and Government Dense's stacked entries read as a deliberate, more formal presentation, consistent with those archetypes' own identity, not merely "more spaced out."
- Long-career page-break checks (6-entry/4-bullet persona) for Balanced Two-Column and Government Dense confirm no orphaned headings or awkward wraps across the page 1→2 boundary.

**Quality gates:** `flutter analyze` clean (project-wide, re-confirmed: "No issues found!"). Targeted resume test suite: 296/296 passing after fixing a stale ATS round-trip test assumption (it wasn't threading the new `sidebarAlsoTakesEducationAndCertifications` flag, so it kept "passing" while silently no longer reflecting Balanced Two-Column's real composition) and `layout_primitives_test.dart`'s `buildEntryBlock` call signatures. Full-suite result for this pass: see this session's own final report.

**Still explicitly not done:** the same human-visual-review gate as the prior two passes (RV3-10) — see [04-risk-register.md](04-risk-register.md).

---

## Product Visual-Audit Pass (color anchors, role tagline, icons, title-emphasis direction)

The product owner rejected all three prior passes as still producing "programmatically generated documents" and required a formal, ranked design audit against 4 attached Enhance CV references *before* any code change — this pass's audit is what actually drove the work below (D-M5-21 through D-M5-27, [03-decisions.md](03-decisions.md)).

**Audit finding:** the real gap was never typography or entry structure (both already addressed in prior passes) — it was the complete absence of any bold color anchor, any icon, or any header content beyond name/contact. Every one of the 10 archetypes was plain black text on a white page; all 4 references use a colored role banner, a full-width color band, or icon-prefixed contact rows as their strongest visual signal.

**What changed, all in `lib/services/resume/template/` (plus `lib/models/resume_snapshot.dart`, `lib/services/resume/resume_compiler_service.dart`):**
- **Role tagline** (D-M5-21) — `Resume.targetRole` (real, user-typed text that already existed since M0 for JD-matching, never rendered) now flows through `ResumeSnapshotProfile.roleTagline` → a new `ResumeContentLineKind.roleTagline` → the header. Zero fabrication risk: it is the user's own words, and the header omits the line entirely (not a placeholder) when unset.
- **`HeaderStyle` token** (D-M5-22/D-M5-23) — `pill` (role tagline in a filled rounded accent badge under the name) for Executive Summary-Led; `colorBand` (the whole header on a solid accent fill, light text) for Modern Accent and Creative Visual, each a different accent hue. The remaining 7 archetypes keep `plain`. The color band spans the content width, not true edge-to-edge page bleed — a disclosed, deliberate trade-off against a much larger page-margin-architecture change (D-M5-23).
- **Hand-drawn vector contact icons** (D-M5-24/D-M5-25, new `layout/contact_icons.dart`) — phone/email/location/link glyphs built from `pw.CustomPaint` primitives, investigated as a real alternative to an icon font (which would need bundling a second, much larger asset) or Unicode dingbats (which have no glyph in the bundled Inter font and would render as missing-glyph boxes). Applied to the two rail/sidebar archetypes (Two-Column Sidebar, Balanced Two-Column) only, where a narrow stacked contact block benefits most.
- **`EntryTitleEmphasis` token** (D-M5-26) — role-vs-company bold-weight direction is now a per-archetype choice (`role`/`company`) instead of a hard-coded universal rule, since the two full-detail Enhance CV references studied disagree with each other on this. Classic and Government Dense now bold the company (institutional identity); the other 8 keep the existing role-forward treatment.
- **Explicitly not built** (D-M5-27): a user photo (no storage/upload UI/data-model field exists — a genuine future capability, not silently added), an Achievements callout component (the schema column still has no editor UI populating it), and any proficiency chart (this product collects no skill-proficiency data — building one would mean fabricating a signal never actually captured).

**Self-caught defect during implementation:** Creative Visual's pre-existing "accent bar above and below the header" decoration became redundant once its header became a solid color-band fill — caught during the very first render (a visibly doubled-up accent element), fixed by removing the now-redundant bars (the same fix independently applied to Modern Accent's own pre-existing thin accent rule).

**Visual findings from this pass's inspection** (4 personas rendered via a temporary, non-committed test harness — 2 with `targetRole` set, 2 without, to exercise both the tagline and its graceful omission — 13 PDFs across all 10 archetypes, opened and inspected directly):
- Modern Accent and Creative Visual's color-band headers are a genuine, visible step change — the single most impactful visual difference of any pass so far, and the first thing in this catalog that reads as "designed" rather than "styled text."
- Executive Summary-Led's pill badge reads as a deliberate, considered accent under the centered name, close in spirit to the studied reference's own role-banner technique.
- Contact icons render correctly oriented (phone as a diagonal capsule, email as an envelope with a flap line, location as a downward-pointing map pin, link as two overlapping rings) at both stacked-sidebar and single-line widths.
- Company-forward emphasis (Classic, Government Dense) reads as a deliberate institutional convention, not an inconsistency, once seen next to the still-role-forward archetypes.
- The role tagline wraps to 2-3 lines in the ~140pt sidebar/rail width for a long value — real text, never clipped, but visually heavier there than in a full-width header; disclosed as a minor, non-blocking density note.
- Long-career page-break re-checks (Modern Accent's color-band header across a 2-page document, Government Dense's stacked+company-forward entries across 2 pages) confirm no clipping, orphaning, or awkward wraps introduced by this pass.
- All 7 archetypes with no direct token change this pass (Classic already covered above, Compact Technical, Two-Column Sidebar's own unaffected inline mode, Minimalist Monochrome, Entry-Level/Student) re-render identically to before, confirming the shared `header_block.dart`/`entry_block.dart` rewrite introduced no regression.

**Quality gates:** `flutter analyze` clean (project-wide, re-confirmed: "No issues found!"). Targeted resume test suite: 296/296 passing. Full-suite result: see this session's own final report.

**Still explicitly not done:** the same human-visual-review gate as every prior pass (RV3-10) — see [04-risk-register.md](04-risk-register.md). Photo support and an Achievements component remain the two highest-value candidates for a future content-model pass, not silently dropped.

---

## Product Composition-Audit Pass (recency-weighted density, column ratio, honest architecture assessment)

The product owner rejected the visual-audit pass with the strongest framing yet: the renderer "behaves like a DATA-TO-PDF renderer rather than a PROFESSIONAL RESUME COMPOSITION ENGINE." The required workflow: stop coding, audit the architecture, explicitly evaluate whether a page/region-allocation layer is needed between `resume_content_plan` and the PDF primitives, implement only what the audit justifies, and report a failed visual-quality gate honestly rather than overclaim.

**Audit finding, agreed with the product owner:** `content_line_renderer.dart` walks a flat line list and emits every entry with identical visual weight regardless of age or position - a long career doesn't get composed, it gets stacked until it runs out of entries. The two-column sidebar's 140pt width was a bare space-allocation number, not a considered ratio.

**On the proposed layered architecture:** investigated directly against what `package:pdf` 3.11.3 actually provides. `pw.MultiPage` does automatic flow pagination; `pw.Partitions`/`pw.Partition` is the only column-balancing primitive; neither exposes a pre-layout height query. A true page-aware allocator (deciding before rendering which section lands on which page, or rebalancing columns by predicted height) would require building an entirely new dry-run measurement pass - real, large, high-risk infrastructure with no precedent in this codebase. This pass did not build that, and did not fake a version of it that doesn't actually measure anything. This is disclosed as an open architectural question, not resolved (D-M5-28, [03-decisions.md](03-decisions.md)).

**What was actually built, the one real and safely achievable answer to "does this need entry density modes":**
- **Recency-weighted Experience bullet density** (D-M5-29) - `buildResumeContentPlan` gained `capOlderExperienceBullets` (default `true`). When a resume has 4+ Experience entries, the 2 most-recent (ranked by parsed end date, `Present`/null ranking highest - never by list position, since entry order follows the user's own drag-reorder `sortOrder`) keep every bullet the user wrote; every older entry is capped to its first 2. Never hides an entry, never rewrites or invents a bullet. Government Dense opts out (`capOlderExperienceBullets: false`), matching its own stated "complete, exhaustive chronological record" identity.
- **Two-column ratio fix** (D-M5-30) - the sidebar `pw.Partition` widened from a fixed 140pt (~26% of printable width) to 168pt (~31%), fixing a real, previously-found 3-line role-tagline wrap.
- **Investigated and declined:** a rail background/visual-identity treatment - `pw.Partition` has no decoration parameter, and its child must remain a bare `SpanningWidget` to paginate safely (a real prior bug this exact constraint already caused and fixed once). Building a custom decorated `SpanningWidget` was judged out of this pass's safe scope, not silently skipped (D-M5-31).
- **No further header decoration added** (D-M5-32), per explicit instruction to stop iterating there until the audit proved it necessary - it didn't.

**Visual findings** (re-rendered and directly inspected: a realistic 6-role long-career persona across Classic, Government Dense, and Balanced Two-Column; the DevOps persona across Modern Accent and both two-column archetypes) — including catching and fixing a bug in the test harness itself (the "current/Present" role was initially assigned to the oldest-starting entry rather than the most-recent-starting one, which technically exercised the ranking-by-date logic correctly but produced an unrealistic persona; corrected before drawing conclusions):
- The recency cap is clearly visible and reads as a deliberate authorial choice: the 2 most recent roles (Program Manager, Senior Program Director) carry full detail, the 4 older roles condense to 2 bullets each - a real, visible hierarchy signal a flat stack never had.
- The two-column ratio fix measurably improves wrap quality: the same role tagline that wrapped to 3 lines at 140pt now wraps to 2 at 168pt; skills chips lay out 3-per-row instead of 2.
- Government Dense correctly shows every bullet on every entry, confirmed the opt-out works.
- Short/medium resumes (2 experience entries) are correctly unaffected by the cap (only activates at 4+).

**Honest self-assessment, not a "closer"/"considered" claim:** the two changes above are real and visually confirmed, but they do not close the larger gap the product owner named. The renderer is still fundamentally a sequential-flow composition with no true page-aware allocation - that remains an open architectural question requiring either new measurement infrastructure or an explicit decision that automatic-flow pagination is acceptable for this product's scope. This pass narrows the density/ratio axis specifically; it does not claim to have built a composition engine.

**Quality gates:** `flutter analyze` clean (project-wide: "No issues found!"). 6 new dedicated unit tests for the recency-cap behavior (ranking by date not position, cap threshold, opt-out, never-hides-an-entry), plus 1 existing test updated for the new 168pt ratio. Full-suite result: see this session's own final report.

---

## Current Repository State

- **Branch/remote:** `main`, tracking `origin/main`.
- **Local `HEAD` / `origin/main`:** `b25dd60 feat(v3): complete milestone 5 beta hardening` — pushed and verified matching (`git ls-remote origin refs/heads/main`).
- **Working tree:** the Milestone 5 commit (`b25dd60`) plus uncommitted changes from four post-M5 passes: the beta validation pass (doc files only), the visual-quality redesign pass (`lib/services/resume/template/` + docs), the reference-driven redesign pass (font asset + `pubspec.yaml` + `lib/services/resume/template/` + 5 test files + docs), and the product redesign pass (`lib/services/resume/template/` content-plan + layout primitives + catalog, 2 test files, docs). All four passes used a temporary, non-permanent test file (`test/_beta_validation_test.dart`) to exercise the pipeline/renderer against realistic data and render templates for visual inspection — deleted after each pass's findings were captured, never committed. No file outside `docs/v3/implementation/*.md`, `lib/services/resume/template/`, `assets/fonts/`, `pubspec.yaml`, and the renderer/layout-touching test files was changed by any of the four passes.
- **New bundled asset:** `assets/fonts/Inter-{Regular,Bold,Italic}.ttf` + `Inter-LICENSE.txt` (SIL OFL 1.1), registered in `pubspec.yaml`. No new package dependency — uses `package:pdf`'s existing `Font.ttf`/`ThemeData.withFont` API and Flutter's existing `rootBundle`.
- **Full test suite:** 1425/1425 passing as of the Milestone 5 commit; re-run after each subsequent pass — see this session's own final report for the confirmed count after the product redesign pass specifically.
- **`flutter analyze`:** 0 issues, re-confirmed after every pass including this one (project-wide).
- **`docs/v3/01-prd.md`:** untouched throughout M4, M5, and all four post-M5 passes.
- **`docs/v2/`:** untouched.
- **Template catalog:** still 10 templates (beta scope, D-M4-04) — unchanged in count by any pass, per explicit instruction not to grow template count; only internal typography/spacing/heading/entry-header structure changed, plus Two-Column Right's column-content composition and display name (D-M5-18).
- **V3 overall:** **technically beta-ready**, not the same claim as production-ready — see [09-definition-of-done.md](09-definition-of-done.md)'s criterion-by-criterion table for the precise distinction. Every PRD §24 criterion that is structurally verifiable in this environment is met; the remainder require a real Android device or a human visual reviewer, both explicitly disclosed as outstanding rather than silently assumed. The post-Milestone-5 beta validation pass found zero blockers and two new, non-blocking cosmetic/UX findings (RV3-17, RV3-18); the three subsequent redesign passes fixed RV3-17 and made real, visually-confirmed, cumulative structural progress on RV3-10, each pass's own visual re-inspection finding no new defect (and the product redesign pass's own inspection catching and fixing one real defect before declaring the pass complete).

---

## Beta Product Validation → Physical-Mobile-First Validation → Final Product-Build Phase

Several sessions after the redesign passes above, the product-owner direction shifted from template visual polish (already judged sufficient) to **product validation**: is the fixed 5-template beta actually reliable, does it preserve real users' data end-to-end, and can it produce a real, installable release APK. **The beta template catalog was reduced from 10 to exactly 5** (Balanced Two-Column, Classic, Modern Accent, Executive Summary-Led, Minimalist Monochrome) as an explicit product decision at the start of this arc — the other 5 archetypes still exist in code (`ResumeTemplateCatalog.all`) and still render correctly for any resume that already selected one, but the gallery/beta UI only ever exposes the 5, and no template #6 was added at any point across this whole arc, per repeated explicit instruction.

### Product Validation / My Profile
- Added `Resume.isProfile` (migration v19) — a single additive boolean flag on the existing `Resume` row, not a new entity, reusing the already-correctly-scoped `ResumeBlockRepository` for "My Profile" (the reusable career source of truth). `CreateResumeFromProfileUseCase` derives an independent, job-specific resume from the profile's live composition, sharing (not duplicating) library blocks via the existing `ResumeBlockRef` join.
- `CannotTailorProfileException` added at both real mutation points (`GenerateResumeSuggestionsUseCase`, `AcceptSuggestedEditUseCase`) — the profile itself can never be JD-tailored; a derived resume must be created first. Verified end-to-end, including the case where a derived resume shares the *exact same* underlying library block as the profile: accepting a tailored suggestion on the derived resume only ever writes that resume's own `ResumeBlockRef.overrideJson` row — the profile's own ref row, and the shared library block itself, are architecturally untouched (proven by a dedicated end-to-end test, not just asserted).
- Fixed a real data-loss bug found via *mandatory visual PDF inspection* (not caught by any existing test): a custom section's standalone bullets (no `entryTitle`) were silently discarded by `content_line_renderer.dart`'s `flushEntry()` guard. Fixed and regression-tested.

### Beta Product Validation (real template gallery)
- Replaced the gallery's decorative, hand-drawn preview mock with real PDF-rendered thumbnails, using the exact same `ResumeTemplateRenderer` the final export uses — reusing the existing `PdfPageRenderingService` rasterization abstraction (the same one every PDF Tool already uses), not a second preview implementation.
- Added `ResumeTemplateDetailScreen` (tap a template → larger real preview via `PdfPreview` → "Use This Template" → back to Editor). Regression-tested that the preview renders the *selected* template, never silently falling back to Classic (a previously-shipped bug this session explicitly guarded against).
- Full field-level import-preservation test suite added (8 scenarios: normal, 8-role long-career, 12 section types, unusual section names, 10+ projects, 15-20 skills, missing/unusual dates, unusual section order) tracing SOURCE → parser → real Sqflite DB → `ResumeCompilerService` → rendered PDF.

### Physical-Mobile-First Validation (see [03-decisions.md](03-decisions.md) D-M6-01 through D-M6-09 for full reasoning)
- **Pagination:** fixed the real orphaned-section-heading defect (found on all 5 beta templates via direct visual inspection) using `pw.Inseparable`, package:pdf's own "keep together" primitive — two earlier attempts (`pw.Column`, `pw.Container`) were tried and empirically proven to have zero effect before landing on the correct fix. The previously-reported "Balanced Two-Column two-column desync" finding was **retracted** after an isolated probe disproved it.
- **Import:** added real "City, ST" location detection (previously no producer logic existed at all) and auto-persisted Summary/Objective as a real "Summary" custom section (previously silently lost on import unless the user manually copied it in — it only ever reached `unclassifiedText`, which `confirmImport` never persists).
- **Mobile UX:** consolidated the Resume Editor AppBar from 6 action icons down to 2 + one overflow menu (was crowding out the resume title on a ~360dp phone); fixed a real back-stack-destroying navigation bug (`context.go` → two `context.pop()` calls) in the template confirm screen.
- **Reliability:** added error-feedback (`SnackBar`) to every resume-editor block action that previously discarded a failed operation silently or near-silently — most notably `_pickExisting`'s `onPicked` callback, which was typed as `void Function` so its actually-async `attachBlock()` call had its returned `Future` silently discarded rather than awaited, across 4 of 6 section types' "add existing" flow.
- **Investigated, no change needed:** the fabrication guard's accept-time behavior (already structurally unbypassable — the warning is unconditionally shown on the only screen that can trigger acceptance) and Title-Case custom-section headings (confirmed not a silent-drop bug, a disclosed UX gap deferred rather than risked under time pressure, given a prior version of this exact heuristic was reverted for a real false-positive regression).

### Final Product-Build + Physical-Device Beta Validation Phase (this update)
- **Release build fixed.** `flutter build apk --release --split-per-abi` was failing outright before this phase (`ndk.abiFilters` conflict, a genuine pre-existing bug unrelated to any change in this whole arc) — see D-M6-10/D-M6-11. A first fix attempt (explicitly declaring the app's own `ndk.abiFilters`) was tried, empirically proven to have zero effect via a real rebuild, and reverted rather than left as a misleading comment.
- **The actual, sufficient fix:** `pubspec.yaml` now scopes `llamadart`'s native-assets build hook to `llama_cpp` only (`hooks.user_defines.llamadart.llamadart_native_runtimes: [llama_cpp]`), confirmed correct against the installed `llamadart-0.8.17` package's own source (not the `--dart-define` an earlier session incorrectly assumed) and against the fact that every catalog model is GGUF/whisper.cpp `ggml`, never LiteRT-LM. This resolved the Gradle conflict as a side effect (Android no longer requests an `android-x64`/x86_64 native-assets build target once LiteRT-LM is out of the picture) and reduced the arm64-v8a release APK from ~174MB to **127.8MB** (a genuine ~46MB/26% reduction, from removing real, verified-unused native code — not from removing FFmpeg, llama.cpp, Whisper, or any model-download capability, all of which remain and were directly confirmed present in the built APK's own file listing).
- **APK produced and inspected:** `build/app/outputs/apk/release/offlinemomai-22-arm64-v8a-release.apk` (127.8MB) and `offlinemomai-22-armeabi-v7a-release.apk` (110.3MB) — both built successfully, both directly inspected (`unzip -l`) for LiteRT-LM/`.tflite`/`.onnx` traces (none found) and accidentally-bundled model weights (none found — models remain download-after-install only, unchanged). Signed with the debug keystore (no `android/key.properties` present in this environment) — **suitable for sideloading/local testing only, not Play Store distribution.**
- **Offline architecture reconfirmed unaffected:** the `INTERNET` permission remains scoped to first-time model downloads only (already documented in `AndroidManifest.xml` itself); no inference code path anywhere in `lib/services/ai/` makes a network call. This phase's only changes were `pubspec.yaml` (native-assets scoping) and a reverted-then-clean `android/app/build.gradle.kts` — no Dart-level AI/inference behavior changed.

---

## Post-Beta-Baseline: Real-Device Findings Remediation

The BETA BASELINE commit (`3188c9b`) was installed on a real Android phone with the user's actual resume. Physical-device testing surfaced **catastrophic data loss** the entire prior automated-validation history (including the "Beta Product Validation" pass above, which used synthetic personas, not the user's own file) had never caught: missing name, an entire missing Work Experience section, an entire missing Education section, a Summary shredded into disconnected fragments, and scrambled section order. This pass fixed the actual root causes in the parser (not surface symptoms), then continued through 9 further phases the user specified end-to-end, without stopping between phases per explicit instruction.

### Phase 1–2: Real-resume data-loss root-cause fixes (`lib/services/resume/resume_import_parser.dart`)

All of the following were real, independently-reproducible parser bugs, found by parsing the user's actual resume text and diffing the result against the source PDF — not inferred from synthetic test data:

- **Name detection** only tested the first preamble line and didn't strip a trailing parenthetical (e.g. a pronoun or credential in parentheses); rewritten to scan every preamble line and strip `(...)` before re-testing.
- **Date-range regex** had a structural bug where a broader alternative could swallow text belonging to a narrower intended capture group (the "June 2024" vs "2024" pattern) — restructured into 3 named capture groups (start year / present-or-current text / end year) so month-name prefixes never leak into the wrong group.
- **Experience/Education block parsing** (`_parseExperience`/`_parseEducation`) previously required a title+date combination to appear in one specific line shape; rewritten around a new `_findDateRangeInBlock`/`_BlockDateMatch` scan that finds the date anywhere in the block and splits combined title+date lines by match position — this alone was the direct cause of the entire missing Experience/Education sections, since a combined "Software Engineer | Jan 2024 - Present | Hyderabad, Telangana" line didn't match any of the parser's prior expected shapes and silently dropped the whole entry.
- **Summary fragmentation**: bullet-style summaries were being split into disconnected fragments instead of preserved as bullets, and prose summaries weren't being rejoined into one paragraph; fixed via a new `_joinWrappedContinuationLines` helper that only joins a non-bullet line onto the previous item when that item was itself opened by a real bullet marker and doesn't already end in terminal punctuation — also applied to Experience/Education bullet extraction and custom-section entries for the same class of bug.
- **Location parsing (explicit known gap #1, "Hyderabad, Telangana" not importing):** no Indian-location producer logic existed at all. Added `_indianStatesAndUnionTerritories` (33 states/UTs) + `_commonResumeCountryNames`, a new `_locationNamedRegionPattern`, and `_detectLocation` now also splits each preamble line on `|` and tests each segment — explicitly **not** US-only, per instruction.
- **Duplicate/misattributed links**: `_extractLinks` was scanning the *entire* document (including a project's own "GitHub: url" line) instead of just the preamble, double-counting a GitHub link into both the header and, separately, as a stray Experience bullet; scoped to preamble-only (mirroring the existing phone-number-detection convention) and the project-bullet exclusion changed from exact-match to `.contains(...)` so "GitHub: url"-labeled lines are also correctly excluded from bullets.
- **Sub-project structural nesting (explicit known gap #2, SciLab/ByHeart/Crossword rendering as plain lines):** investigated and **deliberately deferred**, not fixed — a proper fix requires a real data-model change (a new nested-entry field/table, parser support, renderer support, and editor UI), judged too large and too risky to attempt safely within this pass's remaining scope. Documented here as an investigated-and-declined decision, not a silent gap.

**Result:** re-parsed against the user's real resume text (`test/manual/verify_real_device_import_fix_test.dart`, a throwaway diagnostic script, not part of the tracked suite): name, full Work Experience, full Education, and a coherent Summary all now import correctly and render correctly across all 5 templates.

### Phase 3: Genuine template differentiation (not just color/font)

- **Modern Accent**: skills now render as chips (`skillsAsChips: true`, newly scoped to only fire on the actual Skills section via a new `ResumeContentLine.isSkillsList` field — the naive first attempt at this leaked chip styling onto the Summary paragraph too, caught and fixed before landing); Projects now render before Education (`projectsBeforeEducation: true`).
- **Executive Summary-Led**: Summary now renders as a visually emphasized callout (left accent border, italic, slightly larger body size — `ResumeContentLine.emphasized`).
- Both changes flow through the existing shared, token-driven pipeline (`resume_content_plan_builder.dart` → `content_line_renderer.dart`) — no per-archetype duplicated rendering logic, no 6th template added, per explicit instruction.

### Phase 4: Content-aware layout stress testing

40 combinations (8 synthetic datasets — short/3-job/6-job/10+-project/15-20-skill/multi-custom-section/long-bullet/everything-present — × 5 templates) all render without throwing, no hardcoded bullet/project count cap introduced. Found and fixed a real, reproducible crash in the process (below).

### Balanced Two-Column pagination crash (found via stress testing, fixed)

`pw.Partitions` (package:pdf's two-column primitive) threw `PdfTooBigPageException: This widget created more than 20 pages` when a long Summary paragraph landed in the narrow sidebar column. Two compounding fixes were required — the first alone was insufficient:
1. A char-threshold safety net in `content_line_renderer.dart` (`maxInseparableGroupChars = 1400`) so `pw.Inseparable` (which has a hardcoded `canSpan=false` and hard-crashes if its wrapped content exceeds one page on its own) never wraps a group large enough to risk that.
2. The actual root cause: `resume_content_plan_builder.dart`'s Summary-rendering block now always targets `ResumeContentColumn.main`, never the sidebar/header column, for every archetype — a long paragraph should never be routed to a ~168pt rail column at all, regardless of pagination-safety measures downstream.

### Phase 5–6: Re-verification + Indian location parsing (see Phase 1–2 above for the location fix itself; folded in there since it was one root-cause fix, not a separate pass)

Re-rendered the user's real resume across all 5 templates after the Phase 3 template changes and confirmed no regression.

### Phase 7: Template gallery renders the user's actual resume, not sample data

`templateSamplePdfBytesProvider` (rendered a fixed, fake `buildSampleResumeSnapshot`) replaced with `templateResumePdfBytesProvider`, keyed by `(resumeId, templateId)`, calling the same `ResumeEditorController.compileSnapshot()` the Editor's own Preview/Export actions already use — the gallery can never again drift from what a real export actually produces. Fixed a real async-timing race in the process: the provider's first build can run before the Editor's own `_load()` finishes, and a one-shot `ref.read(...).compileSnapshot()` call never retried once it hit that race, permanently stranding the preview in an error state (caught by a real widget-test failure, fixed with a short poll-until-ready loop).

### Phase 8: JD tailoring revalidated after the parser/template changes

All 46 relevant tests (fabrication guard, profile-protection guard, `SuggestedEdit` accept/reject gate) pass unchanged — confirmed the parser's "SKILLS SUMMARY" heading-recognition fix directly benefits JD matching, since `resume_jd_analyzer.dart` iterates individual `snapshot.skills` entries.

### Phase 9: Model download resumability (Whisper onboarding download)

**Root cause** (found via direct source investigation, not assumed): the app has two entirely separate download implementations. `HttpModelDownloadService` (used by the post-onboarding Model Manager screen) was already correctly resumable — real `Range`-header resume, `ETag`/`Last-Modified` validator checking, never deletes a valid partial on a recoverable failure. `WhisperSpeechToTextEngine._downloadModelFile` (used exclusively by first-time onboarding) was a second, independently hand-rolled `HttpClient` loop that (a) never sent a `Range` header at all, so any retry re-fetched the whole file from byte 0, and (b) unconditionally deleted its `.part` file in its `catch` block on *any* failure, including a transient stall or the OS backgrounding/suspending the app — this is the exact, confirmed cause of the user's reported bug ("started the download, backgrounded the app, returned later, the download started from the beginning").

**Fix:** `_downloadModelFile` rewritten to delegate to `ModelDownloadService.download()` (the same resumable primitive the Model Manager already uses) instead of its own broken HTTP loop — `ensureModelDownloaded`'s public signature gained an injectable `ModelDownloadService? downloadService` parameter (defaults to a real `HttpModelDownloadService`, matching `ModelDownloadController`'s existing convention). Diagnostic `debugPrint` logging (never gated behind `kDebugMode`, since a beta APK is still a release build) was added to `HttpModelDownloadService.download()` itself, printing the exact facts requested for beta-testing diagnosis: initial request/existing-partial-bytes, the `Range` header sent, the HTTP status/`Content-Range`/decision (resume vs. fresh), and completion facts — visible via `flutter logs`/Logcat on a real device.

**Tests added** (`test/services/ai/whisper_speech_to_text_engine_test.dart`, using `FakeModelDownloadService` + a `_FakePathProviderPlatform`, mirroring `model_download_controller_test.dart`'s established pattern): delegation reaches the service with the correct URL/destination; an already-downloaded model is never re-downloaded; `WhisperModel.none` never touches the network; and — the core resumability claim — an interrupted download leaves a resumable `.part` file behind (`hasPartialDownload` true, no destination file written) rather than deleting it. All 4 pass, alongside the pre-existing `HttpModelDownloadService` loopback-server tests.

**Explicitly disclosed limitation, not glossed over:** this fix is verified at the code/unit-test level only. **Physical Android background/resume behavior has not been verified on a real device in this environment** — the diagnostic logging above exists specifically so that verification can happen during real beta testing, not as a substitute for it. `AppSettings.allowBackgroundDownloads` remains unchanged at its deliberate `false` default (requires a persistent Android notification, a real UX trade-off the user should opt into explicitly, not this pass's concern).

### Phase 10: Release APK build — a second, previously-undetected build bug found and fixed

Rebuilding the release APK after all of the above surfaced a **new, previously-unknown bug distinct from the `ndk.abiFilters`/LiteRT-LM issue already fixed and documented above (D-M6-10/D-M6-11).** `flutter build apk --release --split-per-abi`, run with no explicit `--target-platform`, defaults to targeting **3** Android ABIs (`android-arm`, `android-arm64`, `android-x64`) — but `android/app/build.gradle.kts`'s `splits.abi.include(...)` deliberately narrows Gradle's own output to only **2** (`arm64-v8a`, `armeabi-v7a`, per the earlier, still-valid decision to drop the emulator-only x86_64 and obsolete armeabi-v7a-adjacent... — specifically, x86_64 was dropped as a real-phone-irrelevant desktop/emulator architecture). This mismatch means Flutter's own tool-side post-build verification (`gradle.dart`'s `listApkPaths`) always looks for a third, non-existent `app-x86_64-release.apk`, and — even though both real ABI APKs build and copy successfully, printing two genuine "√ Built ..." lines — the overall `flutter build apk` command **always exits with code 1** and prints `Gradle build failed to produce an .apk file`.

This had evidently gone undetected through every prior pass in this project's history that "confirmed" a successful APK build (including the Final Product-Build Phase entry directly above this section) — every one of those checks apparently relied on the printed "√ Built" lines and/or the files existing on disk, never on the command's actual exit code, which a piped/tailed invocation silently masks. This pass caught it specifically by checking the real exit code directly (`echo $?` after a non-piped invocation) — see D-M7-05.

**Fix (D-M7-05):** pass `--target-platform android-arm,android-arm64` explicitly, matching Gradle's own 2-ABI split. Confirmed with a real, unmasked exit-code check: `REAL_EXIT_CODE=0`. Both APKs rebuilt cleanly at their expected sizes (arm64-v8a 127.8MB, armeabi-v7a 110.3MB, matching the Final-Product-Build-Phase measurement above, confirming this pass introduced no size regression). Native library composition re-confirmed via direct `unzip -l`: `libllama.so`/`libllama-common.so`/`libggml*.so` (llama.cpp), `libwhisper.so` (Whisper), `libavcodec.so`/`libavformat.so`/etc. (FFmpeg) all present; zero `litert`-matching entries in either APK; zero `.gguf`/`.ggml`/`.bin`/`.task` model-weight files bundled.

**Documentation/scripting implication:** any future `flutter build apk --release --split-per-abi` invocation for this project **must** include `--target-platform android-arm,android-arm64`, or it will report a false failure despite producing valid APKs.

### Phase 11: Final validation

- `flutter analyze` (project-wide): **0 issues** — the only 2 lint infos found anywhere are `info`-level (`prefer_const_constructors`, `avoid_print`) inside `test/manual/*.dart`, this pass's own throwaway diagnostic scripts, not part of the tracked suite and not committed.
- `flutter test` (full suite): **1528/1528 passing**, run once after all of Phases 1–9's changes landed together (not per-phase), confirming no cross-phase regression.
- Release build: verified with a genuinely unmasked exit code (`REAL_EXIT_CODE=0`) after the D-M7-05 fix above — not inferred from log text alone.

**Known limitations explicitly carried forward, not silently dropped:**
- Sub-project structural nesting (SciLab/ByHeart/Crossword-style entries within one Experience/Project block) still renders as plain lines, not structurally distinct sub-entries — investigated, a proper fix requires a real data-model change, deliberately deferred (Phase 1–2 above).
- Physical Android-backgrounding download-resume behavior is code/unit-test verified only, not device-verified (Phase 9 above) — diagnostic logging is in place specifically to enable that verification during real beta testing.
- Every pre-existing limitation carried forward from the BETA BASELINE checkpoint (no real device/emulator in this environment for RAM-tier/ATS-native-extraction/download-resumability *device* verification; no genuine human visual review against the Enhance CV bar performed; debug-keystore signing only) remains unchanged and still open — this pass did not close any of those, only the real-device data-loss and download-resumability findings a physical install specifically surfaced.
- **No physical Android device or emulator is available in this implementation environment at any point across this entire arc.** Everything above is automated/static/build-level verification; nothing has been installed on or run on a real phone. This is the one gate every report in this arc has consistently and explicitly disclosed rather than silently assumed passed.

---

## Reliability-Overhaul Pass (post-`636eeb8`)

A 25-phase specification asking whether the beta implementation is "genuinely usable and reliable," not just passing its own prior checkpoints. Per its own explicit instruction, this section reports real findings and honest scope limits, not a claim that all 25 phases received full, equal-depth treatment - several are large enough to be their own multi-day efforts and are explicitly marked NOT DONE below rather than rushed.

### Phase 1: Import completeness validation mechanism (new)

Added `ResumeImportCompletenessReport`/`SectionCompleteness` (`lib/services/resume/resume_import_completeness.dart`), attached to every `ParsedResumeDraft` as `.completeness`. Built from the exact same block-counting `ResumeImportParser` already does internally while parsing (`_splitIntoBlocks`, the same skill-token dedup loop, the same custom-section-content check) - never a second, independently-guessed count that could drift from what the parser actually did. Reports Source/Imported/Missing per category (Experience, Education, Projects, Certifications, Skills, Custom sections, Summary, Links), with `missingCount` defined as "accounted for by neither a structured entry nor a flagged review item" - an invariant the parser's own control flow already guarantees (every block takes exactly one of those two paths), so this report *proves* that invariant on every real import rather than merely assuming it. `toReportString()` renders the exact "Source: / Imported: / Missing: 0" shape requested.

14 new tests (`test/services/resume/resume_import_completeness_test.dart`) cover 1/2/4+ experiences (5-role dataset), multi-project entries, custom sections, reordered sections (Education before Experience), a resume missing optional sections, wrapped bullets, links found in multiple places, an Indian location, mixed date formats, an empty document, and the report's string rendering - every one asserts `isComplete == true`.

### Phase 2: Expanded link detection and structural promotion

`_urlPattern` extended to recognize bare (no `http(s)://`/`www.`) Stack Overflow, LeetCode, Medium, HackerRank, Behance, and Dribbble URLs alongside the existing GitHub/GitLab/LinkedIn/Twitter set, each correctly labeled (`_labelForUrl`). New `_promoteLinksFoundElsewhere`: scans every custom-section entry and every unclassified line (deliberately **not** Experience/Education bullets, where an inline URL is usually incidental reference content, not a standalone profile link) for a URL not already captured as a profile/project/certification link, and promotes it into the same structural `ResumeLink` list every other profile link uses - a link inside a dedicated "LINKS"/"PORTFOLIO" custom section (or a labeled line like "Stack Overflow: stackoverflow.com/users/123" under an unrelated heading) is now stored structurally, not left as un-rendered plain text. Covered by the completeness tests above (a links test asserting all 4 sources - header LinkedIn/GitHub, a custom "LINKS" section's Stack Overflow/Portfolio entries - are promoted and labeled correctly).

### Phase 6/7/8/20/21: Template acceptance matrix, distinguishability, and content completeness (new permanent suite)

`test/services/resume/template/resume_acceptance_matrix_test.dart` (45 tests) promotes the prior pass's throwaway `test/manual/stress_test_datasets_test.dart` script into the permanent regression suite and extends it with the verification that script never had:
- **Phase 21 (acceptance matrix):** 8 datasets (short, 3-job, 6-job, 10+ project, 15-20 skill, 5-custom-section, very-long-bullet, and a 4-experience "everything present" kitchen-sink) × all 5 enabled templates = 40 combinations, each asserted to render a non-empty PDF starting with the real `%PDF-` magic bytes (a genuine, platform-channel-free PDF-validity signal) — plus 5 further distinguishability/content-completeness tests below, 45 total in the file.
- **Phase 6 (output must match selection):** all 5 templates rendering the same resume data are asserted **pairwise byte-different** - an accidental fallback to Classic (or any other template silently rendering identically to another) would fail this test immediately, not just "look wrong" on manual inspection.
- **Phase 8 (content completeness):** for the 6-experience and "everything present" datasets, every experience company/role, every education institution, every project name, and every custom-section heading is asserted present in the pre-render `ResumeContentPlan`'s line text - the same disclosed-limitation approach `ResumeContentPlan`'s own doc comment already establishes (real native PDF text extraction needs `read_pdf_text`'s platform channel and cannot run under `flutter test`; this verifies through the layer that actually determines final PDF content instead, which is what the existing ATS round-trip tests already do for section-heading order).
- **Phase 20 (4+ experiences):** the 6-role and 4-role datasets explicitly assert `hasLength(6)`/`greaterThanOrEqualTo(4)` before checking every single entry survives - never stopping at one or two entries.

All 45 tests pass.

### Phase 11: Model download bar - investigated, found and fixed a narrower real bug than first assumed, and corrected a mistaken premise along the way

Direct code review of `OnboardingSetupController.downloadModels()` (the first-run, multi-model concurrent download screen) found no unguarded null/division bug in any progress-rendering widget (`model_setup_screen.dart`, `model_details_screen.dart` - both already correctly null-check `fraction` before formatting it).

**A mistaken initial hypothesis, corrected by the test written to prove it:** the first pass through this code assumed `Future.wait([...])` completes - moving the method into its `catch` block - the instant *any one* of the concurrently-downloading models fails, leaving the *others* "orphaned" and still writing state afterward. **This is wrong, and the regression test written to demonstrate it proved that directly**, not by re-reading documentation: Dart's `Future.wait` defaults to `eagerError: false`, so it does not settle - and `OnboardingSetupState` does not become `Failed` - until *every* concurrent download has finished, success or failure. The first test written against the "orphan" hypothesis hung until its gated fake download was manually released, which is exactly what disproved the hypothesis. This is now the corrected, empirically-verified behavior documented directly in the test suite (`test/features/onboarding/onboarding_setup_controller_test.dart`).

**The real, narrower bug:** `downloadModels()` has no re-entrancy guard, and `_sttFractions`/`_llmFraction` are shared instance state. Nothing stops the method from being called a second time while a first call is still in flight (a fast double-tap on "Download & Continue" before Riverpod rebuilds the button away, or a caller-side bug elsewhere) - if that happens, the *first* call's eventual settlement (whenever its own downloads finish) would overwrite whatever the *second*, already-finished call left behind, since both write to the same `state` field.

**Fix:** a generation counter (`_generation`) plus an `_currentAttemptEnded` flag, checked via `_isCurrentAttempt()` before every `state =` write inside every progress callback - a stale call's late state write, from either scenario, is now a guaranteed no-op once a newer call has started. The fix itself required no change once the premise was corrected - the same guard protects the real (narrower) scenario as the originally-assumed one. Also fixed a related, smaller gap found along the way: the Whisper side of this same method previously always constructed a fresh real `HttpModelDownloadService()` rather than reading the app's shared `modelDownloadServiceProvider` (the same provider `ModelDownloadController` already uses) - now unified, which is also what made this bug testable at all.

3 new tests (`test/features/onboarding/onboarding_setup_controller_test.dart`, previously a completely uncovered file - zero prior tests existed for `OnboardingSetupController`): the normal success path; `Future.wait`'s real "waits for everyone" semantics (state stays `Downloading` while any download is still pending, even after another has already failed internally - the test that disproved the original "orphan" hypothesis above); and the actual regression this pass's fix protects against - a second, overlapping call to `downloadModels()` finishing successfully is never corrupted by a first, still-in-flight call's late settlement.

### Phase 13/14/17: Model activation now verifies before switching (Whisper), documented scope limit (LLM/embedding)

Found `InstalledModelsController.activate()` switched the active model on nothing but its DB row existing - a row whose file had since been deleted or corrupted outside the app could become "active" with nothing ever confirming it still loads, directly contradicting Phase 14's "the active model must always point to a verified READY model." Fixed for speech-to-text models (the only kind whose verification is fast and local - file-exists + size + hash check, no network): `activate()` now calls the same `ModelDownloadController.verify()` the manual "Verify" button already uses, before switching, and returns `false` (never throws) if it fails - callers (Model Details' Activate button, onboarding's profession-setup flow, the resume-editor model-upgrade dialog) all now surface a visible error rather than silently switching to (or silently failing to switch to) an unverified model.

**Deliberately not extended to LLM/embedding models** - a real, disclosed trade-off found while implementing this: `ModelDownloadController.verify()` for those two kinds re-triggers `llamadart`'s own cache validation via a real `ensureModelReady()` call, which can mean genuine network I/O. Unconditionally running that on every switch would make switching silently turn into "wait for a network round-trip", contradicting this app's own documented "switching is instant, not a fresh download" promise - and, confirmed empirically while fixing the existing test suite, would have made `flutter test` itself attempt a real multi-gigabyte network download on every `activate()` call in any test exercising it. Logged as RV3-22 below rather than silently left unfixed.

2 tests fixed (an existing Whisper-activate test needed a real on-disk file once verification was added, matching how a genuinely-installed model would actually look) plus 1 new regression test (`activate()` refuses to switch and returns `false` when the file is missing).

### Phase 15/16: Offline Readiness screen + network audit (new)

New `OfflineReadinessService`/`OfflineReadinessReport` (`lib/services/offline/offline_readiness_service.dart`) - checks whether an active, installed LLM/embedding/speech-to-text model exists (via `InstalledModelRepository.getActiveForKind`, the same source of truth the AI Model Manager itself reads) plus three static, network-audit-backed claims (local database, on-device inference, no network required for inference/search/PDF generation). New `OfflineReadinessScreen` (Settings → Offline Readiness) renders this as the requested "OFFLINE READY"/"OFFLINE NOT READY" checklist with a "Download required model" CTA when incomplete.

**Network audit (Phase 16), performed directly, not assumed:** confirmed via `pubspec.yaml` inspection that this app has no `http`/`dio` package dependency and no Firebase/analytics/crash-reporting SDK of any kind. The only real network-capable code anywhere in `lib/` is `HttpModelDownloadService` (`dart:io HttpClient`, used for Whisper downloads) and `llamadart`'s own internal downloader (used for LLM/embedding downloads) - both exclusively for one-time model downloads, never called from any transcription/summarization/resume-parsing/resume-generation/document-search/PDF-generation code path. A pre-existing, narrower utility (`hasInternetConnection()`) is used only as a pre-flight check before the profession-setup onboarding download flow, not app-wide - unchanged by this pass. **Network required:** model downloads, an optional update check. **Network not required:** transcription, summarization, resume parsing/generation, local document search, local AI inference, PDF generation, model switching, viewing existing documents - confirmed by direct code audit, not asserted from memory.

5 new tests (`test/services/offline/offline_readiness_service_test.dart`, real in-memory Sqflite database, not a mock): not-ready with nothing installed; not-ready with only some required models; ready once all three are active; an installed-but-inactive model doesn't count; the static checks always pass.

### Phase 18/19: Canonical resume model and custom sections - verified already correct, no change needed

Direct re-inspection of `ResumeSnapshot`/`ResumeCompilerService`/`ResumeTemplateRenderer` confirms the architecture Phase 18 asks for already exists exactly as specified: `Imported Resume → (confirmImport persists into library blocks) → ResumeCompilerService.compile() → ResumeSnapshot (canonical, frozen, template-independent) → ResumeTemplateRenderer → PDF`. `ResumeSnapshot` itself never imports anything from `template/` (confirmed by its own doc comment and file); every template is a pure function of one canonical snapshot, never a template-specific re-parse of the source. Custom sections (Phase 19) already exist as `CustomSectionBlock`/`ResolvedCustomSectionEntry`, rendered by every template exactly like any typed section - confirmed via the acceptance-matrix tests above (5 custom sections all survive to real headings, in source order, across every template). No code change was needed for either phase; this is a verification finding, not a fix.

### Phase 9: Home screen resume visibility - verified already satisfied

`HomeScreen`'s Quick Actions grid (the very first content section after the greeting, before any "Recent Meetings" content) already includes a "Resumes" tile (`RoutePaths.resumeList`) since Milestone 1. The "No meetings yet" empty state is correctly scoped to the *Recent Meetings* section specifically (not a whole-app claim) and doesn't compete with or hide the Resume entry point above it. No code change was made - this is a verified, not a claimed, finding.

### Phases 3/4/10: Explicitly NOT completed this pass - large scope, honestly disclosed rather than rushed

- **Phase 3** (verify the 5 existing templates are genuinely structurally distinct, not just color variants): already true from the prior pass's own Phase 3 work (chips/project-reordering on Modern Accent, emphasized-callout Summary on Executive Summary-Led, both through the shared content-plan pipeline) - re-confirmed by this pass's own 45-combination acceptance matrix finding every template pairwise byte-different. No further change needed.
- **Phase 4** (a new template matching the user's reference resume - centered header, blue accent, category-grouped skills grid): **NOT built this pass.** A genuine reference-faithful archetype is a multi-hour effort (new layout code, catalog registration, full render/pagination/acceptance-matrix coverage, visual verification) that this pass's remaining time budget did not allow doing to the same verification standard as everything else here. The closest existing archetype (Executive Summary-Led: centered identity, prominent Summary callout) does not yet use category-grouped skills (`groupSkillsByCategory`, already implemented and used by Balanced Two-Column) - wiring that in would be the smallest safe step toward the reference's skills presentation, not attempted here. Explicitly marked NOT DONE rather than claimed complete.
- **Phase 10** (document manager: search, sort, multi-select, preview): **NOT extended this pass.** The existing `DocumentsScreen`/`DocumentDetailsScreen` already support folders (create/rename/delete), per-document rename/move/delete, and both an empty-folder and no-documents empty state - confirmed via direct code review. Search (app-wide only, not scoped to Documents), sort, multi-select/bulk actions, and in-app PDF preview (the details screen shows extracted text/summary, not a rendered page view) are genuinely absent and were not added. A real, scoped feature addition, not a bug fix - explicitly deferred rather than rushed under this pass's remaining time.

### Phase 23: Final validation

- `flutter analyze` (project-wide, after every change in this pass): **0 issues** on every individual file checked incrementally; final full-repo run recorded in this session's own final report.
- `flutter test`: every new/modified test file passes individually (completeness: 29/29 combined with existing parser tests; offline readiness: 5/5; acceptance matrix: 45/45; activate()/onboarding fixes: verified via targeted runs); full-suite final count recorded in this session's own final report.
- No existing test was deleted or weakened to make this pass's changes pass - two existing tests (`installed_models_controller_test.dart`'s speechToText-activate test, and its own file's whisper-download-fix predecessor) were *strengthened* (given a real on-disk file matching the new verify-before-switch behavior), not loosened.

### Risk register additions (RV3-19 through RV3-22 - see `04-risk-register.md`)

RV3-19/RV3-20/RV3-21 (real-device data loss, Whisper download resumability, the `--target-platform` build bug) were resolved by the prior pass, unchanged here. This pass adds:
- **RV3-22 (new, ACCEPTED scope limit):** LLM/embedding model activation is not verified before switching, unlike Whisper - `ModelDownloadController.verify()` for those kinds can trigger real network I/O, and running it on every switch would both contradict the app's own "instant switching" UX promise and make it unsafe to call from a plain UI action. A corrupted/deleted LLM or embedding model file would only be caught the next time it's actually used (via the existing graceful AI-failure-degradation paths, all still correct and unchanged), not at switch time.

### Known limitations carried forward, unchanged by this pass

Sub-project structural nesting (still deferred, needs a real data-model change), physical Android-backgrounding download-resume behavior (still code/unit-test verified only), no physical Android device/emulator available anywhere in this implementation environment, no genuine human visual review against the Enhance CV bar, debug-keystore signing only. This pass did not close any of those - it closed the specific new findings this 25-phase spec's own audit surfaced (import completeness, link handling, template acceptance/distinguishability/content-completeness, the onboarding download race, model-activation integrity, and offline readiness), and explicitly did not attempt Phase 4's new template or Phase 10's document-manager expansion.

---

## Product-Quality Remediation Pass (Parts A-L)

A second, independent 12-part specification (Parts A-L), issued after the product owner reviewed a generated APK from the Reliability-Overhaul Pass (`a1ac9ed`) above and found its "all phases complete" framing did not match what the APK actually showed - explicitly instructing every part to AUDIT → IMPLEMENT (only where a real gap is found) → TEST → GENERATE OUTPUT → INSPECT → DOCUMENT → REPORT, never assume a prior pass's completeness claim. Each part below landed as its own commit; none were squashed. Sub-project structural nesting (the one limitation the prior two passes both explicitly deferred) was finally built this pass (Part A5).

**Parts B through G were completed in an earlier session turn than the one that wrote this section** - summarized here from their own commits and `03-decisions.md`/`04-risk-register.md` entries (D-M9-01 through D-M9-05, RV3-23/RV3-24), not re-narrated from memory. Parts H through L (below) were completed and documented directly by the session turn that wrote this section, with full first-hand detail.

### Part A5: Sub-project nesting data model (`a1ccdb1`)

`ExperienceSubProject` (`name` + its own `bullets`) added as a new `ExperienceBlock.subProjects` list (migration v20, additive/backward-compatible), threaded through `ResumeCompilerService` → `ResolvedExperienceEntry` → `ResumeContentPlan` → `content_line_renderer.dart`'s `buildEntryBlock`, rendering each sub-project as an indented bold sub-heading with its own indented bullets. Parser's `_splitIntoSubProjects` reuses the existing wrapped-continuation-line heuristic. **VISUAL VERIFIED** - the real Harshavardhan resume's SciLab/ByHeart/Crossword sub-projects render as structurally distinct nested entries in the generated Classic-template PDF, directly inspected. See D-M9-01.

### Parts B/C: Template quality + reference-matching (`2674903`)

Executive Summary-Led's Skills section now renders grouped by category (D-M9-02) - the smallest safe gap against the reference resume without a 6th template (explicit rule). Balanced Two-Column's pagination orphaning defect (RV3-24) was root-caused as far as static analysis allows (`package:pdf`'s `Partitions.layout()` gives each column the same `constraints.maxHeight` with no cross-column coordination) but not blindly patched without a reliable reproduction to verify a fix against - **OPEN, disclosed**.

### Part D: Document manager (`349631d`)

Real search (title substring) and sort (title/newest/oldest/largest) added to the Documents screen, operating on the same persisted rows every other part of the screen already reads (D-M9-03). Thumbnail/preview and multi-select remain a disclosed, not-yet-built gap - deliberately scoped out as a larger, separate lift.

### Part E: Multi-model management (`14ba445`)

9 of 10 explicit requirements were already correctly implemented; 5 new regression tests close the 2 genuine, previously-unverified gaps (a real end-to-end interrupted-download-then-resume splice against a real local loopback server, and the active model surviving a simulated app restart) - see D-M9-04.

### Part F: Offline readiness (`39cbeb0`)

Found and fixed a real inaccuracy: `OfflineReadinessService`'s own detail text claimed network was used for "an optional update check" - no such feature has ever existed anywhere in `lib/`, confirmed by a direct repo-wide grep. Also wrote the 20-step combined physical-device test plan (Parts F1/K, `08-quality-gates.md`) - still genuinely unexecuted, no device available.

### Part G: Acceptance matrix extension (`5f9ab6c`)

Extended `resume_acceptance_matrix_test.dart` with 2 new datasets (`J-subProjects`, `K-multipleLinks`) the matrix predated - sub-projects (D-M9-01) and `ResumeSnapshotProfile.links` had zero prior cross-template coverage. All 5 templates × both new datasets render valid, non-empty PDFs; this is also the first permanent, machine-checked confirmation that RV3-24 is cosmetic/layout-only, never data loss.

### Part H: JD tailoring re-verification (`5fd02f8`)

Direct audit found `ResumeJdAnalyzer`, `PrioritizeResumeContentUseCase`, and `GenerateResumeSuggestionsUseCase` all predated sub-projects and read only `entry.bullets`. Fixed the two read-only paths (JD-matching evidence, prioritization density scoring) to include sub-project content; deliberately left AI-suggestion generation scoped to top-level bullets only, since sub-projects have no write-back path through `SuggestedEdit`/`setOverride` - extending eligibility there would produce suggestions with no safe way to apply on accept. **AUTOMATED VERIFIED** - 6 new regression tests, 104/104 passing in `test/services/career/` + `test/features/career/analysis/` (was 99). See D-M9-06.

### Part I: Import completeness stress-testing (`9a8296e`)

Stress-tested 5 previously-untested realistic shapes (multi-role-same-company, sub-projects, a zero-bullet experience entry, curated non-Indian international locations, mixed bullet marker styles) - all 5 already worked correctly, no production change needed for those shapes themselves. Along the way, found and fixed a real bug: a single `"|"`-joined header line (this app's own documented common layout) whose every segment was individually extracted was *also* redundantly flagged as unclassified content still needing review. **AUTOMATED + VISUAL VERIFIED** - 10 new regression tests plus a manual PDF-generation script combining all 5 shapes, rendered across all 5 templates and directly inspected. 426/426 passing in `test/services/resume/` (was 419), 151/151 in `test/features/career/resume/`. See D-M9-07.

### Part J: Template gallery/preview "shows blank" (`4e4aad8`)

Root-caused by reading `package:printing`'s actual source: neither `ResumeTemplateDetailScreen` nor `ResumePreviewScreen` passed an `onError` callback to `PdfPreview`, so any render failure fell back to Flutter's own default `ErrorWidget` - whose message text is computed inside an `assert()` block, stripped entirely in release builds, leaving a bare textless box. Fixed both screens with an `onError` builder reusing the app's existing `ErrorState` convention; also added `AppLogger.warning` diagnostics to the grid thumbnail's previously-silent catch, closing a gap the Reliability-Overhaul Pass had disclosed but not fixed. **AUTOMATED VERIFIED** - 2 new tests assert `find.byType(ErrorWidget)` is `findsNothing`. 153/153 passing in `test/features/career/resume/` (was 151). See D-M9-08.

### Part K: Release APK build + inspection (`bf8d86b`)

Built the release APK for real (`flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`, the D-M7-05 fix) and verified `REAL_EXIT_CODE=0` via a non-piped, unmasked check. **VISUAL VERIFIED** - both ABI APKs inspected via `unzip -l`: zero LiteRT/tflite/onnx traces, zero bundled model weights, debug-keystore signing confirmed, sizes essentially unchanged (arm64-v8a 127.9MB, armeabi-v7a 110.4MB) from the last documented measurement. Found one new, genuine, previously-unverified-per-ABI gap: the `armeabi-v7a` build ships zero llama.cpp native libraries at all - **CODE VERIFIED** via direct inspection of the installed `llamadart-0.8.17` package source (no `android-arm` build target exists in its own supported-target list, an upstream constraint, not a project misconfiguration). Traced the failure path and confirmed it degrades gracefully (the existing AC3-05 model-load-failure handling applies) rather than crashing. Disclosed as RV3-25, not fixed - no in-project fix is possible. See D-M9-09.

### Part L: Final documentation sync + quality gate (this section)

**Full regression run, batched per top-level `test/` subdirectory** (this environment's own established practice - a monolithic `flutter test`/`flutter analyze` across the whole repo has previously crashed with a Windows `DartWorker` thread/memory-exhaustion error):
- `flutter analyze lib/` - **0 issues** (271s).
- `flutter analyze test/` - **0 issues** (176s).
- `flutter test test/core test/database test/models test/repositories test/shared test/use_cases test/widget_test.dart` - **493/493 passing**.
- `flutter test test/services` - **762/762 passing**.
- `flutter test test/features` - **365/365 passing**.
- **Total: 1620/1620 passing, zero failures, zero regressions.** `test/performance/` (expensive indexing/search benchmarks, no code touched by any Part A-L change) and `test/manual/` (one-off PDF-generation scripts, explicitly documented in their own file headers as outside the regular regression suite) were deliberately not included in this final run - a scoping decision, not an oversight.

**Documentation synced:** `03-decisions.md` (D-M9-01 through D-M9-09, all grounded in real commits/tests), `04-risk-register.md` (RV3-23/RV3-24/RV3-25), `08-quality-gates.md` (a full Parts A-K gate-result table), and this file's own new section above. `01-master-roadmap.md`, `02-backlog.md`, `05-dependency-graph.md`, `06-module-order.md`, `07-git-strategy.md`, `09-definition-of-done.md`, `11-gap-analysis.md`, `12-architecture-diagrams.md` reviewed for staleness against this pass's changes - none required a substantive update (this pass's changes were fixes/verification/tests within already-documented architecture, not new modules, new dependencies, or new milestone-level scope).

**Git checkpoint:** every part (A5 through L) is its own commit on `main`, none squashed. **Not pushed to `origin/main`** - explicit instruction: "Do NOT push to GitHub unless I explicitly tell you to push."

### Known limitations carried forward, unchanged by this pass

Every limitation the Reliability-Overhaul Pass listed above remains open: no physical Android device/emulator available anywhere in this implementation environment (the 20-step test plan, Parts F1/K, remains genuinely unexecuted), no genuine human visual review against the Enhance CV bar, debug-keystore signing only, Balanced Two-Column's RV3-24 pagination defect (disclosed, not fixed), Document manager's thumbnail/preview and multi-select (disclosed, not built). This pass adds one new disclosed limitation: **RV3-25** - the `armeabi-v7a` release APK has no on-device LLM/embedding capability at all (an upstream `llamadart` package constraint), though it degrades gracefully rather than crashing.

---

## R-6 / R-7 / R-8 Product-Quality Passes (V3-scoped pieces)

Three short, real-screenshot-driven product-quality passes ran after Part L, each a mix of V1/V2 (meeting/toolkit/chat) and V3 (resume) fixes in the same commit — this section covers only the V3-scoped pieces; see [`docs/v2/implementation/10-v2-progress.md`](../../v2/implementation/10-v2-progress.md) for the V1/V2-scoped pieces of the same three commits.

**R-6 (`1f2c8ea`, 2026-08-21):**
- **Resume template gallery freeze, fixed.** Every visible template card in `ResumeTemplateGalleryScreen` independently triggered its own root-isolate `Printing.raster()` thumbnail call with no serialization, piling up native rasterization work and freezing the UI thread. Fixed with a minimal, dependency-free serial task queue (chain each new thumbnail task onto the previous one's completion) added to `resume_template_providers.dart`, scoped to `templateResumeThumbnailProvider` only — the same "one exclusive native resource, many callers" pattern `LlmRequestQueue` already solves for the LLM engine, sized down to what this narrower case actually needs (no priority/foreground handling).
- **`AiDisclaimer` added to `ResumeSuggestionReviewScreen`** — the AI-rewrite-suggestion review screen now shows the same shared disclaimer widget every other AI-generated-content surface uses, closing a gap where this screen (arguably the highest-stakes AI surface in the whole app, since it's the one screen that can write AI text into a real resume) had none.

**R-7 (`a0582fb`, 2026-08-21):** the Progressive Resume Wizard and "Create Resume from a Job Description" — already fully documented in [12-architecture-diagrams.md §11](12-architecture-diagrams.md#11-r-7-additions--progressive-resume-wizard--create-resume-from-a-job-description-built), added as part of that same commit (renumbered from §10 to §11 in the diagrams-readability pass that added a new §10 overview diagram). No further doc changes needed for R-7 itself; this entry exists so the milestone/pass timeline in this file doesn't have a silent gap between Part L and R-8.

**R-8 (`d0333c0`, 2026-08-21):**
- **`AiDisclaimer` added to two more AI-generated-content surfaces** flagged by this pass's own audit: `BulletSuggestionField`'s "Improve with AI" preview (used on every resume block editor, and reused as-is by R-10's Beginner Resume Review step) and `ResumeImportScreen`'s AI second-pass offer card.
- Not resume-specific, but shares the same root-cause class as the gallery freeze above: `answerQuestionStream` (document/RAG chat) and the older Ask feature's `answerQuestion` both replaced a fixed `maxTokens: 300` with `outputBudgetTokens()`, a dynamically computed budget sized to actual remaining context-window headroom — see [`docs/v2/implementation/10-v2-progress.md`](../../v2/implementation/10-v2-progress.md) for the full detail, since neither AI surface is resume-scoped.

**AI disclaimer coverage, as of R-8 (verified by direct `grep` across `lib/`):** meeting summary + Minutes of Meeting tabs (`meeting_details_screen.dart`, ×2), Chat's message bubbles (`chat_screen.dart`), Resume's AI-suggestion review screen (`resume_suggestion_review_screen.dart`), Resume Import's AI second-pass offer (`resume_import_screen.dart`), `BulletSuggestionField`'s inline AI-rewrite preview (used across every resume block editor and R-10's Beginner Resume Review step), and R-10's own Beginner Resume Review step. Every AI-generated-text surface in the app carries the shared `AiDisclaimer`/`AiDisclaimer.resume()` widget — there is no known gap as of this writing.

**Quality gates (R-6/R-7/R-8, combined):** each commit's own stated scope was verified individually at commit time (`flutter analyze` clean, new/extended tests passing per that commit's message) — see each commit's own message for exact counts. No V3-specific regression was introduced; the full-suite re-run that follows R-10 below (2076/2076) re-confirms this.

---

## R-9 — Final Build + Physical-Device Validation Preparation

Build-and-config-only phase, no product behavior changed. `flutter clean`/`pub get`/`analyze`/`test` re-run clean, then `flutter build apk --debug` OOM-crashed the Gradle daemon twice on this implementation environment's constrained 8GB/2-vCPU host. Explicitly authorized fix: `android/gradle.properties`'s `org.gradle.jvmargs` lowered from `-Xmx2560m -XX:MaxMetaspaceSize=768m` to `-Xmx1536m -XX:MaxMetaspaceSize=512m` (committed separately, `9d0e63d`, per its own explicit "commit only this change" instruction). Debug APK then built successfully: `app-debug.apk`, 464MB. No physical-device testing was performed as part of this phase — that was always the next, separate step, per this phase's own explicit "I will install this APK on my physical Android device and test the application manually" instruction.

---

## R-10 — Beginner Resume Flow

**"Create a Beginner Resume"** — a short, progressive flow for users with little/no work experience or projects (fresh graduates, first-time job seekers). Full architecture already diagrammed in [12-architecture-diagrams.md §12](12-architecture-diagrams.md#12-r-10-addition--beginner-resume-flow-built) (renumbered from §11 to §12 in the diagrams-readability pass), and now also shown alongside the other two resume-creation paths in [§10, "Resume Creation Entry Points"](12-architecture-diagrams.md#10-resume-creation-entry-points-built); this entry is this file's own status record, per this file's "every pass gets an entry here" convention.

**What shipped:** a 7-step wizard (Basic details → Target role → Education → Experience → Skills → Languages/Certifications/Achievements → Review) reached via a full-width entry card on the Resume list screen (same prominence as "My Profile," not a buried icon). Target role is either picked from a new, static, deterministic `RoleCategoryCatalog` (14 curated categories: General Fresher, Sales Executive, Business Development Executive, Customer Support Executive, Data Entry Operator, Office/Admin Assistant, HR/Recruitment Assistant, Marketing Executive, Accounts Assistant, Banking/Finance Fresher, IT/Technical Support, Software/IT Fresher, Operations Executive, Retail Executive), matched from a pasted short job title via `RoleCategoryMatcher` (exact/alias/token-overlap, falls back to General Fresher, never throws), or routed to the existing R-7 JD pipeline unchanged if real JD text/a file is supplied. Generation (`CreateBeginnerResumeUseCase`) writes through the exact same `Resume`/`ResumeBlockRef`/block-repository architecture every other resume-creation path uses — no parallel model, no new database table. Every section is created only if the user actually supplied it; no experience/project/certification content is ever invented. The Review step's summary is deterministic (`buildBeginnerResumeSummary()`), with the pre-existing `BulletSuggestionField` offering an optional, disclaimed AI polish as the *only* AI touchpoint in the entire flow — the flow completes and produces a full, exportable resume with zero AI model installed. Generation hands off to a dedicated 3-template chooser (Entry-Level/Student, Classic, Modern Accent) or, if a real JD was supplied, to the existing `ResumeJdAnalysisScreen`, then to the standard, unmodified Resume Editor/export pipeline.

**Bugs found and fixed during implementation (test-driven, not superficial):** a missing constructor parameter (compile error, caught by `flutter analyze`); a broken `markNeedsBuild()` rebuild hack in the role-search picker, replaced with the correct `ListenableBuilder(listenable: searchController, ...)` pattern; a real `_NavBar` `RenderFlex` overflow at realistic 412dp phone width (a genuine device-relevant UX bug, not a test artifact); a genuine cross-widget Riverpod reactivity bug (`_BeginnerResumeScreenState.build()` never `ref.watch`'d the shared JD provider, so the Next button stayed stale-disabled after a real JD finished parsing even though the child JD-status widget updated correctly); and a template-catalog lookup bug (`ResumeTemplateCatalog.specById()` was being called with a bare archetype id, not the catalog's real composite `archetypeId-tokenPresetId` id, so all 3 "distinct" template cards silently collapsed to Classic).

**Verification:** `flutter analyze lib/ test/` — no issues. `flutter test` — **2076/2076 passing** (2017 pre-existing + 59 new: `role_category_matcher_test.dart` 30, `role_input_classifier_test.dart` 8, `create_beginner_resume_use_case_test.dart` 14, `beginner_resume_screen_test.dart` 6, `beginner_resume_template_screen_test.dart` 2 — zero regressions, including the app-wide `widget_test.dart` smoke test still passing with the new entry card in place). Offline confirmed by direct grep of every new file: zero `http`/`Dio`/`HttpClient`/`Uri.parse`.

**Known limitations (see [04-risk-register.md](04-risk-register.md) RV3-26):** Institution and exact experience dates are not required fields — left blank rather than fabricated when not supplied, easily filled in via the standard Editor reached right after generation. No dedicated "Help me fill this" mode was built — inline hint text on each step serves the same purpose. Debug-signed APK only; production/release signing and Play Store readiness remain not done (unchanged, standing limitation). Physical-device validation of this flow (like every other V3 feature) has not been performed in this implementation environment — no Android device/emulator available.

**Git status:** committed and pushed (`459294d`, 2026-08-22) once the user explicitly requested it after physical-device testing began — at the time this section was first written, R-10 was deliberately uncommitted per its own "DO NOT COMMIT" instruction; that instruction was superseded by the user's later explicit "commit and push everything" request.

---

## R-11 — Physical-Device Bug Fixes (V3-scoped pieces)

First real physical-device testing surfaced concrete bugs across several areas; this entry covers only the V3/Resume-scoped fixes. See [`docs/v2/implementation/10-v2-progress.md`](../../v2/implementation/10-v2-progress.md) for the V1/V2-scoped pieces of the same pass (resumable model downloads, onboarding pause/resume UX, Offline Readiness relocation + user-facing rewrite, terminology cleanup).

**P0 — "Create Resume from a Job Description" looked broken end-to-end.** Traced the full flow (JD input → parser → role/company detection → `CreateResumeFromJdUseCase` → `initialResumeId` → `ResumeJdAnalysisScreen` → `GenerateResumeSuggestionsUseCase` → suggestion review) against the real code, not assumed. Found two real, distinct UX bugs, both now fixed - the underlying R-7 pipeline itself needed no logic change:
- **No dead end when "My Profile" isn't set up yet.** `CreateResumeFromJdUseCase` correctly throws `NoProfileException` when there's no profile to build a tailored resume from (by design - nothing to build *from* without one), and `JdToResumeScreen` already displayed that message - but gave the user no way forward. On a fresh device, this is the common case, not the exceptional one. Added a "Set up My Profile" button directly in the error state (`_setUpProfile()`, reuses the existing `openOrCreateProfile()` helper unchanged) that creates the profile and opens the Editor via `context.push` (not a replace), so popping back returns to the exact same JD-review screen with the already-parsed JD still there - no re-paste needed, "Create my resume" then succeeds.
- **"No AI suggestions" looked identical whether generation had run or not, and gave no reason why.** `GenerateResumeSuggestionsUseCase` is deliberately scoped to `MatchLevel.partial` skill matches only (an exact match needs no rewrite, a fully-missing skill has nothing to rewrite from without inventing content, D-M3-02) - correct, tested behavior, not a bug. But `ResumeJdAnalysisScreen` simply hid the "Generate AI suggestions" button with zero explanation when there were no partial matches, and `ResumeSuggestionReviewScreen`'s empty state ("check back after running one") read as if generation hadn't happened yet even right after a user tapped it and got zero results. Both screens now say plainly why: no partial skill matches means nothing safe to rewrite, not a broken feature.

**P0 — Beginner Resume template selection destroyed the navigation stack.** `BeginnerResumeTemplateScreen._select()` used `context.go(RoutePaths.resumeEditorPath(resumeId))`, which replaces the *entire* GoRouter stack with just the Editor route - silently discarding Home and Resume List from history, leaving the system/app-bar back button with nothing to return to (the real-device report: "trapped inside Resume creation, no way back to Home"). A near-identical anti-pattern is already documented and avoided in `ResumeTemplateDetailScreen._useThisTemplate`'s own doc comment - this screen just didn't follow it. Fixed by switching to `context.pushReplacement`, the same convention `JdToResumeScreen`/`ResumeTemplateDetailScreen` already use: swaps only this one screen for the Editor, Home and Resume List stay in the stack underneath.

**Tests added:** `jd_to_resume_screen_test.dart` (+2, including a full "hit the dead end → set up profile → return → retry succeeds" round trip), `resume_jd_analysis_screen_test.dart` (+2, no-partial-matches explanation), `resume_suggestion_review_screen_test.dart` (3 existing tests updated for the reworded empty state), `beginner_resume_template_screen_test.dart` (+1, a dedicated back-stack-integrity regression test using `Navigator.canPop()` after selection, with its own router shaped like the real Home → List → Template Chooser stack).

**Verification:** `flutter analyze lib/ test/` - no issues. `flutter test` - see this section's own final count below (run together with the V1/V2-scoped R-11 changes, one full-suite pass).
