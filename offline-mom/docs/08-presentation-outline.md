# Presentation Outline

Suggested 10-12 minute defense structure, one slide per numbered item unless noted.

1. **Title slide** — OfflineMoMAI, tagline, your name/institution.
2. **The problem** — cloud meeting assistants require trusting a third party with sensitive audio, and cost money per use; separately, translating with no internet connection isn't well served either. (2-3 sentences, from [`01-executive-summary.md`](01-executive-summary.md).)
3. **The idea** — do the entire pipeline on-device: no server, no account, no recurring cost — and reuse the same on-device model for more than just meetings.
4. **Live/recorded demo, part 1: meetings** (2-3 slides or a screen recording) — record a short meeting → show transcript appearing → show summary/MoM → add an action item manually → export PDF. This is the highest-impact part of the defense; prioritize it over slides.
5. **Live/recorded demo, part 2: Conversation Translator** — pick two languages, speak a line, show it translated and spoken aloud, reply in the other language. This is the most visually striking part of the app and worth its own moment, not a footnote to the meeting demo.
6. **Architecture at a glance** — the layered diagram from [`docs/architecture/hld.md`](architecture/hld.md): Presentation → Use Cases → Repositories/Services → SQLite/Hive + native AI, noting the Conversation Translator's session is the one thing that deliberately never touches SQLite/Hive.
7. **Why Clean Architecture here specifically** — the AI engines are the one part of this app guaranteed to change (model swaps, package swaps); show the `SpeechToTextEngine`/`LlmEngine` interfaces, mention the `flutter_llama` → `llamadart` swap, and that the same `LlmEngine` interface now backs three features (summary, Ask AI, Translator) with zero interface changes needed to add the last two.
8. **The AI pipeline** — one slide: record/import → ffmpeg → whisper.cpp → llama.cpp (strict JSON out) → SQLite, with the activity diagram from [`docs/architecture/lld.md`](architecture/lld.md).
9. **A real reliability bug, found and fixed** — briefly: because three features share one model that serializes requests, a single stuck generation call once hung the *entire app's* AI functionality for 8+ hours on a 7-second recording; walk through the two timeouts (generation stall, download stall+cap) that now bound it. This is a genuinely strong engineering story — a real bug, root-caused, fixed with a specific mechanism, not just "we added a try/catch."
10. **Database design** — the ER diagram from [`docs/architecture/database-design.md`](architecture/database-design.md), one line on why cascading deletes matter, and a one-line aside on the `decisions` table being intentionally kept-but-unused rather than ripped out.
11. **Testing approach** — repository tests against real SQLite, use-case tests against fake AI/TTS engines, why that split makes sense without a device.
12. **Real engineering challenges encountered** — briefly: native toolchain version mismatches, a broken pub.dev package discovered mid-build, an AGP-9 Kotlin-migration conflict. This shows engineering judgment, not just following a tutorial — reference [`docs/guides/installation-guide.md`](guides/installation-guide.md).
13. **What's deliberately out of scope** — no cloud/login/integrations, and why (privacy is the entire premise); also why decisions/structured action items are no longer AI-extracted (a considered trade-off, not a bug).
14. **Future scope** — configurable/larger models, bundling models in the APK for zero-network-ever, chunked summarization for long meetings, byte-level download progress.
15. **Questions.**

### Presentation tips specific to this project

- If a live demo isn't possible (no device in the room), a screen recording from your own phone is a strong substitute — silent demos with captions work fine. This matters even more for the Translator demo (item 5), since spoken audio output is the whole point.
- Be ready to explain *why* Qwen2.5-1.5B/whisper-base rather than bigger models: it's a deliberate size/quality trade-off, not a limitation you didn't notice — and be honest that translation quality on a 1.5B model is a real, acknowledged limitation, not something claimed to be solved.
- Be ready to explain *why* decisions/action items stopped being AI-extracted: it's a considered speed/reliability trade-off made after real testing, reversed a previous design decision, and isn't a missing feature — it's useful to show you can change your mind on your own earlier design when evidence says to.
- The native-toolchain saga and the 8-hour-hang bug (items 9 and 12) are both legitimate engineering stories worth telling honestly — they demonstrate debugging and adaptation, which examiners generally value more than a project that "just worked."
