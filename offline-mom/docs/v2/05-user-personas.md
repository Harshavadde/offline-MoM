# V2 User Personas

V1's `docs/02-prd.md` already established six personas (Student, Teacher, Developer, Small team lead, Researcher, Traveler). The Traveler persona was tied specifically to the Conversation Translator and is retired along with that feature — not carried forward here. The other five carry forward unchanged and gain new needs from the Documents/Chat/Search modules, listed below. Three new personas are added, specifically because they represent segments for whom cloud AI tools are not just undesirable but often disqualifying.

## Carried forward, with new needs

| Persona | V1 need | New V2 need |
|---|---|---|
| **Student** | Record a lecture, get a searchable transcript | Import lecture slides (PDF) and readings (DOCX/text), then ask questions that draw on both the recording and the reading for one exam-prep session |
| **Teacher** | Private record of meetings | Chat with a semester's worth of meeting notes and policy documents at once instead of re-reading each one |
| **Developer** | Standup/design-review notes | Import a design doc or RFC (Markdown), chat with it alongside the meeting where it was discussed |
| **Small team lead** | Distribute a formal MoM | Search across every meeting and every shared document from one place to answer "did we already discuss this" |
| **Researcher** | Transcribe interviews offline | Import related papers/PDFs and cross-reference them against interview transcripts without any of it touching a server |

## New personas

| Persona | Need | Why cloud AI tools don't work for them |
|---|---|---|
| **Legal professional** (associate, paralegal, solo practitioner) | Record client meetings, import contracts/filings, ask questions across a case file without violating privilege | Attorney-client privilege makes sending case material to a third-party server a professional-conduct risk, not just a preference |
| **Healthcare practitioner** (clinician, therapist, care coordinator) | Keep private notes on patient-related meetings/consults, reference prior notes without re-reading everything | Patient information handling is subject to regulatory expectations that a zero-transmission architecture is structurally suited to, even without claiming a specific formal certification (see [16-security.md](16-security.md)) |
| **Journalist / investigative researcher** | Record interviews, import source documents, chat across them while building a story | Source protection is fundamentally incompatible with any tool that transmits recordings or notes off-device, AI-powered or not |

## What's explicitly the same across all personas

Every persona above shares the same non-negotiable requirement that already defines V1: nothing they record, import, or ask leaves their device except the one-time model download. V2 does not create a tiered privacy model where some personas get stronger guarantees than others — the architecture in [10-system-architecture.md](10-system-architecture.md) and [17-privacy.md](17-privacy.md) applies uniformly.

## Addendum (Phase 5A/5B, not in this document's original scope): Student Toolkit personas

This document predates the Student Toolkit (Image Tools/Scanner/PDF Tools) and was not rewritten to add it, per this document set's own frozen-spec convention (see [README.md](README.md)). The Toolkit's real-world workflows (ADR-033/034, `docs/v2/implementation/03-decisions.md`) already imply a broader persona set than the table above covers: **job seeker** (resume/certificate compression for portals), **freelancer/accountant/small business owner** (invoices, receipts, ID documents), in addition to the **Student** persona already listed. These are recorded here as an observation for whoever next revises personas formally, not as a resolved addition to the table above — see [20-future-roadmap.md](20-future-roadmap.md)'s "Productivity Toolkit" section for the related product-naming question this raises.
