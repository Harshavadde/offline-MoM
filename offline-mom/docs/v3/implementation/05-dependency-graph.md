# V3 Milestone & Technical Dependency Graph

Companion to [01-master-roadmap.md](01-master-roadmap.md) (the milestone timeline) and [06-module-order.md](06-module-order.md) (the in-milestone build order this graph justifies).

**Last updated:** 2026-08-10, Milestone 5 finalized (all five milestones complete). Every dependency below is verified against actual `import` statements/constructor signatures in the current repository, not assumed from the PRD's plan.

## Milestone sequence (as actually executed)

```
M0 (Data model & device foundation)      ✅ dd4a03d
 ↓
M1 (Template engine)                     ✅ d67528a
 ↓
M2 (Deterministic tailoring depth)       ✅ 30bf491
 ↓
M3 (AI rewrite suggestions)              ✅ 2f92bba
 ↓
M4 (Import depth, suggestions-while-typing, beta template catalog, second model tier)   ✅ 7219ac5
 ↓
M5 (Beta hardening)                       ✅ (see 07-git-strategy.md for commit hash)
```

This is the PRD's own §25 ordering — linear, not parallelized. Each milestone's acceptance criteria assumed the previous one's deliverables already existed, and each was in fact built in this order, confirmed by `git log`.

## A. Resume content → template/rendering (Milestones 0–1, unchanged by M2/M3)

```
Resume + ResumeBlockRef (live composition)     [pre-existing]
        │
        ▼
ResumeCompilerService.compile()                [pre-existing, never template-aware — D-02]
        │
        ▼
ResumeSnapshot                                  [pre-existing]
        │
        ├──▶ ResumeContentPlanBuilder ──▶ ResumeContentPlan   [M1 — shared ordering model, D-M1-01]
        │            │
        │            ▼
        │     content_line_renderer.dart + layout primitives  [M1]
        │            │
        ▼            ▼
ResumeTemplateSpec ──▶ ResumeTemplateRenderer ──▶ pw.Document ──▶ PDF file    [M1]
(from ResumeTemplateCatalog,                      (atomic temp-then-rename,
 4 archetypes × 2 presets = 8 entries)              preserved from the pre-existing
                                                     ResumePdfExportService)
```

## B. JD analysis → matching → prioritization (Milestone 2)

```
Imported JD (session-only, never persisted)     [pre-existing JdParser]
        │
        ▼
ResumeJdAnalyzer.analyze(snapshot, jd)          [pre-existing deterministic core]
        │
        ├─ exact / alias / tokenOverlap match ──────────────┐
        │   (MatchSource.exactKeyword/.alias/.tokenOverlap)  │
        │                                                     ▼
        └─ for each still-`missing` requirement:      ResumeJdAnalysisResult
           ResumeJdSemanticMatcher.findBestMatch()    (skillMatches, matchSource
           via EmbeddingEngine ──▶ MatchLevel.partial  per match, experienceCheck,
           + MatchSource.semanticEmbedding             educationChecks,
           (additive only — never touches an           certificationChecks)
           existing exact/partial match; catches                │
           its own failure, returns null on error)              │
                                                                  ▼
                                          PrioritizeResumeContentUseCase
                                          (re-ranks Experience/Projects/Skills
                                          by requirement-match density;
                                          Education/Certifications untouched)
```

## C. AI suggestion generation → fabrication flag → accept/reject (Milestone 3)

