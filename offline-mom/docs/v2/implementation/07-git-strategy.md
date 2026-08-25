# V2 Git Strategy

## Standing rule, restated because it overrides any generic convention below

**No commit in this repository ever carries a "Co-Authored-By" trailer for an AI assistant, or any similar AI-attribution trailer.** Commit authorship is the human maintainer's name only. This has been an explicit, firm, standing instruction for this project and applies to every commit produced during V2 implementation without exception, regardless of what tooling produced the diff.

## Branch strategy

Trunk-based, matching the project's actual size and team (currently a solo maintainer working with AI-assisted implementation, not a large team needing GitFlow's overhead):

- **`main`** is always in a releasable state — every commit on `main` passes the Phase-appropriate quality gates in [08-quality-gates.md](08-quality-gates.md). Nothing broken is ever merged to `main` "temporarily."
- **Milestone branches**: one short-lived branch per roadmap milestone (see [01-master-roadmap.md](01-master-roadmap.md)), named `v2/<milestone-id>-<short-slug>` — e.g. `v2/m0.2-llm-request-queue`, `v2/m1.0-embedding-spike`. A milestone branch is deleted once merged; it is not a long-lived integration branch.
- **No separate `develop` branch.** With milestones already scoped to "ends in a working, testable app" (per the master roadmap's own requirement), an intermediate integration branch would just be a second copy of `main` with extra ceremony and no corresponding benefit at this project's scale.
- Spikes (M1.0) are branched and committed like any other milestone, explicitly labeled as spike-quality in the commit message (see Commit strategy) rather than hidden or done outside version control — a spike that discovers something important needs to be reviewable history, not a lost afternoon.

## Commit strategy

- **Conventional Commits prefixes**, adopted starting with V2 work specifically (not retroactively applied to V1 history): `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `perf:`. Scope tag matches the Epic/module where useful, e.g. `feat(documents): add DOCX text extraction`.
- Every commit message body explains **why**, not just what — continuing this project's existing, already-strong discipline (visible throughout V1's commit history) of doc-comment-quality rationale in commit messages, not just diff summaries.
- One logical change per commit. A milestone branch may have several commits; it does not need to be squashed into one, as long as each commit on it builds and (where applicable) passes tests — `git bisect`-friendliness is a real, cheap property to preserve.
- **No `--no-verify`, no skipped hooks**, consistent with this project's existing standing practice.

## Pull request strategy

Even for a solo-maintainer project, every milestone branch goes through a PR before merging to `main` — not for a second human reviewer necessarily, but because the PR description *is* where the milestone's acceptance check (per [01-master-roadmap.md](01-master-roadmap.md)) gets recorded as evidence, and where [08-quality-gates.md](08-quality-gates.md)'s checklist gets explicitly confirmed rather than assumed. A PR description template:

```
## Milestone
(e.g. M1.2 — Chunking, embedding, vector storage)

## What changed

## Acceptance check evidence
(the specific check from 01-master-roadmap.md, with proof it passed)

## Quality gates
- [ ] Architecture review (self or reviewer) against docs/v2/
- [ ] flutter analyze clean
- [ ] flutter test passing, new tests added for new behavior
- [ ] Integration/manual check where applicable
- [ ] Performance/memory/battery check where applicable (per 08-quality-gates.md)
- [ ] Accessibility check where applicable
- [ ] Documentation updated (10-v2-progress.md status, ADR amendments if a spike changed a pending decision)
```

## Tagging

Every milestone in [01-master-roadmap.md](01-master-roadmap.md) has a corresponding git tag, applied on `main` immediately after that milestone's PR merges — this is what makes "each phase ends in a Git commit milestone" concretely true rather than aspirational. Tags follow semantic versioning with pre-release identifiers:

- `v2.0.0-alpha.N` — Phase 0 and Phase 1 milestones (foundation + infrastructure; not yet feature-complete).
- `v2.0.0-beta.N` — Phase 2 milestones (feature-complete workspace surface, not yet performance/accessibility/monetization-hardened).
- `v2.0.0-rc.N` — Phase 3 milestones short of general availability.
- `v2.0.0` — the Phase 3 exit tag, submittable to the Play Store.

The exact tag-to-milestone mapping is maintained in [01-master-roadmap.md](01-master-roadmap.md) itself (each milestone states its tag) so there's one place to look, not two documents that can drift apart.

## Release naming

Internal builds use the version tag directly (`v2.0.0-beta.3`) — no separate marketing codename is needed for engineering communication. If a public-facing release name is wanted for the eventual Play Store listing (e.g., "OfflineMoMAI 2.0 — Workspace"), that's a marketing decision made at M3.5, not an engineering concern this document needs to settle.

## Version numbering — how this maps onto the existing Android versioning

V1 already uses `pubspec.yaml`'s `version: 1.0.0+N` (currently `+22` as of this writing), where `N` is the Android `versionCode` and must only ever increase, per Play Store's own hard requirement — this is non-negotiable and V2 does not reset it. Mapping:

- The `X.Y.Z` part of `pubspec.yaml`'s version becomes `2.0.0` once V2 development starts in earnest (at M1.0, when the app genuinely begins diverging from what "V1" describes) — pre-release suffixes (`-alpha.N` etc.) are not valid in `pubspec.yaml`'s build-name field the same way they are in a git tag, so the git tag is the source of truth for phase/milestone tracking, while `pubspec.yaml`'s plain `2.0.0` (or `2.x.0` if a phase boundary warrants a minor bump — e.g. `2.1.0` at Phase 2's start) reflects the broader release line.
- The `+N` build number continues incrementing exactly as it always has, once per release build cut, regardless of which git tag or `pubspec.yaml` version-name it corresponds to — this is purely an ever-increasing counter and should never be reasoned about as meaningful beyond that.
- Each milestone tag in [01-master-roadmap.md](01-master-roadmap.md) corresponds to one specific `+N` build that was actually built and (at minimum, internally) tested — the mapping between git tag and build number should be recorded in [10-v2-progress.md](10-v2-progress.md) as work proceeds, since it's the kind of fact that's easy to reconstruct while building and tedious to reconstruct after the fact.

## Milestones (as git artifacts, summarizing the above)

Every roadmap milestone = one milestone branch → one PR → one merge to `main` → one git tag → one entry updated in [10-v2-progress.md](10-v2-progress.md). No milestone is considered complete without all five of these existing.
