# V3 Git Strategy

Restates the standing project-wide rule first, because it overrides any generic convention below: **no commit in this repository ever carries a "Co-Authored-By" trailer for an AI assistant, or any similar AI-attribution trailer.** Commit authorship is the human maintainer's name only — unchanged from V2's own [07-git-strategy.md](../../v2/implementation/07-git-strategy.md). Confirmed: none of the commits below carry any such trailer.

## Current repository reality (verified this session via `git log --oneline --decorate` and `git ls-remote origin refs/heads/main`)

- Branch: `main`, tracking `origin/main`.
- `origin/main` at the start of this Milestone 5 pass: `7219ac5 feat(v3): finalize milestone 4 beta resume templates`.
- Working tree: Milestone 5's implementation, tests, and documentation are complete and staged for exactly one commit, `feat(v3): complete milestone 5 beta hardening` — see the Milestone 5 row below once committed and pushed.

## V3 commit history (verified, in order)

| Commit | Type | Contents | Pushed? |
|---|---|---|---|
| `5a06f89` | `docs:` | `docs/v3/01-prd.md` only | ✅ Yes |
| `dd4a03d` | `feat(v3):` | Milestone 0 implementation — 22 files, 1508 insertions(+), 14 deletions(-) | ✅ Yes |
| `0e47848` | `docs(v3):` | This `docs/v3/implementation/` directory's original 12-file creation | ✅ Yes |
| `d67528a` | `feat(v3):` | Milestone 1 implementation — 35 files, 2397 insertions(+), 123 deletions(-) | ✅ Yes |
| `30bf491` | `feat(v3):` | Milestone 2 implementation — 10 files, 1126 insertions(+), 74 deletions(-) | ✅ Yes |
| `2f92bba` | `feat(v3):` | Milestone 3 implementation — 25 files, 2533 insertions(+), 7 deletions(-) | ✅ Yes |
| `7219ac5` | `feat(v3):` | Milestone 4 implementation — beta resume templates (10-template catalog), writing suggestions, import review, second model tier | ✅ Yes |
| *(pending)* | `feat(v3):` | Milestone 5 — `complete milestone 5 beta hardening` (privacy audit, PDF metadata test, RAM sequencing, ATS integration tests, gallery widget test, full docs sync) | 🔄 Staged, not yet committed as of this line being written |

Every "Pushed?" answer above is a direct claim only where verified by `git ls-remote origin refs/heads/main` or `git merge-base --is-ancestor` at the time each milestone was finalized (see each milestone's own session in this project's history). `7219ac5` was `origin/main`'s HEAD at the start of this Milestone 5 pass, confirmed by `git log`.

## Commit discipline actually followed (verified against the history above, not just stated as intent)

- **One milestone per commit set, never mixed.** Confirmed by inspecting each commit's own file list (`git show --stat`) — no Milestone 1 file appears in the Milestone 0 commit, no Milestone 3 file appears in the Milestone 2 commit, etc. Milestone 0 was the one exception explicitly split into two commits (implementation, then documentation), by explicit instruction at the time — every other milestone (1, 2, 3, 4) landed as a single commit. Milestone 5 follows the same single-commit discipline: one commit, `feat(v3): complete milestone 5 beta hardening`, covering every M5 phase (privacy audit findings, PDF metadata test, RAM sequencing + tests, ATS integration tests, gallery widget test, docs sync) together, since the user's own instruction for this milestone was explicitly "create ONE M5 commit."
- **Documentation-only changes are their own commit, distinguishable from implementation commits.** `5a06f89` (PRD) and `0e47848` (this directory's creation) are both `docs:`-scoped with zero `lib/`/`test/` changes. Milestone 5's own docs sync is bundled into its single `feat(v3):` commit rather than split out, per that milestone's explicit instruction.
- **Conventional Commits prefixes**, matching V2's adopted convention: `feat(v3): implement/finalize/complete milestone N ...` for every implementation commit, `docs(v3): ...` for documentation-only commits — followed exactly for all commits above.
- **Before every milestone commit:** that milestone's own tests passed, `flutter analyze` was clean, and `git diff`/`git status` was reviewed to confirm the staged set matched exactly that milestone's file list — done for all of M0–M4, confirmed by each milestone's own session record, and done identically for Milestone 5 before its own commit (see [10-v3-progress.md](10-v3-progress.md) for the specific numbers: 1425/1425 tests, 0 analyze issues).
- **Never pushed unreviewed.** Every push (PRD, M0, M1, M2, M3, M4) was a separate, explicitly requested action after the corresponding commit was reviewed — commit and push were always two distinct steps, never combined silently. Milestone 5 follows the same pattern.

## What this documentation pass itself does

This Milestone 5 pass touches `docs/v3/implementation/` (all 12 files) plus the specific `lib/`/`test/`/`integration_test/` files listed in [02-backlog.md](02-backlog.md)'s Milestone 5 table. It does not modify `docs/v3/01-prd.md` (frozen — confirmed via `git diff -- docs/v3/01-prd.md` producing no output) or anything under `docs/v2/` (confirmed via `git diff -- docs/v2/` producing no output), and it does not touch any file outside the Resume/Career feature surface and its own test/doc coverage. Staging, committing, and pushing are the final step of this pass, performed only after this full review.

## Post-beta

Milestone 5 was the explicit stopping point for this engagement — per the user's own instruction, no Milestone 6 work, redesign, or further template expansion should begin without a new, separate request. Should a future milestone begin, the same discipline applies: its own commit(s), separate from M0–M5, `flutter analyze` clean and the full suite passing before staging, `git diff --cached --stat` reviewed before committing, push only after explicit approval.
