# Productivity Toolkit — Final Productization Audit (Phase 0)

**Purpose:** Mandatory pre-implementation audit for "Productivity Toolkit — Final Productization + Offline-First PDF Suite." Every claim below is grounded in direct source inspection (`lib/`, `pubspec.yaml`, installed package source under the pub cache, `docs/v2/implementation/`), not assumption. Where a claim rests on existing documentation (the Phase 5A/5B completion records in `10-v2-progress.md`, ADR-033/034/015 in `03-decisions.md`, R-30 through R-34 in `04-risk-register.md`), it was spot-checked against the current code, not trusted blindly — several checks (file existence, enum values, dependency list, `PdfEncryption`'s actual completeness) were run explicitly for this document.

**Date:** 2026-08-13. **Scope:** Phase 0 only — audit and capability/feasibility matrix. No implementation code was touched.

**Update, 2026-08-18 (P0-7):** Items #5/#6/#33 below (OCR, Scan → searchable PDF, OCR text search) and §5's "OCR engine — Exact package TBD in P0" are now resolved and shipped — see ADR-045, `docs/v2/implementation/03-decisions.md`. This document's own tables/analysis are preserved as written below (a point-in-time audit, not a living spec); treat any "E"/"TBD" marking on those three rows as historical, superseded by ADR-045 and the P0-7 entry in `10-v2-progress.md`.

**Update, 2026-08-18 (P0-8):** Items #21/#22 below (PDF password protection/encryption, PDF permissions/security) and this document's own §3/§6 caveat that "no package identified/vetted yet" for PDF encryption are now resolved and shipped — see ADR-046, `docs/v2/implementation/03-decisions.md`. This audit's original assessment ("real password protection means either finding a separate, permissively-licensed Dart PDF-encryption package... or writing a correct ISO-32000 standard-security-handler from scratch, a security-sensitive undertaking") held up: `pdf_cos`/`pdf_document` (Apache-2.0) supplied the former (a real, spec-correct Standard Security Handler *reader*), and this app's own new `pdf_encryption_algorithms.dart` supplied the one missing piece (the *write-side* key-derivation the library's public API doesn't expose), verified against the library's own independent reader rather than assumed correct. Treat the "E"/"not yet researched" marking on rows #21/#22 and the §3/§6/§7 caveats about password protection as historical, superseded by ADR-046 and the P0-8 entry in `10-v2-progress.md`.

**Update, 2026-08-19 (P0-9, final P0 item):** Item #13 below (File manager parity) is now resolved and shipped — see ADR-047, `docs/v2/implementation/03-decisions.md`. This audit's own §5 recommendation was followed exactly as written: **option (a)** ("Bring Toolkit Recent Files to feature parity — search/sort/folders/multi-select — while keeping the two stores separate... respects ADR-033's original, deliberate 'toolkit outputs aren't Knowledge Sources' decision"), not option (b) (unifying `toolkit_files` with `documents`, which would have reversed ADR-033 and was explicitly flagged as needing its own separately-approved phase, not something to fold in silently). The parity table in §5 above is now stale on every row for Toolkit's own column: Folders/Search/Sort/Favorites/Multi-select are all now Yes, and Move is now Yes (folders exist to move into) — Documents' own column is unchanged and still reflects its own state as of this audit's original writing. **The original P0 backlog (items 1-13) is now completely closed.**

**Update, 2026-08-20 (B3 release blocker, discovered and fixed after P0 closed):** A Release Readiness / Full Product Audit run immediately after P0-9 closed found a genuine regression this audit did not anticipate: the rasterize-and-rebuild architecture this document's own §2 explains (every PDF Tool flattens pages to images and rebuilds) was silently destroying a page's *existing* searchable text — including OCR's own invisible text layer from item #5/#6 above — the moment a user ran Compress/Merge/Split/Organize/Edit/Redact on an already-searchable PDF, document-wide, even when only one page was actually transformed. This was not a gap this audit's own §3 matrix disclosed (items #5/#6/#36 were marked feasible/shipped on their own merits, not cross-checked against every *other* tool's own destructive rebuild step) - a genuine miss, recorded honestly rather than glossed over. Fixed (`PdfSearchableTextPreserver`, R-49, `04-risk-register.md`, commit `039be18`): five tools now reconstruct existing text via `PdfTextSearchService` with zero new OCR calls; Permanent Redaction never reuses pre-redaction flat text on a page it actually redacts, using fresh word-level OCR (only when a model is already installed) to keep only demonstrably-safe words instead. See `12-architecture-diagrams.md` §12b for the full pipeline diagram. **B1/B2/B3 (the three release blockers a subsequent Release Candidate audit, 2026-08-20, found and independently re-verified fixed) are now all resolved** — see R-47/R-48/R-49 in `04-risk-register.md`. That same 2026-08-20 audit also confirmed the release APK is currently **debug-signed** (no production keystore exists in this implementation environment) — a release-*process* gap (R-27, still open), not a defect in anything this document audited.

**Baseline for context:** release APK (`docs/v3` Part K, same repo, same day) — arm64-v8a 127.9MB, armeabi-v7a 110.4MB. Native libraries already bundled: llama.cpp/ggml (LLM + embeddings), whisper.cpp (speech-to-text), FFmpeg (audio transcode), SQLite (FTS5-capable, `sqlite3_flutter_libs`). No PDF-specific native library is bundled today — `printing`'s rasterization calls Android's own OS-level `PdfRenderer` via platform channel, not a bundled library.

---

## 1. Current Feature Audit — the 8 existing tools, individually re-verified

The current Productivity Toolkit (internally still named "Student Toolkit" in code/docs — user-facing copy already says "Productivity Toolkit" per `HomeScreen`) ships exactly 7 tool types plus a Recent Files view, confirmed directly from `lib/models/toolkit_file.dart`'s `ToolkitToolType` enum: `imageCompress`, `imageResize`, `scan`, `pdfCompress`, `pdfMerge`, `pdfSplit`, `pdfOrganize`.

| Feature | Real implementation? | I/O | Persistence | Errors | Cancel | Progress | Large-file | Offline | Tests | Category |
|---|---|---|---|---|---|---|---|---|---|---|
| **Scan Document** | Real: camera/gallery capture via `image_picker`, pure-Dart 4-point perspective correction (`scan_image_processing_service.dart`, real projective-transform math), multi-page session, `ScannerPdfService` builds a real PDF | Real images in → real PDF out | `ToolkitFile` row + file on disk (migration v11/v12) | Picker exceptions now caught (Phase 10 fix); PDF generation failures surface a friendly error | UI-level session (delete/reorder before commit); no mid-render cancel needed (fast) | Per-page, via session state | Not tested against a large (50+ page) scan session | Fully offline (no network code anywhere in the path) | 9 controller tests + 11 image-processing tests + 3 PDF-service tests | **A**, with disclosed risk (R-32/R-34: never run on a real camera/touchscreen) |
| **Compress Image** | Real: `ImageCompressionService`, target-size JPEG binary search with an analytically-computed downscale ratio | Real image in → real compressed image out | `ToolkitFile` row + file | Picker exceptions caught; decode-failure throws a typed exception | UI-level, proven by a dedicated test (`cancel()`-during-processing) | Yes | Untested against a real multi-MB camera photo (R-31) | Fully offline | 11 service + 8 controller + 2 screen tests | **A**, disclosed risk (R-31) |
| **Resize Image** | Real: `ImageResizeService`, percentage/width/height with aspect-lock | Real in/out | `ToolkitFile` row + file | Same as Compress | Same | Yes | Same R-31 caveat | Fully offline | 12 service + 6 controller tests | **A**, disclosed risk (R-31) |
| **Compress PDF** | Real: `PdfCompressionService`, 5 fixed-tier presets + Custom (DPI/quality, not target-byte) | Real PDF in → real PDF out (rasterize-and-rebuild, see §2) | `ToolkitFile` row + file | `PdfRenderingException` on unreadable input, friendly message | Not separately tested at the controller level (service-level only — disclosed scope boundary) | Yes | Streams one page at a time (`PdfPageRenderingService`), never holds all pages in memory | Fully offline | 5 service tests | **A**, with a real disclosed quality tradeoff (R-33: loses text-selectability, by design) |
| **Merge PDFs** | Real: `PdfMergeService` | Multiple real PDFs in → one real PDF out | `ToolkitFile` row + file | Same pattern | Same | Yes | Same streaming approach | Fully offline | 5 service + 5 controller tests | **A** |
| **Split PDF** | Real: `PdfSplitService`, proven to rasterize each needed page exactly once even across multiple output groups | One real PDF in → multiple real PDFs out | `ToolkitFile` rows + files | Same pattern | Not controller-tested (disclosed scope boundary, service-level only) | Yes | Same | Fully offline | 4 service tests | **A** |
| **Organize Pages** | Real: `PdfOrganizeService` — covers both "Extract Pages" and "Reorder Pages" as one transform (`organize(sourceBytes, orderedPageIndices)`) | Real PDF in → real PDF out | `ToolkitFile` row + file | Same pattern | Not controller-tested (disclosed scope boundary) | Yes | Same | Fully offline | 5 service tests | **A** |
| **Recent Files** | Real: `ToolkitFileRepository` (SQLite, migration v11/v12), grouped Today/This Week/Older, rename/favorite/duplicate/delete/share | Real DB rows, real files on disk | Survives app restart (SQLite) | `duplicate()`'s disk-full case now caught with a snackbar (Phase 10 fix) | N/A | N/A | Not stress-tested with hundreds of entries | Fully offline | 5 action tests + 4 screen tests | **A**, but genuinely thin next to Documents (see §6) — no search, no sort, no folders, no multi-select |

**Overall:** every one of the 8 current features is genuinely, fully implemented — not UI-only, not fake. Category A across the board. The honest gaps are (a) real-device verification (R-30 through R-34, all still **Open** — confirmed by direct re-read of `04-risk-register.md` for this document, not assumed carried-forward), and (b) Recent Files' feature depth versus the separate Documents manager (see §6).

**One confirmed unfixed defect, not new:** R-30 (a `TextEditingController`-dispose race in `showDialog` rename flows) was fixed in Toolkit's own Recent Files screen but is still **suspected, unconfirmed, unfixed** in six other app-wide dialogs (`HomeScreen._editDisplayName`, `DocumentDetailsScreen._renameDocument`, `ChatHistoryScreen._rename`, three `MeetingDetailsScreen` dialogs) — outside this toolkit's own boundary, but worth carrying into this pass's risk awareness since new rename/edit dialogs should not reintroduce the same pattern.

**One new finding this audit surfaced, not previously documented:** the exact "shows blank when preview" `PdfPreview`-missing-`onError` bug fixed this session in the Resume feature (`docs/v3` Part J, commit `4e4aad8`) **also exists in 5 more places**, all using the identical bare `PdfPreview(...)` call with no `onError`:
- `lib/features/student_toolkit/presentation/screens/pdf_merge_screen.dart`
- `lib/features/student_toolkit/presentation/screens/pdf_organize_screen.dart`
- `lib/features/student_toolkit/presentation/screens/scanner_screen.dart`
- `lib/features/student_toolkit/presentation/screens/toolkit_recent_files_screen.dart`
- `lib/features/export/presentation/screens/pdf_preview_screen.dart` (meeting-report export, outside the toolkit but same root cause)

Same root cause confirmed by source read of `package:printing` 5.14.3: Flutter's default `ErrorWidget` fallback computes its message inside an `assert()` block, stripped in release builds. **Not fixed in this audit pass** (Phase 0 is audit-only) — flagged for the P0 implementation phase, since it directly affects the toolkit's own result previews (Merge/Organize/Scanner) and the Recent Files "preview before you rename/delete/share" flow this spec explicitly asks to be reliable.

---

## 2. The one architectural fact that governs most of this audit

**This app's entire PDF strategy is rasterize-and-rebuild** (ADR-034, confirmed unchanged): every PDF operation reads pages via `Printing.raster()` (Android's OS-level `PdfRenderer`, no bundled native library), then rebuilds a new PDF from those page images via `package:pdf` (a PDF *generator*, not an *editor* — it cannot open and modify an existing PDF's object graph). This was a deliberate, license-driven choice: the only alternative with equivalent manipulation power (`pdf_manipulator`) is AGPL-3.0 with a Rust native engine, explicitly rejected.

**Consequence for this productization pass:** every capability that only needs to *place new content on top of* or *rebuild from* existing pages (add text, signatures, annotations, watermark, crop, rotate, redaction, page insert/delete/reorder/duplicate) is genuinely, fully feasible offline with **zero new dependencies** — it's the same mechanism the app already runs for every Compress/Merge/Split/Organize operation today, just drawing something before the rebuild step instead of nothing.

**Every capability that needs to read or modify an existing PDF's real internal structure** (true text editing in place, reading/filling existing AcroForm fields, reading existing bookmarks/outlines, extracting embedded images to move them) is **not achievable** with the current dependency set — `package:pdf` has no PDF-*parsing* capability of that depth, only page-content-stream *extraction* (already used by `pdf_parser.dart` for the Documents feature's search indexing) and *generation*.

**One genuinely favorable consequence of this architecture, worth calling out explicitly:** true redaction (§8 below) is *easier and safer* here than in a text-preserving PDF editor. Because every rebuilt page is a flat rasterized image with no underlying text object ever surviving into the output, a redaction implemented as "black out this region of the *already-rasterized* image, then rebuild" is real, permanent redaction by construction — there is no hidden text layer left to recover, unlike the well-known "black box drawn over live text" anti-pattern the spec explicitly warns against.

---

## 3. Full 46-capability matrix

**Legend — Current State:** A = fully implemented · B = partially implemented · C = implemented but unreliable · D = UI-only/fake · E = missing · F = infeasible offline with current architecture · G = feasible but needs a new dependency.
**Legend — Offline Class:** OFFLINE · OFFLINE+MODEL (local model, downloaded once) · OFFLINE+NATIVE (native lib, no network) · PARTIAL (some local, one part external) · NOT REALISTIC (see note).

### PDF Core

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 1 | Professional PDF Viewer | **B** | OFFLINE (view/zoom/scroll/rotate/share) / NOT REALISTIC (in-page text search-highlight, text selection) | `PdfPreview` (already used everywhere) gives real scrollable/zoomable rasterized-page viewing today, but no dedicated "open any PDF and read it" screen exists — every current `PdfPreview` use is a result-preview tied to one operation. No text-selection or in-page search-highlight is achievable without either a licensed SDK or a from-scratch content-stream text-position mapper (large, not recommended). **Real, honest alternative:** page-level search using the same text-extraction `pdf_parser.dart` already does — jump to the matching page, don't highlight the glyph. |
| 2 | PDF text editing (existing text) | **E** | **NOT REALISTIC** with current architecture | `package:pdf` cannot read/modify an existing PDF's content stream in place — confirmed, this is a generator, not an editor. No permissively-licensed Flutter-compatible true PDF editor exists (ADR-034's own conclusion, re-confirmed). Would need a licensed SDK (Syncfusion/PSPDFKit-class, cost+license review) or a ground-up PDF object-model editor (multi-week, high risk). **Do not fake this as "annotation overlay."** |
| 3 | PDF image editing (move/replace an embedded image) | **E** | **NOT REALISTIC** with current architecture | Same root cause as #2 — no existing-object-graph access. |
| 4 | Add text to PDF | **E**, but **feasible** | OFFLINE | Overlay mechanism (§2) — draw new text at a chosen position on the rasterized page before rebuild. Real, useful, zero new dependency. Must be labeled "add text," never "edit text." |
| 5 | OCR — scanned/image PDF → searchable PDF | **E** | OFFLINE+MODEL | See §5. No OCR exists anywhere in `lib/` — confirmed `ocr_parser.dart` is a deliberate, disclosed, `UnimplementedError`-throwing stub (ADR-015), not registered anywhere. |
| 6 | Scan → searchable PDF | **E**, depends on #5 | OFFLINE+MODEL | Combine existing Scanner pipeline with new OCR: recognize text per page, place an invisible text layer at word bounding boxes via `package:pdf` (standard "searchable scan" technique). Architecturally sound once #5 exists. |
| 7 | Images → PDF | **A** (already built, not exposed standalone) | OFFLINE | `ScannerPdfService` already does exactly this inside the Scan flow. IA gap, not a capability gap — expose as its own entry point. |
| 8 | PDF → Images | **B** (infrastructure exists, no user-facing feature) | OFFLINE | `PdfPageRenderingService` already rasterizes every page on demand. Needs a thin new use case ("export pages as JPG/PNG") + screen, not new rendering logic. |
| 9 | PDF → Word | **E** | PARTIAL | Full layout/table/font-preserving conversion is **not realistic offline** with current or any readily-available permissive dependency. Realistic scope: extract-text-and-flow into a plain-paragraph `.docx` (buildable today via the existing `archive` package, since `.docx` is a zip of XML) — genuinely useful for text-heavy documents, explicitly disclosed as "text content, not exact layout." |
| 10 | PDF → Excel | **E** | **NOT REALISTIC** offline | Requires table-structure detection from unstructured page content — effectively a table-detection ML problem, no existing infrastructure or model. Recommend **not building a fake version** of this; disclose as a real, honest gap. |
| 11 | PDF → PowerPoint | **E**, but **feasible in a limited form** | OFFLINE | One full-page rasterized image per slide, built via the same `archive`-based zip+XML technique as #9. Real and useful (e.g. turning a scanned handout into slides), explicitly disclosed as image-based, non-editable text. |
| 12 | PDF → Text | **B** (extraction logic exists for indexing, not exposed as export) | OFFLINE | `pdf_parser.dart`/`DocumentTextExtractionService` already extracts PDF text for the Documents search index. Needs a thin export wrapper, not new extraction logic. |
| 13-19 | Page rotate / delete / extract / insert / duplicate / replace / reorder | **B** (Organize already covers extract+reorder; the rest are extensions of the same rebuild mechanism) | OFFLINE | All achievable with zero new dependencies — every operation is "choose which rasterized pages, in which order, with which transform, feed to the existing rebuild step." Insert/replace from a second source PDF is a specialized case of the existing Merge architecture. |
| 20 | PDF cropping | **E**, feasible | OFFLINE | Adjust the rasterized page's drawn offset/clip before rebuild — same mechanism, zero new dependency. |

