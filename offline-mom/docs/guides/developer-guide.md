# Developer Guide

> **Sync note (documentation synchronization pass):** the migration count and feature list below were updated to match the current codebase (migrations through v14; no `conversation_translator/` feature folder — it was removed). Updated again 2026-08-06 for migration v15 (`folders`) and the new `friendlyErrorMessage()`/`hasInternetConnection()` utilities (see [`10-v2-progress.md`](../v2/implementation/10-v2-progress.md), Phase 9.3, tag `phase-9-3`).

Start with [`docs/architecture/hld.md`](../architecture/hld.md) for the overall shape, and [`docs/architecture/database-design.md`](../architecture/database-design.md#folder-structure-why-it-looks-the-way-it-does) for why the folder layout looks the way it does.

## Adding a new feature

1. **Entities** go in `lib/models/` if shared across features, or inside the feature's own folder if truly local.
2. **Persistence** goes through a repository interface in `lib/repositories/` (abstract class + `Sqflite*`/`Hive*` implementation) — never call `sqflite`/`Hive` directly from a ViewModel.
3. **Native/platform functionality** (a new sensor, a new file format, a new AI capability) goes behind a service interface in `lib/services/<category>/` — same rule: ViewModels never import a plugin package directly.
4. **Orchestration crossing more than one repository/service** gets a dedicated use-case class, named `<Verb><Noun>UseCase`, living in the feature folder it most naturally belongs to. Simple single-repository reads/writes are called directly from the ViewModel.
5. **Wire it up** in `lib/providers/app_providers.dart` — this is the only file that should construct a concrete repository/service implementation.
6. **ViewModel**: a Riverpod `Notifier` in `features/<name>/presentation/providers/`, exposing a sealed state class if the feature has more than a simple loading/data/error shape (see `RecordingUiState`, `ImportUiState` for examples).
7. **Screen**: a `ConsumerWidget`/`ConsumerStatefulWidget` in `features/<name>/presentation/screens/`. Use `lib/shared/widgets/empty_state.dart` for empty states and `lib/shared/widgets/ai_pipeline_fallback.dart` for anything waiting on the transcribe/summarize pipeline.
8. **Route**: add the path to `lib/core/router/route_paths.dart` and the `GoRoute` to `lib/core/router/app_router.dart`.
9. **Tests**: repository tests against a real in-memory DB (`test/test_helpers/test_database.dart`), use-case tests against fakes if AI engines are involved (`test/test_helpers/fake_ai_engines.dart`).

## Swapping an AI engine

This is the scenario the architecture is built around (and it already happened once — see [`docs/architecture/ai-architecture.md`](../architecture/ai-architecture.md#why-flutter_llama-was-replaced-with-llamadart)):

1. Write a new class implementing `SpeechToTextEngine` or `LlmEngine` (`lib/services/ai/`).
2. Change one line in `lib/providers/app_providers.dart` (`speechToTextEngineProvider`/`llmEngineProvider`) to construct the new class instead.
3. Nothing else changes — no screen, use case, or repository references a concrete engine class.

## Database migrations

The schema is versioned (`lib/database/migrations/` — currently `v1.dart` through `v15.dart`). To add a column/table:
1. Write the next `vN.dart` with the `ALTER TABLE`/`CREATE TABLE` statements needed to go from vN-1 → vN.
2. Bump `AppConstants.sqliteDbVersion` and add an `onUpgrade` callback in `AppDatabase.open()` that calls the new migration when upgrading from an older version.
3. Update [`docs/sql/schema.sql`](../sql/schema.sql) and the ER diagram in [`docs/architecture/database-design.md`](../architecture/database-design.md) to match.

**Additive columns don't always need a real foreign key.** A handful of columns (`toolkit_files.tool_type`, `installed_models.model_id`, `documents.folder_id`) reference something outside a strict parent/child schema relationship (an enum-like value, a static catalog, an organizational label) and are deliberately left without a `REFERENCES` constraint, validated at the repository layer instead. Reach for this only when the column is genuinely additive and low-risk, not as a default — every content-ownership relationship (`meeting_id`, `document_id`, etc.) still uses a real, cascading FK.

**A model doesn't have to be `@freezed`.** Most domain models are (`Meeting`, `Document`, `ChatMessage`); a few simpler ones are plain hand-written classes with their own `copyWith`/`toMap`/`fromMap` (`Note`, `Folder`) — a reasonable choice for a small model where a `build_runner` codegen run isn't worth the risk/cost for what it adds. Follow whichever an existing sibling model in the same area already does.

**User-facing error text goes through `friendlyErrorMessage()`.** `lib/core/utils/friendly_error.dart` turns an exception into plain-language text (never a raw `toString()`/stack trace) for any screen/widget that shows an error to the user — wire new error-displaying UI into it rather than writing another ad hoc translation. For a proactive (rather than reactive) connectivity check before starting something network-dependent, use `lib/core/utils/connectivity_check.dart`'s `hasInternetConnection()` (no new package required).

**Deliberately not persisting something.** Not every feature has to belong in SQLite/Hive — an earlier feature (the since-removed Conversation Translator) kept its session in-memory only (a plain Riverpod `Notifier`, no repository at all) because that data was treated as more sensitive-by-default than a recorded meeting. If a future feature has the same "never write this to disk" requirement, that's the pattern to copy: no repository interface, no table, state lives only in the Notifier for the screen's lifetime. Nothing in the current app uses this pattern any more — every content type today is persisted.

## Code style

- No comments explaining *what* code does (identifiers should already say that) — only *why*, when it's non-obvious (a workaround, a hidden constraint, a subtle invariant).
- Prefer three similar lines over a premature abstraction.
- `flutter_lints` is enabled (`analysis_options.yaml`); `flutter analyze` should report zero issues before committing.

## Where things live (quick index)

| Concern | Path |
|---|---|
| Theme | `lib/core/theme/app_theme.dart` |
| Routes | `lib/core/router/` |
| DB schema/migrations | `lib/database/` |
| Composition root (DI) | `lib/providers/app_providers.dart` |
| Repositories | `lib/repositories/` |
| Recorder/import/AI/retrieval/toolkit/security/export services | `lib/services/` |
| Feature code | `lib/features/<name>/` — `ai_models`, `ai_summary`, `ask` (legacy, orphaned), `chat`, `documents`, `export`, `import`, `meetings`, `onboarding`, `recording`, `search`, `settings`, `student_toolkit`, `transcription` |
| AI reliability (timeouts/cancellation) | `lib/services/ai/llamadart_llm_engine.dart` — see [`ai-architecture.md`](../architecture/ai-architecture.md#reliability-timeouts-and-cancellation) before changing anything here |
| Friendly error messages / connectivity check | `lib/core/utils/friendly_error.dart`, `lib/core/utils/connectivity_check.dart` |
| Tests | `test/` (unit/widget), `integration_test/` (on-device) |
| Documentation | `docs/` (this folder) |
