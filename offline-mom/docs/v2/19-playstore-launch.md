# V2 Play Store Launch Readiness

Consolidates and extends work already substantially underway on the existing codebase (not V2-specific — this applies whether V2's new modules exist yet or not, and should be treated as gating commercial launch independent of feature completeness).

## Already in place

- Legal documents rewritten as production-facing text (not academic-template wording): `docs/legal/privacy-policy.md`, `terms-of-service.md`, `data-processing-agreement.md`, `nda.md`, `security-compliance.md`, `ethical-ai-statement.md`, `responsible-ai-statement.md`.
- Real release-signing Gradle configuration wired (`android/app/build.gradle.kts` reads from a gitignored `android/key.properties`, falling back to debug signing only when that file is absent).
- Foreground-service permissions (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS`) already declared and scoped to the opt-in background-download feature only.
- App branding finalized (OfflineMoMAI, `com.offlinemomai.app`).

## Still outstanding (V1 scope, unblocked by V2)

- **A real release keystore.** The signing config is wired but no keystore exists yet — this must be generated and its passwords kept safe by whoever owns the Play Store listing; it is not something that should be generated and handed over casually, since losing it means losing the ability to ever update the published app again.
- **AAB build format.** The Play Store requires an Android App Bundle (`flutter build appbundle --release`) for new app submissions, not the `.apk` this project has been building and testing with.
- **A hosted, publicly-reachable privacy policy URL.** `docs/legal/privacy-policy.md` is a repository file, not a live web page — Play Console requires a URL, not a file. GitHub Pages (rendering the existing markdown) is the lowest-friction option.
- **Store listing assets**: screenshots, a feature graphic, short and full descriptions, content rating questionnaire completion.
- **Data Safety form** in Play Console — should be straightforward given the zero-data-transmission architecture, but still needs to be filled out accurately (including any new data categories introduced by V2 — see below).
- **A support contact.** The current privacy policy points to "the project's README" for contact information; the README doesn't currently have one. This needs an actual, monitored contact before launch.
- **Google Play Developer account** (one-time registration fee).

## New for V2 specifically

- **Data Safety form updates**: document import and chat history are new "data collected/processed" categories to declare accurately, even though — per [17-privacy.md](17-privacy.md) — none of it is transmitted anywhere. "Collected but never shared or transmitted, processed entirely on-device" is the honest, and favorable, answer Play Console's form structure supports.
- **Any new permission** introduced by document import (unlikely to need more than the existing file-picker-based flow, which requires no broad storage permission on modern Android) should be re-justified in the same spirit as the existing `FOREGROUND_SERVICE_DATA_SYNC` justification.
- **If Play Billing is adopted** ([18-subscription-model.md](18-subscription-model.md), Option B), the `com.android.vending.BILLING` permission and Play Billing library integration need their own review pass — in-app purchase flows have their own Play Console review requirements distinct from the rest of this checklist.

## Sequencing

This entire checklist is independent of V2's feature roadmap ([07-feature-roadmap.md](07-feature-roadmap.md)) and can be completed in parallel with Phase 0/1 engineering work — there's no reason to wait for Documents/Chat to ship before generating a keystore, hosting the privacy policy, or registering a developer account. The one item that must wait is the Data Safety form update for document/chat data categories, since that depends on those features actually existing.

## Operational cost & infrastructure overview

Direct consequence of the "no backend, no accounts, no cloud AI" architecture restated throughout this document set ([10-system-architecture.md](10-system-architecture.md), [17-privacy.md](17-privacy.md)): there is no server this product operates, so there is no server to size, host, monitor, or pay for. Whatever the app does at runtime, it does using compute the user's own device already has — this is a cost statement, not just a privacy one.

**What this product does not need, and why:**

- **No application servers.** All transcription, summarization, embedding, retrieval, and PDF/image processing run on-device (`whisper.cpp`, `llama.cpp`, brute-force vector search, `pdf`/`printing`) — there is no API for the app to call at runtime beyond the one-time model download.
- **No database hosting.** Every user's data lives in their own device's SQLite/Hive storage; there is no shared or centrally-hosted database.
- **No object/file storage costs.** Recordings, documents, and toolkit outputs are written to the device's own filesystem, never uploaded.
- **No per-user or per-request AI inference cost.** Unlike a cloud-AI competitor's line-item cost-per-token/per-minute, every summarize/chat/transcribe call runs on hardware the user already owns.

**What does have a real, bounded cost:**

- **AI model hosting bandwidth**: the GGUF models (Whisper, Qwen2.5-1.5B, embeddinggemma-300M) are pulled from Hugging Face's own public model hub on first run — Hugging Face bears that hosting/bandwidth cost today, not this project, since the models are hosted on their infrastructure, not a project-operated CDN.
- **Google Play Developer account**: one-time registration fee (see "Still outstanding" above).
- **A hosted privacy-policy page**: effectively free at this scale (e.g. GitHub Pages).
- **If Play Billing is ever adopted** ([18-subscription-model.md](18-subscription-model.md)): still no custom backend, since Google operates the only server involved in entitlement checking — the cost is Play's standard revenue share on the one-time "Pro" unlock, not infrastructure.

**What would change this**, so it's flagged before it happens rather than discovered mid-roadmap: the one architectural change that would introduce real, ongoing operational cost is the "Backend only for licensing/account management (future)" possibility named in [20-future-roadmap.md](20-future-roadmap.md) — and even that is scoped narrowly to licensing/account state, not to any user content, meeting, document, or AI processing, which stays on-device under every option currently being considered.