### Security

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 21 | PDF password protection/encryption | **E** | OFFLINE, **but genuinely not "quick"** | **Verified by reading the installed package source, not assumed:** `package:pdf` 3.11.3 exposes an extension *hook* (`PdfDocument.encryption`, an abstract `PdfEncryption` class actually wired into the save path) but ships **no concrete encryption algorithm implementation at all** — no RC4/AES standard-security-handler exists anywhere in the package, and nothing implements the abstract class. Real password protection means either finding a separate, permissively-licensed Dart PDF-encryption package (not yet researched — do this before committing to a timeline) or writing a correct ISO-32000 standard-security-handler from scratch, a security-sensitive undertaking that needs real interoperability testing (Acrobat, other readers), not a quick feature. |
| 22 | PDF permissions/security | **E** | Same as #21 | Same underlying mechanism (the PDF encryption dictionary also carries permission flags) — same caveat applies. |
| 23 | PDF form filling | **E** | **NOT REALISTIC** with current architecture | Requires reading an existing PDF's AcroForm field definitions (positions/types/values) — no such capability exists; `package:pdf` cannot read an arbitrary PDF's object graph at this depth. Needs new-dependency research. |
| 24-25 | Signature placement (draw/type/import) | **E**, feasible | OFFLINE | Capture via a `CustomPainter` drawing canvas (drawn), a script-font text render (typed), or an imported image — then place via the same overlay mechanism as #4. Zero new dependency, high confidence. |
| 26 | PDF annotations (general) | **E**, feasible | OFFLINE | Same overlay mechanism. |

