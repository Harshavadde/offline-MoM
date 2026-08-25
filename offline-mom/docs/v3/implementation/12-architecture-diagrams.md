# V3 Architecture Diagrams

Consistent with `docs/v3/01-prd.md` §22. Every diagram below is labeled either **[Built]** — verified against actual source this session — or **[Planned]** — not yet implemented, described exactly as the PRD specifies it, never presented as if it already exists. Mirrors [docs/v2/implementation/12-architecture-diagrams.md](../../v2/implementation/12-architecture-diagrams.md)'s own "as-built vs. planned" discipline.

**Last updated:** 2026-08-22, readability/accuracy correction pass. Diagram 1 was rewritten as a short, compact index (it previously duplicated diagrams 2–6's own detail in one wide graph); a new diagram 10 ("Resume Creation Entry Points") was added showing all three ways a resume gets created side by side; the prior §10/§11 (R-7/R-10 detail diagrams) are renumbered §11/§12 to make room, content unchanged. Diagrams 2–9 reflect Milestone 5 and the Reliability-Overhaul/Product-Quality Remediation passes, unchanged in this pass. No [Planned] boxes remain in diagram 1, except where the PRD itself describes a deferred, explicitly-not-built item. R-6 and R-8 (see [10-v3-progress.md](10-v3-progress.md)) added no new component or flow — both were bugfixes/widget-placement changes to already-diagrammed screens (the gallery's thumbnail-serialization fix, `AiDisclaimer` placement) and are recorded there, not as new diagrams here.

## 1. V3 High-Level Architecture — Map, Not Detail

**Purpose of this diagram changed in this pass.** It previously tried to show every component's full detail (multi-line rationale, decision IDs, milestone tags) for all four layers in one wide graph — duplicating what diagrams 2–6 below already show in focused, full detail, and wide enough to need horizontal scrolling. It's now a compact index: short labels only, one arrow per real dependency, "see diagram N" pointers for the actual detail. Nothing below is new — every component and link already existed, just re-presented for readability.

```mermaid
flowchart TB
    subgraph Content["Content Layer"]
        Resume["Resume / library blocks"]
        Snapshot["ResumeSnapshot"]
        SuggestedEdit["SuggestedEdit"]
    end

    subgraph Template["Template Layer — see diagram 2"]
        Catalog["ResumeTemplateCatalog\n(10 archetypes, 5 in beta gallery)"]
        Renderer["ResumeTemplateRenderer"]
    end

    subgraph Tailoring["Tailoring Pipeline — see diagrams 3–5"]
        Analyzer["ResumeJdAnalyzer\n+ Semantic Matcher"]
        Prompt["AI Suggestion Generation"]
        Guard["SuggestionFabricationGuard"]
    end

    subgraph DeviceLayer["Device / Model Layer — see diagram 6"]
        DeviceCap["DeviceCapabilityService"]
        ModelCatalog["ModelCatalog"]
    end

    Resume --> Snapshot --> Renderer
    Catalog --> Renderer
    Renderer --> PDF["Exported PDF"]

    Analyzer --> Prompt --> Guard --> SuggestedEdit
    SuggestedEdit -->|"accept only"| Resume

    DeviceCap -.->|"tier recommendation"| ModelCatalog
    DeviceCap -.->|"low-tier: sequence\nbefore LLM pass"| Prompt
```

**Where each layer's full detail lives:** Content/Template → diagram 2. Tailoring → diagrams 3, 4, 5. Device/Model → diagram 6. Milestone-by-milestone build history → diagram 7. Three ways a resume actually gets created (blank, from a JD, Beginner Resume) → diagram 10.

## 2. Resume Content → Compiler → Template Renderer → PDF [Built, M1]

