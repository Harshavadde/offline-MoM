# V2 Definition of Done

Four tiers, each building on the one below it. A tier is never marked done based on intent or code existing — only based on the specific evidence listed.

## A task is done when

- The code exists, is merged to its milestone branch, and satisfies its Acceptance Criteria exactly as written in [02-backlog.md](02-backlog.md) — not a weaker approximation of them.
- [8. Documentation updates] and [2. Code review] from [08-quality-gates.md](08-quality-gates.md) pass at minimum; other gates apply where the task type triggers them (e.g., a task touching the AI pipeline also needs [1. Architecture review] and [3. Unit tests]).
- The task's row in [02-backlog.md](02-backlog.md) is updated from `Not Started` — task-level status lives in the team's live tracker once work starts, not by editing the backlog document itself for every task (that document is the initial plan; [10-v2-progress.md](10-v2-progress.md) is the live dashboard, kept at Feature/Epic granularity, not re-deriving every task-level state from a static planning file).

## A feature is done when

- Every task under every Story within that Feature (per [02-backlog.md](02-backlog.md)) is done.
- The Story-level acceptance criteria are demonstrably true as a whole, not just as a sum of individually-passing tasks — a feature can have every task technically complete and still not actually work end-to-end if the pieces don't compose correctly, so an explicit end-to-end walkthrough of the feature's primary user story is required, not assumed from task completion.
- All quality gates from [08-quality-gates.md](08-quality-gates.md) applicable to that feature's nature have passed (a UI-facing feature needs the accessibility gate at minimum per-screen; an AI-pipeline feature needs the performance/memory gates).
- If the feature corresponds to a roadmap milestone (most do — see the mapping in [01-master-roadmap.md](01-master-roadmap.md)), that milestone's specific Acceptance Check has been executed and passed, its git tag has been applied, and [10-v2-progress.md](10-v2-progress.md) reflects `✅ Done`.

## An epic is done when

- Every Feature within it is done.
- The epic's features are tested **together**, not just individually — e.g., Epic 4 (Chat) isn't done just because workspace-chat, document-chat, and general-chat each pass in isolation; a session using all three scopes in sequence, on the same device session, without restarting the app, should behave correctly (shared state, like the LLM request queue and chat history persistence, is exactly where isolated-feature testing can miss a real bug that only shows up under combined use).
- Any ADR in [03-decisions.md](03-decisions.md) that was `Accepted — Pending Validation` and is now validated (or corrected) by this epic's completion is updated to `Accepted` with the final numbers/conclusions recorded — an epic that resolves a pending validation is not done until that resolution is written down, not just known informally.

## A release is done when

*(A "release" here means a `v2.0.0-alpha.N` / `-beta.N` / `-rc.N` / final GA tag, per [07-git-strategy.md](07-git-strategy.md) — not necessarily a Play Store submission, except for the final `v2.0.0` GA tag specifically.)*

- Every Epic scheduled for that phase (per [01-master-roadmap.md](01-master-roadmap.md)'s phase groupings) is done.
- The phase's stated **exit criteria** (explicitly written for each phase in [01-master-roadmap.md](01-master-roadmap.md)) are met and verified, not inferred.
- For a `-beta` or later tag specifically: the app has been installed fresh (not just incrementally updated from a dev build) and walked through its primary flows end to end by someone other than whoever wrote the code, since fresh-install behavior (onboarding, migrations from a real prior version, first-run downloads) is exactly the class of bug that incremental dev-build testing systematically misses.
- For the final `v2.0.0` general-availability tag specifically, additionally: every item in [02-backlog.md](02-backlog.md) Epic 8 (Monetization & Play Store Launch) is checked off with evidence, matching `docs/v2/19-playstore-launch.md`'s checklist — a signed AAB exists, the privacy policy is live at a public URL, the Data Safety form is submitted and accurate, and a real support contact is monitored.
- [10-v2-progress.md](10-v2-progress.md) shows every tracked item for that release as `✅ Done`, with no `🔄 In Progress` or `⛔ Blocked` items silently carried across the release boundary unresolved.

## What "done" explicitly does not mean

Done does not mean "the happy path works when I tried it once." Every tier above requires the specific tests, gates, and evidence listed — a task, feature, epic, or release that "seems to work" without that evidence attached is not done, it's untested, and should be labeled `🔄 In Progress` in [10-v2-progress.md](10-v2-progress.md) until the evidence exists.