### Annotations

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 27-31 | Highlight / underline / strikethrough / freehand / shapes-arrows-text | **E**, feasible | OFFLINE | All are the same overlay-and-rebuild primitive as #4/#24-26. **Recommend building ONE shared "PDF overlay" infrastructure layer** (a drawable-annotation model + a single "commit overlay, rebuild PDF" service) that add-text, signatures, annotations, and watermark all reuse — not five separate ad-hoc features. |

### Search / Navigation

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 32 | Search inside PDF | **E**, feasible | OFFLINE | Page-level search via existing text extraction — jump to matching page. Zero new dependency. |
| 33 | OCR text search | **E**, depends on #5 | OFFLINE+MODEL | Same mechanism as #32, over OCR'd text once #5 exists. |
| 34 | Bookmarks | **E**, feasible in an honest, app-owned form | OFFLINE | Reading a PDF's *own* `/Outlines` object graph needs the same object-graph access #2/#23 lack. **Recommend app-level bookmarks instead** — the user marks a page-of-interest, stored in our own database against the file, not the PDF's internal structure. Arguably more useful for a personal-document tool than parsing professionally-authored PDF outlines anyway. |

### Document Operations

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 35 | Watermark | **E**, feasible | OFFLINE | Overlay mechanism. |
| 36 | Permanent PDF redaction | **E**, feasible, **and architecturally favorable** | OFFLINE | See §2's closing note — black out a region of the *already-rasterized* page image, then rebuild. Genuinely permanent by construction, not a "black box over live text" risk, because no text object survives rasterization in this pipeline at all. **Must ship with a regression test that verifies no text is recoverable from the redacted region of the output PDF** (per the spec's own explicit requirement) — straightforward here since the output is provably image-only. |
| 37-39 | Image crop / rotate-flip / format conversion | **B** (Resize/Compress exist; crop/rotate/flip/convert as standalone tools don't yet) | OFFLINE | All standard `package:image` operations, same dependency already in use. Zero new dependency. |
| 40 | Batch processing | **E** | OFFLINE | No generic batch/queue infrastructure exists today — each tool processes one item at a time. Scanner's own multi-page session (capture/delete/reorder as a batch, then one commit) is the closest existing precedent. **Recommend one shared `BatchOperationQueue`** (queue/progress/cancel/retry/failure-state), modeled on Scanner's session pattern and this app's own proven `LlmRequestQueue`/model-download-queue conventions — per the spec's own explicit "reusable infrastructure layer, not ad-hoc" instruction. |
| 41 | Better PDF compression with quality presets | **A**, minor room to improve | OFFLINE | Already 5 presets + Custom (fixed DPI/quality tiers). A target-byte-size search (like Image Compress already has) would be a genuine improvement, not a gap — Compress currently can't guarantee "under 2MB," only "this quality tier." |

### File Management

| # | Capability | State | Offline Class | Notes |
|---|---|---|---|---|
| 42-46 | Folder/file management, rename/delete/move/favorite/share, recent files, preview-before-destructive, progress/cancel/error recovery | **B**, and **architecturally split** | OFFLINE | See §6 — this is the most consequential single finding in this audit. |

---

## 4. §5 — OCR: engine choice, sizing, and architecture fit

No OCR exists anywhere in this codebase today (confirmed: `ocr_parser.dart` throws `UnimplementedError`, is not registered in any composition root, and is not called by any parser). `ModelKind` already reserves `ocr` (alongside `vision`/`translation`) in `lib/services/ai/model_catalog.dart` — **zero catalog entries exist for any of the three today**, but the extension point is already there, unused.

**Two realistic candidates, both genuinely offline (inference never touches the network):**

1. **Tesseract** (via a Flutter FFI/plugin wrapper — needs a specific package chosen and evaluated, not yet done). Apache-2.0 core engine. Language data (`.traineddata`) is the size driver, not the engine binary — English alone is roughly 15-30MB depending on the trained-data variant chosen (fast vs. best-accuracy). **Fits this app's existing architecture exactly**: reuse the already-built `ModelCatalog`/download-after-install/`InstalledModelRepository` machinery (the same system managing LLM/embedding/Whisper models today) by finally populating the reserved `ModelKind.ocr` catalog entry — no new download/resume/verify infrastructure needed, just a new catalog row and engine wrapper.
2. **Google ML Kit Text Recognition** (`google_mlkit_text_recognition`, Apache-2.0 plugin). Faster to integrate, genuinely on-device inference, but its own small models are provisioned through Google Play Services' own mechanism on first use — outside this app's own download-after-install control and disclosure UX, a real architectural inconsistency with how every other model in this app is managed and disclosed to the user.

**Recommendation:** Tesseract, specifically because it slots into the existing model-management architecture the user has already been trained to understand (download state, active/installed, size shown, removable) rather than introducing a second, differently-behaved provisioning path. Ship the language data as a **download-after-install model**, never bundled — matching this pass's own explicit "prefer download-after-install for large models" instruction and this project's own recent, hard-won APK-size discipline (LiteRT-LM removal). Exact package/version selection and a size/accuracy bake-off between Tesseract variants is a P0 implementation-phase task, not concluded here.

**Must document once built, per the spec's own requirement:** supported languages (start with English only, most likely), model size, download requirement, accuracy limitations (Tesseract's accuracy on skewed/low-contrast phone-camera scans is real but not perfect — set expectations honestly), processing time per page, and device resource requirements.

