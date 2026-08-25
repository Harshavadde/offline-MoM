# Data Processing Agreement (DPA)

## Why this document looks different from a typical DPA

A Data Processing Agreement normally governs the relationship between a **data controller** (an organization that decides why/how personal data is processed) and a **data processor** (a vendor that processes that data on the controller's behalf) — for example, a company and its cloud email provider. That relationship requires a second party actually receiving and processing data.

OfflineMoMAI has no such second party. All processing — recording, transcription, summarization, storage — happens locally on the end user's own device, by software the user controls directly. There is no vendor, no server, and no third party in the loop that receives meeting data. The one network interaction the app makes (downloading a generic AI model file from Hugging Face on first use) does not involve the user's data at all — see [`privacy-policy.md`](privacy-policy.md).

**Conclusion: no data processing agreement is required for OfflineMoMAI's core functionality, because no processing of personal/meeting data by any party other than the device owner occurs.** This document exists to state that conclusion explicitly, since its absence might otherwise look like an oversight.

## When this would need to change

If a future version of OfflineMoMAI introduced any of the following (all currently out of scope — see [`docs/01-executive-summary.md`](../01-executive-summary.md)), a real DPA would become necessary and would need to specify at minimum: the categories of data processed, the purpose and duration of processing, sub-processors used, data subject rights procedures, and breach notification terms:

- Cloud sync or backup of meeting data
- A backend server of any kind
- Any third-party analytics or crash-reporting SDK
- An enterprise/organizational deployment where an admin account can access other users' meeting data

## Organizational use

If an organization deploys OfflineMoMAI to its members for recording internal meetings, the organization itself is the data controller for whatever gets recorded (it decides what meetings get recorded and by whom); the app is simply a local tool each member's device runs, not a processor acting on the organization's behalf. Organizations should apply their own internal data-handling policy to devices running this app, the same way they would for any local recording tool (e.g. a standalone dictaphone).
