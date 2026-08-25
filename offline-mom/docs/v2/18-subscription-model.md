# V2 Subscription / Monetization Model

## The tension this document exists to resolve

V1's documentation states, in multiple places, as a **permanent decision distinguished explicitly from merely-deferred features**: no accounts, no login, no cloud sync, no backend, no subscription billing — justified as directly protecting the product's core privacy premise. This document set's brief asks "what should become premium," which cannot be answered without either revisiting that permanence or designing a monetization model narrow enough to not actually violate it. **This is a product/business decision, not an engineering one — the options below are laid out for an explicit choice, not resolved unilaterally here.**

## Why this matters architecturally, not just commercially

Different monetization models impose genuinely different technical requirements:

- A **subscription** conventionally implies recurring entitlement checking — traditionally requiring a backend to validate active status, which would be a real, direct violation of "no backend, ever."
- A **one-time purchase** can be validated entirely through the Android Play Billing library, which itself talks to Google Play (not a server this product operates), and can be checked locally on-device after purchase — no new backend, no new account system beyond the Google Play account the user's device already has for installing the app in the first place.

This distinction is the crux of which options below are actually compatible with the existing hard constraints.

## Options

### Option A: Paid app, no freemium (simplest)

A single upfront price on the Play Store listing, full workspace functionality included, no tiers. Zero new infrastructure — no Play Billing integration, no entitlement checking of any kind. Fully compatible with every existing constraint without any nuance required. Trade-off: no free tier for user acquisition, no upsell path if a bigger/better model tier is ever worth charging more for later.

### Option B: Free app + one-time "Pro" unlock (recommended default)

Free tier: Meetings (as today) plus a capped/smaller version of Documents and Chat (e.g., a limited number of documents, the smaller default model tier). A single one-time Play Billing purchase unlocks: unlimited documents, the larger LLM/embedding model tier (if [07-feature-roadmap.md](07-feature-roadmap.md) Phase 3 adopts one), and any other capacity/quality gates. Entitlement is checked via Play Billing's on-device purchase-state API — no custom backend, no account beyond the user's existing Play Store account. This preserves "no accounts, no backend" in letter and spirit: the user never creates an OfflineMoMAI-specific account, and Google — not this product — operates the only server involved, in a role identical to what already happens when the user installs the app itself.

### Option C: Subscription via Play Billing's subscription APIs

Technically possible without a custom backend — Play Billing supports subscriptions with Google handling receipt/entitlement state, not requiring the developer to run their own server. Included here for completeness, but **not recommended**: even though it doesn't technically require a backend, a recurring charge is a materially different relationship with the user than the rest of this product's design (no accounts, no ongoing relationship, own your data forever once you've paid for it), and sits awkwardly against the positioning in [02-market-positioning.md](02-market-positioning.md), which explicitly contrasts OfflineMoMAI's "no recurring cost" against Otter.ai/Fireflies/Notion AI's subscription models. Adopting a subscription narrows that differentiation rather than sharpening it.

## Recommendation

**Option B** (free tier + one-time Pro unlock via Play Billing) as the default to design toward, with **Option A** as a safe fallback that requires zero additional engineering if the Pro/free split proves more complex to define fairly than it's worth. **Option C is not recommended** but is documented for completeness since it was a natural reading of "subscription model" as a document title, and its rejection should be an explicit, informed choice rather than an omission.

## What premium should plausibly include, if Option B is adopted

- Unlimited documents in the knowledge base (free tier: a capped number, e.g. enough for genuine evaluation, not enough for real ongoing use).
- The larger LLM/embedding model tier, once one exists (Phase 3, [07-feature-roadmap.md](07-feature-roadmap.md)) — better summary/chat quality is a legitimate, tangible value a user can feel, unlike an artificial feature gate.
- Priority/uncapped chat history retention.
- **Student/Productivity Toolkit capacity or quality gates** (Phase 5A/5B, shipped since this document was originally written) — e.g. a capped number of saved toolkit outputs on the free tier, or higher-DPI/higher-quality PDF compression presets reserved for Pro, mirroring the same "capacity gate on a tangible, feelable quality difference" logic already applied to documents/chat above. Not designed further here — this is a new candidate surface for the same Option B mechanism this document already recommends, not a reason to revisit the recommendation itself.

**What should never be premium**, regardless of which option is chosen: the core privacy guarantees themselves (no tiered privacy — restated from [05-user-personas.md](05-user-personas.md)), the ability to delete your own data, and app lock/security features — gating security behind payment would be a genuinely bad-faith move inconsistent with everything else this product claims to stand for.

## Decision required before Phase 3

Before any Play Billing integration work begins ([07-feature-roadmap.md](07-feature-roadmap.md) Phase 3), the product owner needs to explicitly choose Option A or Option B (or reject both and revisit this document). This is flagged as an open decision, not a default this specification has silently made on the product's behalf.

**Status update (Phase 5B freeze pass):** the *category* of this work — that a licensing/premium architecture will be built — is now Approved Future Architecture (ADR-035, [implementation/03-decisions.md](implementation/03-decisions.md); see also [20-future-roadmap.md](20-future-roadmap.md)). That approval does **not** pick Option A, B, or C — the choice above remains exactly as open as it was before ADR-035, which explicitly declines to resolve it. Nothing in this document should be read as implemented; no licensing code, account system, or backend exists in `lib/` today.