---

## 5. §6 — File management: two parallel, non-unified systems

This is the most consequential architectural finding in this audit. Two independent "my files" experiences exist today, confirmed by direct code inspection:

| | Documents feature (`lib/features/documents/`) | Toolkit Recent Files (`lib/features/student_toolkit/`) |
|---|---|---|
| Storage | `documents` table, FTS5-indexed (workspace-searchable) | `toolkit_files` table (migration v11/v12), **deliberately no FTS5 entry** — ADR-033: "toolkit outputs aren't searchable workspace knowledge" |
| Folders | Yes | No |
| Search | Yes (added this same session, `docs/v3` Part D) | No |
| Sort | Yes (same) | No |
| Favorites | No (confirmed via grep — no favorite handling anywhere in `documents_screen.dart`) | Yes |
| Multi-select | No (disclosed gap, `docs/v3` Part D) | No |
| Rename/move/delete | Yes | Rename/delete/duplicate yes; move — no folders to move into |

This directly contradicts the spec's own stated goal ("a coherent... professional document manager," not two half-built ones). **Two real options, not a forced third:**

- **(a) Bring Toolkit Recent Files to feature parity** (search/sort/folders/multi-select) while keeping the two stores separate — lower risk, respects ADR-033's original, deliberate "toolkit outputs aren't Knowledge Sources" decision, smaller diff.
- **(b) Genuinely unify** the two into one file manager surface, either by merging `toolkit_files` into `documents` (a real schema/architecture change, reverses ADR-033) or by building one UI shell that reads both tables side-by-side (less invasive than a schema merge, but a new cross-table UI layer).

