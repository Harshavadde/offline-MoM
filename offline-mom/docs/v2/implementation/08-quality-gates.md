# V2 Quality Gates

No feature is complete until it passes every applicable gate below. Gates are enforced at different points — some per-PR (automatable, fast, cheap to run often), some per-milestone (need a real device or real content), some per-release (need the full feature surface to be meaningful). Forcing a device-dependent check onto every PR would just make PRs slow enough that the gate gets skipped in practice — the enforcement point is chosen to keep every gate actually followed, not just theoretically required.

## 1. Architecture review

**Enforced:** per PR.
**Criteria:** the change is checked against `docs/v2/` (frozen spec) and [03-decisions.md](03-decisions.md) (resolved implementation decisions) — does it implement what those documents actually say, using the module boundaries and reuse patterns they specify? Any deviation is either a bug in the PR or grounds for a new ADR, not a silent judgment call.
**Pass bar:** reviewer (self or other) can point at the specific `docs/v2` section or ADR the change implements.

## 2. Code review

**Enforced:** per PR.
**Criteria:** matches the existing project's established code-quality bar (see V1's `docs/guides/developer-guide.md`): no comments explaining *what* code does, only non-obvious *why*; no premature abstraction; `flutter_lints` clean; naming and structure consistent with sibling modules (a new feature should look like it was written by the same team as the existing ones, not bolted on).
**Pass bar:** `flutter analyze` reports zero issues; a reviewer would not describe the code as "obviously different in style" from the surrounding codebase.

## 3. Unit tests

**Enforced:** per PR.
**Criteria:** every new use case, repository method, and non-trivial provider has test coverage following the existing fake-engine pattern (real SQLite via `sqflite_common_ffi`, fakes only for `SpeechToTextEngine`/`LlmEngine`/the new `EmbeddingEngine`/`VectorStore` interfaces — per the V2 testing strategy, Epic 7 Task 7.3). No test asserts against a code path that can't occur in production (the exact self-disclosed anti-pattern V1's own testing strategy flagged and V2 should not repeat).
**Pass bar:** `flutter test` passes; new/changed logic has new/changed tests, not just unchanged tests continuing to pass by coincidence.

## 4. Integration tests

**Enforced:** per milestone (not every PR — these are slower and often need real content, e.g. a real PDF corpus for extraction testing).
**Criteria:** the milestone's specific acceptance check from [01-master-roadmap.md](01-master-roadmap.md) is executed and its result recorded as evidence in the milestone's PR description, per [07-git-strategy.md](07-git-strategy.md)'s PR template.
**Pass bar:** the acceptance check passes exactly as specified in the roadmap — not a weaker proxy for it.

## 5. Performance checks

**Enforced:** per milestone for AI-pipeline-adjacent changes (import, chunking, embedding, chat generation); per release for the full app.
**Criteria:** no new O(N)-per-query pattern is introduced without a documented justification (the exact mistake being fixed in Ask AI's current implementation should not be reintroduced anywhere new); search/chat latency measured against NFR-13/14 in `docs/v2/09-non-functional-requirements.md`.
**Pass bar:** a workspace-chat query against a realistic seeded corpus (per NFR-16's scale) returns within the existing generation-timeout budget; document import/indexing reports progress rather than appearing frozen for any step over ~2 seconds (NFR-15).

## 6. Memory checks

**Enforced:** per milestone once more than one model can be resident at once (from M1.2 onward — see risk R-07 in [04-risk-register.md](04-risk-register.md)); per release for the full app.
**Criteria:** peak memory usage during the worst realistic case (e.g., background indexing running while the user has an active foreground chat session) measured on at least one real, non-flagship device and does not cause an OS-level app kill.
**Pass bar:** no OOM kill observed across a defined stress scenario (documented in the milestone's PR evidence); if one occurs, R-07's mitigation (serialize model loading) is applied before the milestone is considered done.

## 7. Battery checks

**Enforced:** per release (M3.1 specifically; not per-PR — this needs sustained real-device runs, not something to gate every commit on).
**Criteria:** per [01-master-roadmap.md](01-master-roadmap.md) M3.1 — documented battery drain across sustained recording+transcription, large-document import+indexing, and a multi-turn chat session, on at least a low-end and a mid-range real device.
**Pass bar:** no scenario shows battery drain disproportionate to what a comparable non-AI-heavy app would show for equivalent active-use time (a relative bar, not an absolute number, since absolute battery behavior varies enormously by device) — and no scenario shows drain continuing after the relevant screen/feature is closed (a leak, not just heavy-but-bounded use).

## 8. Accessibility

**Enforced:** per milestone for new screens; per release as a full audit (M3.2).
**Criteria:** every new screen is navigable via TalkBack in a sensible order; every interactive element has a meaningful accessible label (not a generic "button"); text respects system font-scaling without clipping/overlap; color contrast meets WCAG AA for text against its background, consistent across the existing light/dark/accent-color theming.
**Pass bar:** a TalkBack pass through the screen's primary flow (per new screen, at milestone time) plus the full-app audit at M3.2 with no critical findings outstanding.

## 9. Documentation updates

**Enforced:** per PR.
**Criteria:** [10-v2-progress.md](10-v2-progress.md)'s relevant entry is updated to reflect new status; if a spike or implementation discovery changes a "Pending Validation" ADR's assumption (per [03-decisions.md](03-decisions.md)), that ADR is amended in the same PR, not left stale; if V1's `docs/` needed a correction as a side effect of this work, it's included (per Epic 1 Feature 1.4's ongoing scope).
**Pass bar:** no PR merges leaving the progress tracker or decision log visibly out of sync with what the code now does.

## How gates compound across milestone → phase → release

A milestone passing all applicable gates does not by itself mean the *phase* is done — see [09-definition-of-done.md](09-definition-of-done.md) for how these per-change gates roll up into feature/epic/release-level completion criteria, since some gates (battery, accessibility-as-a-full-audit) are deliberately only meaningful once evaluated against the whole feature surface, not one PR at a time.
