# V3 PRD — Offline AI Resume Builder

**Status:** Locked. Implementation-ready.
**Supersedes:** nothing — this is the first V3 planning document; no `docs/v3/` folder existed before it. The existing Resume/Career code in `lib/features/career/`, `lib/services/resume/`, `lib/services/career/`, and migration `v16` is the implementation baseline this PRD builds on, not the definition of V3.
**Related:** `docs/v2/` (frozen V2 spec, untouched by this document), the V3 Product Discovery & Architecture Report (session artifact, not stored in-repo — its findings are folded into this PRD directly).

This document is intentionally self-contained: product definition, requirements, architecture, and milestones in one place, so an engineering agent can implement directly from it without re-deriving context.

---

## 1. Product definition

V3 is an offline, on-device AI Resume Builder inside OfflineMoMAI. A user brings an existing resume or starts from nothing, picks a professional template, and produces a polished, ATS-friendly resume. If they supply a Job Description, the app tailors the resume to it — identifying relevant and missing content, proposing specific rewrites — while the user reviews, edits, accepts, or rejects every meaningful AI change before it becomes part of their resume. Nothing about resume content, JD content, or the tailoring process ever leaves the device except through model download.

## 2. Locked non-negotiable requirements

These are constraints, not options. Every section below is written to satisfy them; none may be traded off during implementation.

