# V2 Security

Extends V1's `docs/legal/security-compliance.md` threat model to the new modules. Carries forward, unchanged: dependency pinning (no floating version ranges), ProGuard keep-rules verified against real package names, app-private OS-sandboxed storage, the app-lock (`local_auth`) design that never lets the app see the underlying credential.

## New attack surface: untrusted file parsing

Documents introduce a new class of input the app has not previously had to handle: user-supplied PDF and DOCX files, which are complex binary formats with a real history of parser vulnerabilities across the industry (malformed PDFs triggering crashes or worse in poorly-hardened parsers is a well-known class of issue, independent of this app). Same discipline V1 already applies to audio (ffmpeg) and speech recognition (whisper.cpp): **do not hand-roll PDF/DOCX parsing in application code.** Use well-maintained upstream libraries for the actual format parsing (NFR-19), treat any parser failure as an ordinary `error` status rather than something the app needs to special-case, and — matching the existing convention — verify any new native/plugin dependency's real package name for ProGuard rules rather than guessing, and document why it was chosen if it has native glue code.

## Threat model additions

| Threat | Applicable? | Mitigation |
|---|---|---|
| Malicious/crafted document exploiting a parser vulnerability | Yes, in principle | Handled by the upstream extraction library's own input hardening, not this app's own parsing code (same posture as ffmpeg/whisper.cpp today) |
| A large or adversarially-crafted document causing excessive memory/CPU use during extraction or embedding | Yes | Extraction and embedding both run through the same background-processing + timeout discipline as transcription/summarization; a pathological file fails with an `error` status rather than hanging the app (extends NFR-9/NFR-10) |
| Embedding vectors or chunk text leaking content outside the app | No new risk beyond what already exists for transcripts/summaries | `knowledge_chunks` lives in the same app-private SQLite database as everything else; no new export/sharing path is introduced for chunk-level data specifically |
| Chat history containing sensitive content persisted where meeting/document content wasn't before | New consideration | Chat history is stored with the same protections as every other on-device table (app-private storage, app-lock gate if enabled) — see [17-privacy.md](17-privacy.md) for the reasoning behind persisting it at all |

## Unchanged, disclosed gap

V1's security-compliance document already discloses that neither the SQLite database nor the Hive box is encrypted independently of the OS's own device-level encryption. V2 does not close this gap by itself — it inherits it, now covering a larger surface (documents, chunks, chat history in addition to meetings). If V2 is pursued as a genuinely commercial product (per this document set's framing, no longer a college project), **closing this gap — SQLCipher or Hive's built-in AES encryption — should be evaluated seriously before general availability**, rather than carried forward a second time as an accepted gap. This is a recommendation, not a requirement resolved by this document.

## Compliance posture

Same honest posture as V1: no formal regulatory certification is claimed (GDPR, HIPAA, SOC 2, or equivalents). The zero-data-transmission architecture makes several of those frameworks' core data-transfer obligations trivially satisfied by construction, which is a genuine, structural advantage — particularly relevant to the legal/healthcare/journalism personas in [05-user-personas.md](05-user-personas.md) — but is not the same as certification, and should not be marketed as such without an actual audit.