**Recommendation:** (a) first, as the P0-safe default — (b) is a legitimate larger ambition worth a dedicated, explicitly-approved follow-up phase given its architectural reversal of a deliberate prior decision, not something to fold into this pass silently.

---

## 6. Required new dependencies — summary

| Dependency need | For | License/size consideration |
|---|---|---|
| An OCR engine (Tesseract-class) | #5, #6, #33 | Apache-2.0-class engine, ~15-30MB *language data* per language — **download-after-install, never bundled**. Exact package TBD in P0. |
| A PDF-encryption implementation | #21, #22 | Either a new permissively-licensed package (research needed) or hand-written crypto — see §3's own caveat. No package identified/vetted yet. |
| **No new dependency needed** | #1 (viewer, minus text-select/search), #4, #7-9 (limited), #11-20, #24-31, #32, #34-41 | All achievable via `pdf`/`printing`/`image`/`archive` — every one already a dependency today. |
| **Not recommended to build at all** | #2, #3, #10, #23 | Genuinely infeasible offline with current or readily-evaluated dependencies — see each row's own note in §3. |

**Explicitly avoided, per this pass's own instruction:** no reintroduction of a heavy runtime (LiteRT-LM-class) is proposed anywhere in this plan. Every recommended addition either reuses an existing dependency or is a download-after-install model, never a bundled native asset.