```mermaid
flowchart LR
    Live["Live ResumeBlockRef\ncomposition\n[Built - pre-existing]"] --> Compiler["ResumeCompilerService.compile()\n[Built - pre-existing,\nnever template-aware, D-02]"]
    Compiler --> Snapshot["ResumeSnapshot\n[Built - pre-existing]"]
    Snapshot --> Renderer["ResumeTemplateRenderer\n[Built - M1]"]
    Spec["ResumeTemplateSpec\n(archetype + token preset,\ndefault = Classic Single-Column\nfor pre-M1 versions)\n[Built - M1]"] --> Renderer
    Renderer --> Doc["pw.Document\n(pw.MultiPage, automatic\npage-break - RV3-11 mitigated)"]
    Doc --> File["PDF file\n(atomic temp-then-rename,\nreused from ResumePdfExportService)"]
```

**Note:** the Two-Column Sidebar archetype's internal composition uses `package:pdf`'s `Partitions`/`Partition` (not `pw.Row`/`pw.Expanded`) specifically for cross-page spanning correctness — see D-M1-02, [03-decisions.md](03-decisions.md).

## 3. JD Tailoring Pipeline — Deterministic + Semantic Matching + Prioritization [Built, M2]

```mermaid
flowchart TB
    JD["Imported JD\n(session-only, never persisted)\n[Built - pre-existing JdParser]"] --> Parse["JdParser\n[Built - pre-existing]"]
    Resume["ResumeSnapshot\n[Built - pre-existing]"] --> Match

    Parse --> Match["ResumeJdAnalyzer:\nexact / alias / tokenOverlap\n[Built - pre-existing]"]
    Match -->|"still missing?"| Semantic["ResumeJdSemanticMatcher\n(additive only - never downgrades\nan existing exact/partial match;\ndegrades to null on embedding\nfailure, AC3-05)\n[Built - M2]"]
    Semantic --> Result["ResumeJdAnalysisResult\n(skillMatches with matchSource,\nexperienceCheck, educationChecks,\ncertificationChecks)\n[Built - M2]"]
    Result --> Prioritize["PrioritizeResumeContentUseCase\n(re-ranks Experience/Projects/Skills\nby match density; Education/\nCertifications untouched, D-M2-03)\n[Built - M2]"]
    Result --> GoToEditor["Per-finding 'Go to Editor' action\n[Built - M2]"]
```

## 4. AI Suggestion Generation → Fabrication Flag → Review [Built, M3]

```mermaid
flowchart TB
    Result["ResumeJdAnalysisResult\n(MatchLevel.partial entries)\n[Built - M2]"] --> Gen["GenerateResumeSuggestionsUseCase\n(one bounded call per eligible entry -\nfirst matching requirement only, D-M3-02)\n[Built - M3]"]
    Gen --> Prompt["ResumeSuggestionPromptBuilder.build()\n(pure, stateless, one entry +\none requirement, AC3-04)\n[Built - M3]"]
    Prompt --> Queue["LlmRequestQueue.enqueue(\n  isForeground: true,\n  run: LlmEngine.generateFromPrompt)\n[Built - M3, D-M3-01]"]
    Queue -->|"success"| Parse["Parse raw text into lines;\nreject empty/malformed/unchanged\n[Built - M3]"]
    Queue -->|"failure (model unavailable,\ntimeout, etc.) - AC3-05"| Skip["Entry produces no suggestion;\nbatch continues\n(currently silent - RV3-16)"]
    Parse --> Insert["SuggestedEditRepository.insert()\nstatus = pending\n[Built - M3, first real writer]"]

    Insert -.->|"generation NEVER calls\nResumeBlockRepository.setOverride\n- verified by dedicated AC3-02 test"| Blocked(["resume_blocks / library-block row"])

    Insert --> List["suggestionReviewListProvider:\nfetch pending + lazily compute\nSuggestionFabricationGuard.check()\nper item [Built - M3]"]
    List --> Screen["ResumeSuggestionReviewScreen\n(original / suggested / JD requirement /\n'Review carefully' warning if flagged /\nAiDisclaimer widget - R-6)\n[Built - M3, disclaimer added R-6]"]

    style Blocked fill:#fee,stroke:#c00
```

## 5. Accept / Reject Lifecycle [Built, M3] — the architectural enforcement of AC3-02