```
ResumeJdAnalysisResult.skillMatches (MatchLevel.partial entries only)
        │
        ▼
GenerateResumeSuggestionsUseCase
        │   - re-derives which entry (experience/education/project)
        │     each partial match's evidence text belongs to
        │   - one bounded call per eligible entry (its own bullets/
        │     details + its one associated JD requirement)
        │
        ▼
ResumeSuggestionPromptBuilder.build()   (pure, stateless — system +
        │                                 user prompt, fabrication-ban
        │                                 instructions baked in)
        ▼
LlmRequestQueue.enqueue(isForeground: true,
        run: () => LlmEngine.generateFromPrompt(systemPrompt, userPrompt))
        │
        │   (any failure here — model unavailable/unloaded/timeout —
        │    is caught per-entry; that entry produces no suggestion,
        │    the rest of the batch continues — AC3-05)
        ▼
Raw model text → parsed into lines → compared against original text
        │
        │   (empty/malformed/unchanged output → no suggestion created;
        │    NOT the fabrication guard's job — a basic-validity check)
        ▼
SuggestedEditRepository.insert(SuggestedEdit(status: pending, ...))
        │
        │   ═══ generation never calls ResumeBlockRepository.setOverride
        │       or any resume-mutating method — verified by a dedicated
        │       test (AC3-02) ═══
        ▼
resume_suggestion_providers.dart: suggestionReviewListProvider
        │
        │   - fetches every pending SuggestedEdit for the resume
        │   - lazily computes SuggestionFabricationGuard.check(original,
        │     suggested) per item, purely for display — never persisted,
        │     never blocks anything (D-M3-04, flag-only)
        ▼
ResumeSuggestionReviewScreen (shows original/suggested/JD requirement/
        │                     "Review carefully" warning if flagged)
        │
        ├──▶ RejectSuggestedEditUseCase ──▶ status: rejected
        │    (status-only change; never touches resume content;
        │    idempotent if already rejected)
        │
        └──▶ AcceptSuggestedEditUseCase
                 - re-validates: still pending, target block still
                   attached, current compiled content still matches
                   originalValue exactly (via the real
                   ResumeCompilerService, not a cached value)
                 - ResumeBlockRepository.setOverride(...)   ← the SAME
                   path ResumeEditorController.setBlockOverride uses
                   for a manual edit (FR3-10)
                 - status: accepted
```

## Existing infrastructure V2/pre-V3 reused, and by whom

| Dependency | Reused (unmodified) by | Notes |
|---|---|---|
| `EmbeddingEngine` | M2 (`ResumeJdSemanticMatcher`) | Same shared instance as Documents/Knowledge indexing — no second embedding model |
| `LlmEngine` | M3 (`GenerateResumeSuggestionsUseCase`) | Interface gained one new method, `generateFromPrompt` (D-M3-07) — every other method untouched |
| `LlmRequestQueue` | M3 (`GenerateResumeSuggestionsUseCase`) | Identical `enqueue(LlmQueueRequest(isForeground: true, run: ...))` pattern already used by `AskAboutMeetingsUseCase` |
| `ModelLifecycleManager` | M2 (via `embeddingEngineProvider`), M3 (via `llmEngineProvider`) | No new lifecycle logic added |
| `ModelCatalog`/AI Model Manager | M2/M3 (indirectly, via the engines above) | No new catalog entry added yet — that's Milestone 4's second-tier LLM |
| `ResumeCompilerService` | M1 (renderer input), M2 (analysis input), M3 (generation input + Accept's re-validation) | Never became template- or AI-aware — still a pure `(Resume, List<ResumeBlockRef>) → ResumeSnapshot` function |
| `ResumeBlockRepository` | M3 (`AcceptSuggestedEditUseCase.setOverride`) | The only new *writer* — `setOverride` itself is pre-existing, already used by the Editor's manual-edit path |
| `SuggestedEditRepository` | M3 (first real writer: `GenerateResumeSuggestionsUseCase.insert`, `Accept`/`RejectSuggestedEditUseCase.resolve`) | Existed since M0 as schema/CRUD only — M3 is what actually exercises it in production code |
| `DeviceCapabilityService` | M4 (model-upgrade-prompt screen, tier recommendation), M5 (`GenerateResumeSuggestionsUseCase`'s RAM-tier sequencing, D-M5-01) | Existed unconsumed since M0 through M3 (RV3-04) — now has two real consumers, both additive, no new concurrency architecture |

## What does NOT depend on what (explicitly, to avoid over-claiming)

- **M1's template engine does not depend on M2 or M3.** The renderer accepts `(ResumeSnapshot, ResumeTemplateSpec)` only — confirmed, no JD/suggestion-shaped parameter anywhere in `resume_template_renderer.dart`.
- **M2's deterministic core does not depend on any LLM.** Only its semantic tier touches `EmbeddingEngine`; `ResumeJdAnalyzer`'s keyword/alias matching needs nothing new (unchanged from pre-V3).
- **M3's generation does not depend on M1's template engine at all.** Suggestions operate on raw `ResumeSnapshot` bullet/detail text, never on rendered/template-specific output.
- **M4's 6 additional archetypes do not depend on M2 or M3** — they extend M1's existing tokens/primitives only.
- **M5 adds no new technical coupling of its own** — it verifies/backfills M0–M4, and its one functional change (RAM sequencing) is inserted into M3's existing `GenerateResumeSuggestionsUseCase` rather than introducing a new component with its own dependencies.