---

## 7. Recommended implementation order (validated against feasibility, not blindly following the spec's own priority list)

The spec's own P0 list is largely sound but includes two items (#2 true text editing, #12/form-filling-adjacent capability) that are **not realistic** with current architecture and should not be attempted as literally stated. Revised:

**P0 (build this pass, in this order):**
1. Fix the 5-instance `PdfPreview`-missing-`onError` bug (§1's new finding) — small, safe, immediately improves reliability of everything else built on `PdfPreview`.
2. Shared PDF-overlay infrastructure (one drawable-annotation model + commit-and-rebuild service) — the foundation #4, #24-31, #35 all build on.
3. Add Text to PDF, Annotations, Signatures, Watermark (all thin layers over #2).
4. Permanent Redaction (with its own dedicated non-recoverability regression test).
5. Page rotate/delete/extract/insert/duplicate/replace (extends existing Organize/Merge architecture).
6. PDF cropping.
7. Images → PDF, PDF → Images as standalone entry points (already-built infrastructure, just needs exposure).
8. Page-level PDF search (uses existing text extraction).
9. App-level bookmarks.
10. Password protection — **only after** the encryption-package research in §3/§6 concludes it's genuinely tractable in-scope; otherwise explicitly deferred and disclosed, not rushed.
11. OCR engine integration (Tesseract, reusing `ModelCatalog`) + Scan → searchable PDF + OCR text search.
12. Professional PDF viewer (view/zoom/scroll/rotate/share/page-search — not text-selection).
13. File manager parity (§5 option (a)).

**Explicitly NOT P0, moved to P1/P2 or dropped:**
- True PDF text/image editing (#2/#3) — **do not build**, infeasible with current architecture; revisit only if a licensed SDK is explicitly approved.
- PDF → Excel (#10) — **do not build a fake version**; disclose as a real gap.
- PDF form filling (#23) — needs new-dependency research before any timeline commitment; not P0.
- PDF → Word/PowerPoint (#9/#11) — real but lower-fidelity versions are buildable; P1, not P0, given their disclosed quality ceiling.
- Batch processing infrastructure (#40) — genuinely valuable but a distinct infrastructure investment; P1, built once the individual P0 operations it would batch already exist.

---

## 8. Proposed navigation/IA

The spec's proposed PDF/IMAGE/DOCUMENT CONVERSION/FILES structure is broadly sound but should extend, not replace, what exists: Home already surfaces a distinct "Productivity Toolkit" Quick Action tile (confirmed, `home_screen.dart`), leading to `StudentToolkitScreen`'s existing three sections (Scanner/Image Tools/PDF Tools, confirmed via `_ToolSection` widgets). Recommend keeping that entry point and three-section shell, but:
- Rename the module's user-facing label consistently to "Productivity Toolkit" everywhere (Home already does; internal code/route names staying `toolkit`/`studentToolkit` is fine, cosmetic only).
- Add a fourth section, "Convert" (PDF→Text/Word/PowerPoint/Images, Images→PDF), rather than scattering conversions across the existing three sections.
- Fold "Files" (Recent Files + eventual parity work from §5) into the existing bottom-nav Documents-adjacent surface rather than inventing a fifth top-level nav destination — the spec's own "few taps" goal is better served by not adding a new nav root.

Do not implement a 40-button flat grid — every new tool should land inside one of these four sections, not as a fifth Home tile.

---

## 9. Risks (new, this audit — supplementing R-30 through R-34, all confirmed still Open)

- **PDF encryption is a security-sensitive undertaking, not a quick feature** (§3/§6) — shipping a broken/incompatible encryption implementation would be worse than not shipping one; must not be rushed to hit a priority-list checkbox.
- **OCR accuracy on real phone-camera scans is unverified** until a real device is available — same standing "no physical device in this implementation environment" limitation this entire project has disclosed since Phase 0 of V2.
- **The overlay-infrastructure recommendation (§3) is a real design decision**, not free — building 8 features (add-text/signatures/annotations×5/watermark) on one shared primitive is the right call, but the shared primitive itself needs its own dedicated design/test pass before the first feature built on it ships, or all 8 inherit the same bug.
- **File-manager unification (§5) touches a deliberate prior architectural decision (ADR-033)** — reversing it should be an explicit, separately-approved decision, not a side effect of "add search to Recent Files."

## 10. Features that should NOT be implemented, stated plainly

- True in-place PDF text editing (#2) and embedded-image editing (#3) — infeasible offline with current or readily-available dependencies; faking it as "annotation overlay" is explicitly against the spec's own instruction.
- PDF → Excel (#10) — no honest offline path exists; do not ship a poor-quality version to check the box.
- A flat 40+ button Home screen — explicitly against the spec's own stated product principle.
- Any cloud-processing fallback for any capability — the spec's own non-negotiable; nothing above requires one, and nothing should quietly introduce one for convenience.

---

**Next step, per this audit's own conclusion:** proceed to implementation planning for P0 items 1-9 (all zero-new-dependency, high-confidence), park items 10-13 (password protection, OCR, viewer, file-manager parity) behind their own short dependency/scope confirmation before implementation begins, per this document's own §3/§5/§6/§7 caveats — not because they're out of scope, but because each has a real open question (encryption package choice, OCR package choice, file-manager-unification decision) that implementation should not guess past.