```mermaid
flowchart LR
    Screen["ResumeSuggestionReviewScreen\n[Built - M3]"] -->|Accept| Accept["AcceptSuggestedEditUseCase\n[Built - M3]"]
    Screen -->|Reject| Reject["RejectSuggestedEditUseCase\n[Built - M3]"]

    Accept --> Check1{"Still pending?\n(duplicate-accept guard)"}
    Check1 -->|No| Throw1(["SuggestedEditNotPendingException"])
    Check1 -->|Yes| Check2{"Target block still\nattached to resume?"}
    Check2 -->|No| Throw2(["SuggestedEditNoLongerApplicableException"])
    Check2 -->|Yes| Check3{"Current compiled content\n(via real ResumeCompilerService)\nstill == originalValue?"}
    Check3 -->|No, changed since generation| Throw3(["SuggestedEditNoLongerApplicableException\n(never silently overwrites\na newer edit)"])
    Check3 -->|Yes| Apply["ResumeBlockRepository.setOverride()\n- the SAME path a manual Editor\nedit already uses"]
    Apply --> Resolve1["SuggestedEditRepository.resolve()\nstatus = accepted"]

    Reject --> RCheck{"Already rejected?"}
    RCheck -->|Yes| Idempotent(["Return unchanged\n(idempotent)"])
    RCheck -->|"No, pending"| Resolve2["SuggestedEditRepository.resolve()\nstatus = rejected\n(no resume content touched)"]
    RCheck -->|"No, already accepted"| Throw4(["SuggestedEditNotPendingException"])

    style Apply fill:#efe,stroke:#0a0
    style Resolve2 fill:#eef,stroke:#06c
```

**Fabrication guard is not part of either flow above** — confirmed by direct inspection, `SuggestionFabricationGuard` is not imported by `accept_suggested_edit_use_case.dart` or `generate_resume_suggestions_use_case.dart`. It only ever runs inside `suggestionReviewListProvider` (diagram 4), purely to compute what the review screen displays.

## 6. Model / Device Sequencing — [Built, M5]

```mermaid
flowchart TB
    Start(["GenerateResumeSuggestionsUseCase.call()\nbegins"]) --> Analyze["Internal embedding-backed\nanalysis pass (_analyzer.analyze())\n[Built - M2/M3]"]
    Analyze --> CheckTier{"DeviceCapabilityService\n.recommendedTierForRamMb()\n[Built - M0, consumed - M5]"}
    CheckTier -->|"highRamDevice (>=5500MB)"| Concurrent["Embedding model stays resident;\nLLM pass begins immediately\n[Built - M5]"]
    CheckTier -->|"anyModernPhone (<5500MB),\nincluding unknown/null RAM"| Sequenced["ModelLifecycleManager\n.unmanagedUnload(ModelKind.embedding)\nbefore the LLM pass begins\n[Built - M5, D-M5-01]"]
    Concurrent --> Gen["LLM generation loop\n[Built - M3]"]
    Sequenced --> Gen
    Gen --> Done(["Suggestions generated -\nidentical output regardless\nof tier, verified by test"])
```

**As built today:** `DeviceCapabilityService` (M0) is now consumed by `GenerateResumeSuggestionsUseCase._releaseEmbeddingModelIfLowTier()` (M5) — the single point in the codebase where the embedding-backed analysis pass and the LLM-backed generation loop run back-to-back in one function call with no user-interaction gap, making it the correct, sufficient insertion point (D-M5-01). Verified by 5 dedicated tests in `generate_resume_suggestions_use_case_test.dart`. **Not yet verified under real memory pressure on an actual low-RAM device** — RV3-12 remains open; this diagram reflects the code-level implementation, not a real-device benchmark.

## 7. V3 Milestone Dependency Flow