1. **Strictly offline** after model download. No cloud LLM, no resume/JD transmission, network used only for explicit model acquisition.
2. **Existing resume → new professional resume**, with no silent information loss and a user review/correction step before content is finalized.
3. **Blank → professional resume**, with intelligent guidance rather than a bare form.
4. **Existing resume + JD → tailored resume**, with every suggestion reviewable and a hard rule against fabricating experience, skills, employers, technologies, or achievements.
5. **JD → new resume** (blank-start variant of #4), same fabrication rule.
6. **Resume quality is core**, not cosmetic: professional typography/hierarchy/layout across ~20 genuinely distinct templates, ATS-conscious, Enhance CV as the visual quality bar.
7. **ATS compatibility** is required and honestly represented — never claimed as guaranteed.
8. **Device/model strategy** must work on 4–6GB RAM Android devices by default; a stronger model is opt-in, never required.
9. **AI suggestions while typing** are debounced and tiered (deterministic always-available Tier 1, optional model-backed Tier 2) — not literal live autocomplete.
10. **User control**: AI proposes, never silently modifies; rejected suggestions leave original content untouched; the user can always manually edit.

## 3. Target users / personas

| Persona | Need | Primary journey |
|---|---|---|
| Student / recent graduate (existing app persona, continued from V2) | First resume, or first professional-looking resume, little existing content | Blank → professional resume (§Journey B); JD → new resume (§Journey D) when applying to a specific listing |
| Job seeker with an existing resume, applying broadly | Wants a genuinely better-looking version of what they have, without rebuilding it by hand | Existing resume → new resume (§Journey A) |
| Job seeker targeting a specific role | Has a resume, has a JD, wants it tailored without lying about their background | Existing resume + JD → tailored resume (§Journey C) — the product's central loop |
| Low-RAM-device user (4–6GB, common in the target India market) | Needs the feature to work without a large model download | All journeys, on the fallback model tier |

Out of scope for this PRD: academic/CV-heavy personas requiring Publications/Research sections (deferred, see §22.6), B2B/recruiter-facing personas (not part of the product vision at all).

## 4. Core user journeys

### Journey A — Existing resume → new resume
Import file (PDF/DOCX/TXT/MD) → existing extraction + existing deterministic parser structure it → **editable** per-entry review (upgraded from today's read-only review) → confirm → content lands in the block library → template gallery → polished resume rendered → export.

### Journey B — Blank → professional resume
Pick a template → enter profile → for each section, add blocks (existing add/create flow) → Tier-1 deterministic writing guidance always available; Tier-2 model-backed suggestions on demand → export.

### Journey C — Existing resume + JD → tailored resume
Journey A's import (or an already-built resume) → import JD → deterministic match (keyword + semantic) → deterministic relevance prioritization → bounded per-entry AI rewrite suggestions → suggestion review screen (accept/edit/reject each) → compile final content → template gallery (if not already chosen) → export, optionally saved as a JD-tagged version.

### Journey D — JD → new resume (blank-start)
Pick a template → import JD first → the JD's stated requirements surface as a guided checklist of what's worth adding while the user fills sections → once enough content exists, the same deterministic-match → suggestion pipeline as Journey C runs → review → export.

*(Journey D reuses Journey C's pipeline once content exists; its only novel part is the pre-content "guided checklist" UX — see §11.5.)*

## 5. Functional requirements

| ID | Requirement |
|---|---|
| FR3-01 | User can import a resume file (PDF/DOCX/TXT/MD) and reach an editable, per-entry-correctable structured review before anything is saved. |
| FR3-02 | Content the parser cannot confidently structure is shown to the user, never silently dropped. |
| FR3-03 | User can create a resume from a blank state using the existing block-library create/attach flow. |
| FR3-04 | User can select a template from ~20 offered options before or after entering content; switching templates never alters resume content, only its rendering. |
| FR3-05 | User can import a JD file (PDF/DOCX/TXT/MD); JD content is held in memory for the current session only unless explicitly promoted to a saved version's metadata (§16). |
| FR3-06 | System deterministically matches JD requirements against resume content (exact keyword, alias, semantic-embedding, or missing) and shows evidence for every match. |
| FR3-07 | System generates bounded, per-entry AI rewrite suggestions for content relevant-but-improvable against JD requirements. |
| FR3-08 | Every AI suggestion is a distinct, reviewable object the user can accept, edit, or reject individually; nothing is applied automatically. |
| FR3-09 | Rejecting a suggestion leaves the original content byte-identical. |
| FR3-10 | Accepting a suggestion updates the live draft the same way a manual edit would. |
| FR3-11 | User can manually edit any content at any time, independent of AI suggestions. |
| FR3-12 | System exports the final resume as a polished PDF using the selected template, plus text/Markdown as today. |
| FR3-13 | User can save a version of a resume; a version may optionally be tagged with the JD title/company it was tailored for. |
| FR3-14 | User can restore a saved version into the live editable draft. |
| FR3-15 | Before first use of the Resume feature, the system offers (never requires) downloading a stronger model, explaining the trade-off in plain language. |
| FR3-16 | The Resume feature is fully usable on the existing, already-installed model with no additional download. |
| FR3-17 | While typing a bullet/summary field, the user can trigger writing-quality suggestions after a pause (debounced), never on every keystroke. |

## 6. AI behavior and safety rules

These are hard constraints on every AI-touching code path, not guidelines.

- **AC3-01 (fabrication ban):** the model must never introduce a fact — number, date, employer, technology, credential, responsibility — that is not already present in the user's own resume content passed into that specific prompt. Prompts must state this explicitly and narrowly (per-entry scope, not "the whole resume," so the model has no room to reach for unrelated invented context).
- **AC3-02 (proposal-only):** no code path may write LLM output directly into a `resume_blocks`/library-block row. Every LLM output becomes a `SuggestedEdit` row first; only an explicit user-accept action (or an "accept all" convenience action the user explicitly triggers) merges it into live content.
- **AC3-03 (deterministic backstop):** every suggestion passes through a deterministic post-check (`SuggestionFabricationGuard`, §22) that flags — for extra user scrutiny, never auto-rejects — any number, date, or proper noun in the suggested text absent from the original text. This is disclosed to the user as a best-effort check, not a guarantee.
- **AC3-04 (bounded scope):** no generative call may include more than one resume entry's worth of content plus its one associated JD requirement. Whole-resume or whole-JD prompts are prohibited by architecture (§22), not just by convention — the 2048-token context window makes this a correctness requirement, not a style preference.
- **AC3-05 (graceful degradation):** if the LLM or embedding model is unavailable, unloaded, or fails to load, the tailoring pipeline still completes through its deterministic stages (match, prioritize) and simply produces zero AI rewrite suggestions rather than failing the whole flow.
- **AC3-06 (transparency):** the UI must always distinguish AI-suggested-and-accepted content from user-authored content in a way the user can find later (at minimum, in the suggestion history for that resume) — accepted suggestions are not required to be visually marked forever in the editor, but their provenance must not be lost.

## 7. Resume content model requirements

- The existing `Resume` / library-block / `ResumeBlockRef` / `ResumeSnapshot` model (§Architecture baseline) is the content model. It is extended, not replaced.
- Content must remain fully independent of any template: `ResumeCompilerService.compile()` output (`ResumeSnapshot`) must never be template-aware. Template selection happens strictly at the rendering step.
- `Resume.targetRole` (existing dead field) becomes live: read/written by the Editor's Profile card.
- A new lightweight `achievements` field (JSON string list, mirroring the existing `links_json` pattern) is added directly to `resumes` — not a new block-library table — for short, non-relational achievement bullets. This is a deliberately minimal addition; a full `AchievementBlock` table/repository/UI stack is not justified by the content's simplicity (see Milestone 0).

## 8. Template / design system requirements

- Templates are **archetypes × design-token presets**, not 20 independently coded documents (§22.2 for architecture).
- Ten layout archetypes: Classic Single-Column, Modern Accent-Rule, Two-Column Sidebar, Executive Summary-Led, Compact Technical, Creative/Visual-First, Entry-Level/Student, Minimalist Monochrome, Government/Public-Sector Dense, and one held-open slot for a tenth archetype selected during Milestone 4 based on what the first nine reveal about gaps (recommendation, not a blocking decision — an Academic/CV archetype is explicitly deferred per §22.6, so this slot is intentionally not pre-committed).
- Two token presets per archetype at launch (≈20 selectable templates), sharing all layout code.
- Every template carries a visible ATS-confidence rating: **Maximum / High / Medium** (§9).
- Design tokens (`ResumeDesignTokens`) are purpose-built for document rendering and are **not** derived from or coupled to the app's Flutter `AppTheme`/`AccentColors` — different rendering technology (`pdf` package widgets vs. Flutter widgets), different concern (print typography vs. app chrome).
- No template may render body text below a 9pt-equivalent floor, and no template may place contact info exclusively in a page header/footer region (ATS risk, §9).
- Multi-column archetypes must be verified for correct logical reading order per template (§9) before shipping.

## 9. ATS requirements

"ATS-friendly" is defined operationally, not left to intuition:

- Real, selectable text layer in every generated PDF — no rasterized/image text, ever. (Already guaranteed by using `package:pdf`'s widget-based generation rather than the Toolkit's image-rasterization approach.)
- Section headings must exist as literal, standard text (e.g., "Experience," "Education," "Skills") in the extracted text, regardless of visual icon/styling treatment.
- Logical reading order in the underlying content stream must match visual reading order for every template, including multi-column ones.
- No table-based layout for chronology-critical content (dates, titles, employers).
- No watermarks, background images, or decorative elements behind text.
- Consistent, parseable date formatting.
- **The product must never state or imply "100% ATS guaranteed."** Every template surfaces its ATS-confidence rating in the UI at selection time.
- Verification method: an automated extraction round-trip test per template — render → extract via the existing `PdfParser`/`read_pdf_text` pipeline → assert expected section headings and reading order survive. This is disclosed to the user as a best-effort self-check, not proof against every real-world ATS (which are proprietary and cannot be tested directly in this environment).

## 10. Import requirements

- Reuse the existing `DocumentTextExtractionService` implementations (PDF/DOCX/TXT/MD) unmodified — already correctly wired, no change needed here.
- Reuse the existing deterministic `ResumeImportParser` / `JdParser` as the first-pass structuring layer — they are careful, tested, and already avoid silent data loss (unclassified-text fallback). Do not replace them with an LLM-based parser as a first resort.
- **New in V3:** the import review screen becomes per-entry editable (today it only allows editing the resume title). The user must be able to correct a misclassified line before import commits, not just accept-or-cancel the whole batch.
- **New in V3, Milestone 4:** when the deterministic parser's `unclassifiedText` ratio for a document exceeds a defined threshold (recommendation: unclassified text exceeding 30% of total non-preamble content — tune during implementation, not a blocking decision), offer an optional LLM-assisted second pass that attempts to structure the unclassified remainder, presented with the same review-before-commit discipline. Deterministic parsing remains the default and first attempt always; the LLM pass is a fallback, never a replacement.

## 11. JD tailoring requirements

1. Deterministic keyword/alias matching (existing `ResumeJdAnalyzer`) remains the trust anchor — every exact/alias match is explainable by quoted resume text, and it structurally cannot fabricate a match.
2. Add a semantic-embedding matching tier using the existing `EmbeddingEngine`, additive only: it may add a new "semantic match" classification for a requirement that has no keyword/alias match, but it may never downgrade or remove an existing keyword-tier match. Degrades gracefully (keyword-tier-only results) if the embedding model isn't available.
3. Deterministic relevance prioritization re-ranks existing resume entries by requirement-match density — no LLM call, since this is sorting the user's own already-authored content.
4. AI rewrite suggestions are generated only for entries flagged as relevant-but-improvable, one bounded call per entry (§6, §22).
5. **Journey D's guided-checklist mode** (JD-first, blank resume): before enough content exists to run real matching, the JD's own extracted requirements are surfaced as a plain checklist ("This role mentions Kubernetes, CI/CD, and 3+ years of experience — consider covering these if relevant") to guide what the user fills in. This is deterministic (the JD parser's own output, not a matching result) and must never suggest the user has experience they haven't stated.
6. The analysis results screen must link back into the Editor for every finding (missing/partial requirement → jump to the relevant section) — the current implementation's dead-end report is a confirmed gap this PRD closes (Milestone 2).

## 12. Suggestion / review UX

- Suggestions are listed per-resume, grouped by target entry, each showing: original text, suggested text, the JD requirement it relates to (if any), and accept/edit/reject controls.
- Editing a suggestion before accepting must be possible (the user isn't limited to a binary accept/reject of the model's exact wording).
- An "accept all" convenience action may exist but must never be the only path — every suggestion must be independently visible first.
- Suggestion history for a resume is not deleted on reject; rejected suggestions are retained (status: `rejected`) for audit/undo purposes rather than hard-deleted, until the resume itself is deleted.
- Debounced writing-quality suggestions (Journey B/Tier 1+2, §5 FR3-17): Tier 1 (deterministic — weak-verb detection, "consider adding a measurable detail" prompts, never auto-inserted) requires no model and is always available; Tier 2 (model-backed rewrite) is an explicit user-triggered action after a pause/blur, never continuous.

## 13. Model / device strategy

- **Existing model remains the required baseline**: Qwen2.5-1.5B-Instruct (already required for the rest of the app) must be sufficient for every core Resume feature — import, template rendering, deterministic matching, and at least basic rewrite suggestions. This is a hard requirement, not aspirational.
- **A second, stronger LLM tier is added to `ModelCatalog`** as an explicit opt-in, offered via a one-time prompt before first entering the Resume feature ("For better resume results, you can download the recommended model. Once downloaded, it stays on your device and works offline."). Declining must not block or degrade access to the feature beyond producing lower-quality suggestions from the existing model.
- **Device RAM detection** (new): a `DeviceCapabilityService` reads total device RAM (via `device_info_plus` or equivalent) and maps it to the existing-but-currently-unpopulated `RecommendedDeviceTier` field already present in `ModelCatalog`'s data model. Used only to inform the model-upgrade recommendation — never to block the feature.
- **RAM sequencing on low-tier devices (≤6GB):** never hold the LLM and embedding models resident simultaneously during tailoring. Run the deterministic + embedding-matching pass first, allow the idle-unload/reference-counting machinery to release the embedding model, then load the LLM for the rewrite pass. On higher-tier devices this sequencing is not enforced (existing `ModelLifecycleManager` behavior is sufficient).
- **Model download remains the only network activity**, using the existing AI Model Manager infrastructure unmodified.

## 14. Offline / privacy requirements

- No network call of any kind is permitted in any resume/JD code path except the existing model-download mechanism.
- Resume and JD content must never appear in a log message, exception message, or crash report — enforced by reusing the existing `friendlyErrorMessage()` discipline.
- JD content is held in memory only for the current session; the only JD data persisted anywhere is the optional title/company label on a tailored `ResumeVersion` (§16) — never the full JD text.
- Exported PDFs are written to the app-private documents directory (`career_paths.dart`'s existing convention) and only leave the device via an explicit user-initiated share action.
- Verify (Milestone 5) whether `package:pdf` embeds any author/creator metadata by default; strip or set it to a neutral value if so, since exported resumes are routinely shared externally.

## 15. PDF / export requirements

- PDF generation continues to use `package:pdf`/`package:printing` — no new PDF dependency.
- The single hardcoded template in `ResumePdfExportService` is replaced by a template-driven renderer (§22.2) that accepts a `ResumeSnapshot` + a `ResumeTemplateSpec` (archetype + token preset).
- The atomic temp-file-then-rename write discipline already present in `ResumePdfExportService` is preserved unchanged in the new renderer.
- Text/Markdown export (`ResumeTextExportService`) is retained as-is — it is template-agnostic by design and already well-tested; no changes required beyond reflecting any new content fields (e.g., achievements) in its section list.
- Page-overflow must be handled gracefully (flowing to a second page for archetypes that support it) — never silently clipped content.

## 16. Versioning requirements

- `ResumeVersion` gains two additive, nullable fields: `templateId` (which template rendered this frozen snapshot) and a JD-tag pair, `tailoredForJdTitle` / `tailoredForJdCompany` (plain labels, never the full JD text — see §14).
- Versions remain immutable once saved (existing guarantee, unchanged).
- **New:** a version can be restored into the live editable draft (a confirmed gap in the current implementation). Restoring does not delete the version being restored from; it copies the version's content back into the live block composition, subject to the same dangling-reference-tolerant compilation behavior the compiler already has.

## 17. Validation requirements

- Below-the-dialog-layer validation is currently absent (confirmed gap) and must be added for: non-empty resume title, non-empty full name before export is allowed, and a basic date-format sanity check on experience/education/certification date fields (free-text is still accepted, but a clearly malformed value — e.g., non-numeric year — surfaces a non-blocking warning rather than silently propagating into the experience-years calculation).
- Duplicate resume titles remain allowed (no hard uniqueness constraint) but the resume list should disambiguate by showing the last-updated date alongside the title (a small UX addition, not a data-model change).
- `SuggestedEdit` values must never be persisted with a `status` other than the four defined states (`pending`/`accepted`/`rejected`/`edited`) — enforced at the model layer.

## 18. Error / failure handling

- LLM/embedding call failure during tailoring: caught, logged (via existing sanitized-logging discipline, never with resume/JD content), and surfaced as a friendly, specific message; the deterministic results already computed are still shown (partial success, not all-or-nothing failure).
- Import parse failure (corrupt file, unreadable format): existing `ResumeImportPickException`/extraction-service error handling already covers this — no change needed, confirmed adequate in the prior audit.
- PDF render failure: existing `ResumePdfRenderException` pattern is preserved in the new template renderer.
- Suggestion-generation timeout (LLM stall beyond the existing 45s ceiling): the affected entry is marked as "suggestion unavailable" rather than blocking the rest of the batch; other entries' suggestions still complete.
- Device RAM read failure/unavailable (some devices/OS versions may not expose this cleanly): fall back to treating the device as the lowest tier — never crash, never block the feature.

## 19. Performance requirements

| Operation | Target | Class |
|---|---|---|
| Resume/JD file import → review screen | < 3s | Desired |
| Deterministic JD↔resume match (no AI) | < 1s | Desired |
| Semantic-embedding matching pass (model already loaded) | < 2s | Desired |
| Embedding model cold load | Existing `isPreparingModel` UX pattern reused | Hard requirement (reuse, not new) |
| Per-entry LLM rewrite suggestion | Single-digit seconds typical; 45s existing stall ceiling is the hard failure bound, not the target | Needs real-device benchmarking |
| Template render to PDF | < 2s per page | Desired |
| Template gallery browsing (no render, preview only) | Instant, no model/file I/O involved | Hard requirement |

## 20. Accessibility requirements

- Every new interactive control (template picker cards, suggestion accept/edit/reject buttons, the model-upgrade prompt) must carry an explicit accessible label, consistent with the app-wide TalkBack discipline already established in V2 (`Semantics`/`semanticLabel` conventions).
- Template preview cards must not rely on color alone to convey ATS-confidence rating — pair color with a text label ("Maximum ATS," "High ATS," "Medium ATS").
- Suggestion diffs (original vs. suggested text) must be presented in a way a screen reader can traverse meaningfully (e.g., clearly labeled "Original" / "Suggested" regions), not as a purely visual strikethrough/highlight.

## 21. Data model changes

New migration: **`v17`** (current schema is `v16`, per confirmed audit evidence).

**New table — `suggested_edits`:**
`id, resume_id, target_block_type, target_block_id (nullable, null = profile-level), field_name, original_value, suggested_value, source_requirement (nullable text), status ('pending'|'accepted'|'rejected'|'edited'), created_at, resolved_at (nullable)`.

**`resumes` — additive columns:** `achievements_json (nullable text)`, `template_id (nullable text)`.

**`resume_versions` — additive columns:** `template_id (nullable text)`, `tailored_for_jd_title (nullable text)`, `tailored_for_jd_company (nullable text)`.

No existing column is altered or removed. No foreign keys added at the SQL level, consistent with the existing project-wide convention (validated at the repository layer).

## 22. Architecture changes

### 22.1 What is reused unmodified
`Resume`/library-block/`ResumeBlockRef` relational model, `ResumeCompilerService`/`ResumeSnapshot`, `DocumentTextExtractionService` (PDF/DOCX/TXT/MD), `ResumeImportParser`, `JdParser`, the deterministic core of `ResumeJdAnalyzer`, `LlmEngine`, `EmbeddingEngine`, `ModelLifecycleManager`, `LlmRequestQueue`, `ModelCatalog`/AI Model Manager, `package:pdf`/`package:printing`, `ResumeTextExportService`.

### 22.2 Template engine (new)
```
ResumeSnapshot ─┐
                ├─▶ ResumeTemplateRenderer(snapshot, ResumeTemplateSpec) ─▶ pw.Document ─▶ PDF file
ResumeTemplateSpec ─┘   (uses layout primitives + ResumeDesignTokens internally)
```
- `ResumeDesignTokens` — type scale, spacing scale, color roles, page rules. Purpose-built, not derived from `AppTheme`.
- `ResumeTemplateSpec` — `{archetypeId, tokenPresetId, displayName, atsConfidence, density, candidateType}`.
- `ResumeTemplateCatalog` — static list of ~20 specs, structured like `ModelCatalog`.
- Layout primitives (`lib/services/resume/template/layout/`) — small, reusable `pw.Widget`-building functions (header block, section heading, entry block, sidebar column, divider), each parameterized by `ResumeDesignTokens`, shared across every archetype.
- One file per archetype composing primitives into that archetype's structure.
- `ResumeTemplateRenderer` replaces the rendering internals of `ResumePdfExportService`; the existing atomic-write wrapper is preserved.

### 22.3 Suggestion pipeline (new)
```
Deterministic match (existing analyzer + new semantic tier)
        ↓
Deterministic prioritization (new)
        ↓
Per-entry bounded LLM call (new, via existing LlmRequestQueue)
        ↓
SuggestionFabricationGuard (new, deterministic post-check)
        ↓
SuggestedEdit row (pending)
        ↓
User review (accept / edit / reject)
        ↓
Accepted → merged into live ResumeBlockRef/override content, same path a manual edit takes
```
No step above bypasses the pending-review gate. This is the architectural enforcement of AC3-02.

### 22.4 Device capability (new)
`DeviceCapabilityService` (interface + real `device_info_plus`-backed implementation + fake for tests, matching the project's established real/fake service-pairing convention) feeds `ModelCatalog`'s existing `RecommendedDeviceTier` field.

### 22.5 Explicitly not built
General Search/Chat integration for resume/JD content, a persistent JD library/history, product-branding decisions on exports, licensing/monetization gating, an Academic/CV archetype and its underlying Publications/Research content types. These stay out of scope unless a future PRD revision reopens them (§22.6).

## 23. Test strategy

- **Every new deterministic/service-layer component** (semantic matcher, prioritization use case, fabrication guard, template renderer, device capability service) gets unit tests before UI work depends on it — matching the project's existing discipline.
- **Template correctness** is verified by an extraction round-trip test per template: render → extract via `PdfParser` → assert expected section headings and reading order, not merely "renders without throwing."
- **The AI-suggestion pipeline's safety property (AC3-02)** gets a dedicated test proving no code path merges LLM output into live content without passing through a `SuggestedEdit` with an explicit accept action.
- **UI/widget test coverage is mandatory for every new screen in this PRD** — the existing Resume/Career module has zero widget tests today (confirmed gap); this PRD does not repeat that gap for new screens, and Milestone 5 explicitly backfills coverage for the pre-existing ones.
- **Fake test doubles** follow the established pattern (`Fake*Engine`, wall-clock polling for async settling) already used throughout the codebase.
- No new integration/real-device test infrastructure is assumed to exist in this environment — real-device verification items are called out explicitly per milestone, matching the standing limitation already disclosed throughout this project's V2 risk register.

## 24. Acceptance criteria

V3 (as scoped by this PRD) is acceptance-complete when:

- All four journeys (§4) are reachable end-to-end and pass their milestone-level tests.
- Zero code path allows AI-generated text into a saved resume without an explicit user accept (AC3-02, verified by a dedicated test).
- All ~20 templates pass the ATS extraction round-trip test and display an accurate ATS-confidence rating.
- The feature is fully usable on the existing baseline model with the stronger model declined.
- `flutter analyze` is clean and the full test suite passes, matching the discipline already established for V2 closure.
- No resume/JD content is reachable in any log, crash report, or network call (privacy verification pass, Milestone 5).
- Widget/UI test coverage exists for every new and pre-existing Resume/Career screen (closing the confirmed historical gap).

## 25. Implementation milestones

Each milestone lists exact files to create/modify. Paths are relative to the repo root; conventions (naming, DI wiring location, test placement) match the existing codebase throughout.

---

### Milestone 0 — Data model & device foundation
*No AI, no templates yet. Closes existing gaps and lays the schema/plumbing everything else depends on.*

**New files**
- `lib/database/migrations/v17.dart`
- `lib/models/suggested_edit.dart`
- `lib/repositories/suggested_edit_repository.dart`
- `lib/services/device/device_capability_service.dart` (+ `FakeDeviceCapabilityService`)
- `test/database/migrations/v17_test.dart`
- `test/models/suggested_edit_test.dart`
- `test/repositories/suggested_edit_repository_test.dart`
- `test/services/device/device_capability_service_test.dart`

**Modified files**
- `lib/database/tables.dart` (add `SuggestedEditsTable`; extend `ResumesTable`/`ResumeVersionsTable` column constants)
- `lib/database/app_database.dart`, `lib/database/test_database.dart` (register `v17`, bump schema version)
- `lib/core/constants/app_constants.dart` (`sqliteDbVersion` bump)
- `lib/models/resume.dart` (add `achievements`, `templateId`)
- `lib/models/resume_version.dart` (add `templateId`, `tailoredForJdTitle`, `tailoredForJdCompany`)
- `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` (wire `targetRole` into the Profile card — closes the confirmed dead-field gap)
- `lib/features/career/resume/presentation/providers/resume_editor_providers.dart` (confirm/adjust the existing `updateProfile(targetRole: ...)` call site)
- `lib/features/career/resume/presentation/providers/resume_version_providers.dart` (add restore-to-draft method)
- `lib/features/career/resume/presentation/screens/resume_versions_screen.dart` (add "Restore" action)
- `lib/providers/app_providers.dart` (register `suggestedEditRepositoryProvider`, `deviceCapabilityServiceProvider`)
- `pubspec.yaml` (add `device_info_plus`)

**Dependencies:** `device_info_plus` (new).

**Tests:** migration applies cleanly over `v16` with no data loss; `SuggestedEdit` CRUD round-trip; fake-backed `DeviceCapabilityService` returns the correct tier for defined RAM thresholds; version-restore controller test; editor controller test extended to cover `targetRole`.

**Acceptance criteria:** `target_role` is settable and visible in the Editor; a saved version can be restored into an editable draft without corrupting the live composition; `DeviceCapabilityService` has a real and a fake implementation, wired through DI the same way every other service pair in this codebase is.

**Manual verification:** real-device RAM read on at least one physical Android device (standing limitation — no device available in this implementation environment).

---

### Milestone 1 — Template engine
*First 4 archetypes, replacing the single hardcoded PDF template.*

**New files**
- `lib/services/resume/template/resume_design_tokens.dart`
- `lib/services/resume/template/resume_template_spec.dart`
- `lib/services/resume/template/resume_template_catalog.dart`
- `lib/services/resume/template/layout/header_block.dart`, `section_block.dart`, `entry_block.dart`, `sidebar_column.dart`, `divider.dart`
- `lib/services/resume/template/archetypes/classic_single_column.dart`, `modern_accent_column.dart`, `two_column_sidebar.dart`, `compact_technical.dart`
- `lib/services/resume/resume_template_renderer.dart`
- `lib/features/career/resume/presentation/screens/resume_template_gallery_screen.dart`
- `lib/features/career/resume/presentation/providers/resume_template_providers.dart`
- `test/services/resume/template/` — one test file per new file above
- `test/services/resume/resume_template_renderer_test.dart` (ATS extraction round-trip)

**Modified files**
- `lib/services/resume/resume_pdf_export_service.dart` (internals refactored onto `ResumeTemplateRenderer`; atomic-write wrapper preserved; default archetype = Classic Single-Column for any version saved before this milestone)
- `lib/features/career/resume/save_resume_version_use_case.dart` (thread `templateId` through)
- `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` (template-picker entry point)
- `lib/core/router/route_paths.dart`, `lib/core/router/app_router.dart` (new gallery route)
- `lib/providers/app_providers.dart` (register new providers)

**Dependencies:** none new.

**Tests:** per-archetype render (empty/full snapshot, no throw); token-preset application; ATS round-trip extraction per archetype (heading text + reading order); atomic-write behavior re-verified on the refactored renderer; page-overflow handling for a long synthetic resume.

**Acceptance criteria:** 4 archetypes × 2 token presets (8 templates) render correctly and pass the ATS round-trip test; no archetype produces image-only text.

**Manual verification:** visual review of generated PDFs against the Enhance CV quality bar (subjective, requires human judgment).

---

### Milestone 2 — Deterministic tailoring depth
*Semantic matching, prioritization, and the analysis→editor loop-back. No LLM rewriting yet.*

**New files**
- `lib/services/career/resume_jd_semantic_matcher.dart`
- `lib/features/career/analysis/prioritize_resume_content_use_case.dart`
- `test/services/career/resume_jd_semantic_matcher_test.dart`
- `test/features/career/analysis/prioritize_resume_content_use_case_test.dart`

**Modified files**
- `lib/services/career/resume_jd_analyzer.dart` (add a `matchSource` field — `exactKeyword`/`alias`/`semanticEmbedding`/`tokenOverlap` — additive only, never downgrades an existing match)
- `lib/models/resume_jd_analysis_result.dart` (add `matchSource`)
- `lib/features/career/analysis/presentation/screens/resume_jd_analysis_screen.dart` (add a per-finding "Go to Editor" action)
- `lib/features/career/analysis/presentation/providers/resume_jd_analysis_providers.dart` (expose the navigation intent)
- `lib/providers/app_providers.dart` (wire `EmbeddingEngine` into the analyzer's construction)

**Dependencies:** none new — direct reuse of `EmbeddingEngine`.

**Tests:** semantic matcher catches a true synonym outside the 13-alias list without conflating genuinely different technologies (same non-aliasing discipline as the existing analyzer tests); prioritization ordering correctness; graceful degradation when the embedding model is unavailable; first widget test for the analysis screen, covering the new loop-back action.

**Acceptance criteria:** semantic tier is strictly additive; the analysis screen has a working, tested action per finding.

---

### Milestone 3 — AI rewrite suggestions
*The core tailoring feature and the single most safety-critical milestone.*

**New files**
- `lib/services/resume/resume_suggestion_prompt_builder.dart`
- `lib/services/resume/suggestion_fabrication_guard.dart`
- `lib/features/career/analysis/generate_resume_suggestions_use_case.dart`
- `lib/features/career/resume/accept_suggested_edit_use_case.dart`
- `lib/features/career/resume/reject_suggested_edit_use_case.dart`
- `lib/features/career/resume/presentation/screens/resume_suggestion_review_screen.dart`
- `lib/features/career/resume/presentation/providers/resume_suggestion_providers.dart`
- One test file per file above, plus `test/features/career/analysis/generate_resume_suggestions_use_case_test.dart` covering the full pipeline with a fake LLM engine.

**Modified files**
- `lib/features/career/resume/presentation/providers/resume_editor_providers.dart` (pending-suggestion count; accept/reject wiring into the live draft)
- `lib/features/career/resume/presentation/screens/resume_editor_screen.dart` (entry point into the review screen)
- `lib/providers/app_providers.dart` (register new use cases/providers)

**Dependencies:** none new.

**Tests:** prompt builder stays within the bounded-scope contract (one entry + one requirement, never whole-resume); fabrication guard correctly flags genuinely new numbers/proper nouns and does not false-positive on content present in the input; suggestion generation never writes to a block directly (dedicated architectural test per AC3-02); accept/reject use cases behave per §12.

**Acceptance criteria:** the AC3-02 test passes; rejected suggestions leave original content byte-identical (dedicated test); every suggestion is individually actionable in the review screen.

**Manual verification:** real-device per-suggestion latency check.

---

### Milestone 4 — Import depth, suggestions-while-typing, remaining templates, second model tier

**New files**
- `lib/services/resume/resume_writing_heuristics.dart`
- `lib/features/career/resume/presentation/widgets/bullet_suggestion_field.dart`
- Remaining archetype files: `executive_summary_led.dart`, `minimalist_monochrome.dart`, `entry_level_student.dart`, `government_dense.dart`, `creative_visual.dart`, plus a tenth archetype decided during this milestone (§8)
- `lib/features/career/resume/presentation/screens/resume_model_upgrade_prompt_screen.dart` (or dialog widget, implementer's choice)
- Matching test files for each above.

**Modified files**
- `lib/features/career/resume/presentation/screens/resume_import_screen.dart`, `resume_import_providers.dart` (per-entry-editable review)
- `lib/services/ai/model_catalog.dart` (second LLM-tier entry — exact model TBD during implementation; architecture does not depend on the specific choice)
- `lib/features/career/resume/presentation/screens/resume_list_screen.dart` (or a new gate widget — surfaces the model-upgrade prompt on first entry into the feature)

**Dependencies:** none new beyond Milestone 0's `device_info_plus`.

**Tests:** writing-heuristics unit tests; debounce-timing test (wall-clock polling, matching existing discipline); remaining-archetype render + ATS round-trip tests; model-upgrade-declined-still-fully-functional test (re-verifies FR3-16 directly).

**Acceptance criteria:** all ~20 templates now exist and pass the ATS round-trip test; declining the stronger model does not degrade feature availability, only suggestion quality; import review is per-entry editable.

**Manual verification:** real-device typing-latency feel-check for the debounced suggestion trigger.

---

### Milestone 5 — Hardening

- Widget/UI test backfill for every pre-existing Resume/Career screen (closing the confirmed historical zero-coverage gap) plus any new-screen gaps missed earlier.
- Real-device performance benchmarking against §19's targets.
- Privacy verification pass: a dedicated test/audit confirming no resume/JD content reaches a log, crash report, or network call.
- PDF metadata check (§14) — strip/neutralize if `package:pdf` embeds identifying metadata by default.
- ADR entries for the major decisions in this PRD (template architecture, suggestion state model, semantic-matching addition), closing this module's total prior absence of ADRs.
- `flutter analyze` clean, full suite green, release build verified — same closure discipline as V2.

**No new files are prescribed for this milestone** — its scope is verification and backfill against everything built in Milestones 0–4.

---

## Deferred / explicitly out of scope

Per the product owner's instruction, these do not block implementation and are not re-litigated here: general Search/Chat integration for resumes, a persistent JD history/library beyond a version's title/company tag, product-branding decisions on exports, licensing/monetization gating, an Academic/CV archetype and its underlying content types (Publications/Research/Teaching), and any other speculative career feature not named in this PRD.