```mermaid
flowchart TB
    M0["M0 - Data model & device foundation\n[COMPLETE - dd4a03d, 0e47848]"] --> M1["M1 - Template engine\n[COMPLETE - d67528a]"]
    M1 --> M2["M2 - Deterministic tailoring depth\n[COMPLETE - 30bf491]"]
    M2 --> M3["M3 - AI rewrite suggestions\n[COMPLETE - 2f92bba]"]
    M3 --> M4["M4 - Import depth, suggestions-while-typing,\nbeta template catalog, second model tier\n[COMPLETE - 7219ac5]"]
    M4 --> M5["M5 - Beta hardening\n[COMPLETE - see 07-git-strategy.md]"]

    M0 -.->|"schema: suggested_edits,\ntemplate_id columns"| M3
    M0 -.->|"schema: template_id columns"| M1
    M0 -.->|"DeviceCapabilityService"| M4
    M0 -.->|"DeviceCapabilityService,\nModelLifecycleManager"| M5
    M1 -.->|"layout primitives"| M4
    M2 -.->|"which entries are\nrelevant-but-improvable"| M3
    M3 -.->|"GenerateResumeSuggestionsUseCase\n(RAM-sequencing insertion point)"| M5

    style M0 fill:#d4edda,stroke:#28a745
    style M1 fill:#d4edda,stroke:#28a745
    style M2 fill:#d4edda,stroke:#28a745
    style M3 fill:#d4edda,stroke:#28a745
    style M4 fill:#d4edda,stroke:#28a745
    style M5 fill:#d4edda,stroke:#28a745
```

**Beta-readiness note:** every box above is [COMPLETE] in the sense of "that milestone's own scoped work is done, tested, and gated" — this is not the same claim as "every real-device or human-judgment verification has occurred." See [09-definition-of-done.md](09-definition-of-done.md) for the three specific categories (real-device, human-visual, widget-test breadth) still disclosed as outstanding after Milestone 5.

## 8. Offline Readiness Check — [Built, Reliability-Overhaul Pass]

```mermaid
flowchart LR
    A["OfflineReadinessScreen\n(Settings)"] --> B["offlineReadinessReportProvider\n(autoDispose FutureProvider)"]
    B --> C["OfflineReadinessService.evaluate()"]
    C --> D["InstalledModelRepository\n.getActiveForKind(llm/embedding/speechToText)"]
    C --> E["Static, network-audit-backed checks:\nlocal DB / on-device inference /\nno network required for inference"]
    D --> F["OfflineReadinessReport\n(per-check pass/fail + detail)"]
    E --> F
    F --> A
```

A capability check, not a live connectivity probe — `D` reads the same `InstalledModel.isActive` rows the AI Model Manager itself reads (never a fresh guess), and `E` asserts facts directly backed by a real code audit (no `http`/`dio` dependency, no analytics SDK, the only real network code is the two model-download paths — `HttpModelDownloadService` and `llamadart`'s own downloader). The separate, pre-existing `hasInternetConnection()` utility (a real DNS-lookup connectivity probe) is unrelated and unchanged — it gates the profession-setup onboarding download flow only, not this check.

## 9. Import Completeness Verification — [Built, Reliability-Overhaul Pass]

```mermaid
flowchart TD
    A["Raw resume text"] --> B["ResumeImportParser.parse()"]
    B --> C["Structured entries\n(Experience/Education/Projects/\nCertifications/Skills/CustomSections/Links)"]
    B --> D["unclassifiedText\n(flagged for manual review)"]
    B --> E["ResumeImportCompletenessReport\n(per-section Source/Imported/Missing counts,\nreusing the same block-splitting\nthe parser already did)"]
    C --> E
    D --> E
    E --> F{isComplete?}
    F -->|"missingCount == 0\n(the guaranteed invariant)"| G["Draft attached to\nParsedResumeDraft.completeness"]
```

`E` never re-derives "how many entries should exist" independently (which would risk a second, drifting parser) — it reuses `ResumeImportParser`'s own internal block count and confirms every block reached either `C` or `D`, never neither. See D-M8-01, [03-decisions.md](03-decisions.md).

## 10. Resume Creation Entry Points [Built]

Three separate ways to start a resume from `ResumeListScreen` (`lib/features/career/resume/presentation/screens/resume_list_screen.dart`), all converging on the same Editor and export pipeline — no parallel resume architecture anywhere. This diagram exists specifically to show all three side by side, since diagrams 11 and 12 below each drill into one of them individually.

```mermaid
flowchart TB
    List["ResumeListScreen"]
    List -->|"FAB: New resume"| Blank["Blank resume\n(title only)\n[pre-existing]"]
    List -->|"AppBar menu item:\nCreate resume from\na Job Description"| Jd["JdToResumeScreen\n[R-7, detail: diagram 11]"]
    List -->|"card: Create a\nBeginner Resume"| Beginner["BeginnerResumeScreen\n[R-10, detail: diagram 12]"]

    Blank --> Editor["ResumeEditorScreen\n(progressive wizard, R-7)"]
    Jd --> Analysis["ResumeJdAnalysisScreen\n(initialResumeId set,\nauto-analyzes - diagram 3)"]
    Analysis -->|"Go to editor"| Editor

    Beginner -->|"no JD supplied"| TemplatePicker["BeginnerResumeTemplateScreen\n[R-10]"]
    Beginner -->|"real JD pasted/imported"| Analysis
    TemplatePicker --> Editor

    Editor --> Renderer["ResumeTemplateRenderer -> PDF\n(diagram 2)"]
```

The "existing resume + JD" tailoring flow (pick an already-created resume, then analyze it against a JD) is the same `ResumeJdAnalysisScreen`/diagram-3 pipeline, just entered directly rather than via `initialResumeId` — not a fourth path, the same `Analysis` node above.

## 11. R-7 Additions — Progressive Resume Wizard & "Create Resume from a Job Description" [Built]

**Progressive wizard.** `ResumeEditorScreen`'s `_EditorBody` (`lib/features/career/resume/presentation/screens/resume_editor_screen.dart`) changed from one continuous scroll of all 7 sections to a step-at-a-time wizard (Profile → Experience → Education → Projects → Certifications → Skills → Custom → Review), with a tappable step bar and progress indicator. This is presentation-only: every field, every section widget (`_ProfileCard`/`_ExperienceSection`/etc.), and `ResumeEditorController`'s state/persistence are unchanged — the Review step renders every section together, identical to the old layout, as a final look before saving. No field was removed to make this shorter.

**"Create resume from a Job Description"** (`lib/features/career/jd/presentation/screens/jd_to_resume_screen.dart`, `lib/features/career/jd/create_resume_from_jd_use_case.dart`) is a second, brand-new-resume entry point alongside the pre-existing "pick an existing resume, then analyze it against a JD" flow (§3 above):

```mermaid
flowchart TB
    Paste["Paste JD text\n(JdParser.parse(), no file needed)\nor import a file\n(reuses ImportJdUseCase)"] --> Review["Review parsed JD\n(same JdParser output as §3)"]
    Review --> Create["CreateResumeFromJdUseCase\n[Built - R-7]"]
    Create --> Profile["My Profile\n(getProfile() - throws NoProfileException\nif none set up yet)"]
    Profile --> FromProfile["CreateResumeFromProfileUseCase\n(ALL profile blocks attached -\nsame blocks, never copied/invented)\n[Built - pre-existing, M-Validation]"]
    FromProfile --> NewResume["New, titled resume\n('<JD title> at <JD company>')"]
    NewResume --> Analysis["ResumeJdAnalysisScreen\n(initialResumeId set -\nskips the resume picker,\nanalyze() runs automatically)\n[Built - R-7]"]
    Analysis --> Rest["Strong/Partial/Missing matches,\nGenerate AI suggestions,\nGo to editor, template, export\n[Built - pre-existing, §3/§4/§5]"]
```

Nothing here is a new resume-creation or JD-parsing mechanism — `CreateResumeFromJdUseCase` is a thin composition of the already-built `CreateResumeFromProfileUseCase` and the already-built `JdParser`. Content is not reordered by JD relevance at creation time (`PrioritizeResumeContentUseCase` needs match evidence that doesn't exist until analysis has run once) — the created resume goes straight into the existing analysis screen instead, which is where a user already sees job requirements vs. their own experience vs. AI-suggested tailoring.

`ResumeJdAnalysisScreen` also gained a small, always-visible header (`_ResumeAndJdHeader`) naming both the resume and the job description together on the results screen, so which resume is being tailored is never only implied by which list item was tapped.

## 12. R-10 Addition — Beginner Resume Flow [Built]

**"Create a Beginner Resume"** (`lib/features/career/resume/presentation/screens/beginner_resume_screen.dart`) is a short, progressive flow for a user with little/no experience or projects (fresh graduates, first-time job seekers) - a clearly visible card on the Resume list screen, the same prominence as "My Profile," not an icon-only popup item.

```mermaid
flowchart TB
    Basics["Step: Basic details\n(name required, rest optional)"] --> Role["Step: Target role"]
    Role --> RoleA["A. Search/pick a role\nRoleCategoryCatalog (14 curated entries)\n[Built - R-10, deterministic, no AI/network]"]
    Role --> RoleB["B. Paste/import a JD"]
    RoleB --> Classify{"looksLikeJobTitle()?\n[Built - R-10]"}
    Classify -->|"short title"| RoleCategoryMatcher["RoleCategoryMatcher.match()\n[Built - R-10, exact/alias/token-overlap,\nfalls back to General Fresher]"]
    Classify -->|"real JD text/file"| JdImportController["JdImportController.parseText()/pickAndParse()\n[Built - pre-existing, R-7]"]
    RoleCategoryMatcher --> RoleA
    RoleA --> Education["Step: Education (optional)"]
    JdImportController --> Education
    Education --> Experience["Step: Experience (optional,\ninternship/part-time/volunteer)"]
    Experience --> Skills["Step: Skills\n(own skills + role-suggested,\nremovable, never auto-claimed)"]
    Skills --> Languages["Step: Languages/Certifications/\nAchievements (all optional)"]
    Languages --> Review["Step: Review\nsummary via buildBeginnerResumeSummary()\n[Built - R-10, deterministic]\n+ optional BulletSuggestionField polish\n+ AiDisclaimer widget\n[Built - pre-existing, R-7/R-8, the ONLY AI in this flow]"]
    Review --> Generate["CreateBeginnerResumeUseCase\n[Built - R-10]"]
    Generate --> NewResume["New Resume + attached blocks\n(only what was actually supplied -\nno fabricated projects/experience/\ncertifications)"]
    NewResume -->|"no JD"| TemplatePicker["BeginnerResumeTemplateScreen\n(entryLevelStudent/classicSingleColumn/\nmodernAccentColumn only)\n[Built - R-10, reuses templateResumeThumbnailProvider\n+ ResumeTemplateSelectionController unchanged]"]
    NewResume -->|"real JD was pasted"| JdAnalysis["ResumeJdAnalysisScreen(initialResumeId: ...)\n[Built - pre-existing, R-7 mechanism, unchanged]"]
    TemplatePicker --> Editor["ResumeEditorScreen\n[Built - pre-existing, unmodified]"]
    JdAnalysis -->|"Go to editor"| Editor
```

**No parallel resume architecture**: `CreateBeginnerResumeUseCase` writes through the exact same `Resume`/`ResumeBlockRef`/block repositories every other resume-creation path uses (`CreateResumeFromProfileUseCase`, `CreateResumeFromJdUseCase`). The professional summary reuses the existing "Summary" `CustomSectionBlock` convention (`resume_content_plan_builder.dart`'s `isSummarySection`); Languages reuses the same generic `CustomSectionBlock` mechanism the codebase already names "Languages" as an intended use case for. No new database table, model, PDF generator, or rendering path was added.

**No fabrication, by construction**: every block is only created if the corresponding input was actually non-blank (see `CreateBeginnerResumeUseCase`'s own doc comment); `RoleCategory.suggestedSkills` only ever becomes a real `SkillEntry` if the screen's `confirmedSkills` list includes it (a suggestion the user removed is never attached); the generated summary's only role-catalog input is `RoleCategory.summaryFocus` (a phrase describing the *role*, never a claim about the person).

**Offline**: `RoleCategoryCatalog`/`RoleCategoryMatcher`/`looksLikeJobTitle` are static Dart data and pure functions - no network, no AI, no database read. The only AI touchpoint in the entire flow is the Review step's optional `BulletSuggestionField` polish on the summary text, reusing the exact same Tier-2 AI infrastructure `bullet_suggestion_field.dart` already provides elsewhere - the flow completes and produces a full resume with zero AI model installed.
