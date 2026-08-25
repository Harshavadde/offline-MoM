# Ethical AI Statement

## Consent to recording

OfflineMoMAI records or processes audio only when a user explicitly initiates it (tapping "Start recording" or picking a file to import) — there is no background or passive listening mode. The app has no way to know whether every participant in a recorded meeting has consented to being recorded; **this responsibility rests with the person operating the app**, under whatever consent laws apply in their jurisdiction (many require all-party consent, not just the recorder's). This is stated explicitly in the Terms of Service and should be treated as a real ethical obligation, not a formality.

## Fairness and bias

Whisper and Qwen2.5-1.5B are general-purpose, third-party pre-trained models the project did not train or fine-tune. Known limitations of models in this class, inherited by this app, include:

- Reduced transcription accuracy for accents, dialects, or speech patterns underrepresented in the models' training data.
- Possible bias in what a small LLM considers "important" enough to summarize, shaped by whatever data Qwen2.5-1.5B was trained on, which this project has no visibility into or control over.
- Uneven transcription accuracy across the app's supported languages — Whisper's training data is not balanced across languages, so accuracy for lower-resource languages may be meaningfully weaker than for higher-resource ones, and this project has no per-language quality evaluation to disclose a specific ranking.

No bias evaluation specific to this app's use case (meeting summarization) was performed (it would require a labeled, diverse set of real recordings across all supported languages, which this project did not have access to). This is disclosed as a limitation, not resolved.

## Human dignity and autonomy

The AI in this app assists a human decision-maker; it does not replace one. Summaries are suggestions/best-effort output for the user to review, not directives, and nothing in the app auto-executes an action item or notifies anyone based on AI output — the user always chooses whether and how to act on what the AI produced. Deleting a meeting deletes its AI-generated content along with everything else — a user's right to remove their own data is never overridden by any "the AI already processed it" consideration, since all processing already happened locally on their own device to begin with.

## Accountability

This project, its architecture, and its known limitations are documented publicly in this repository (`docs/`) rather than treated as an opaque black box — including the deliberate model-size trade-offs, the gaps in on-device validation, and the toolchain issues encountered building it. Anyone evaluating or extending this project can see exactly what the AI does, how, and where it's known to fall short.

## Environmental consideration

Running inference on-device (rather than in a data center) shifts energy cost to the user's own hardware in small, per-use increments rather than a centralized, continuously-running cloud service — arguably a lower aggregate energy footprint for occasional/personal use, though this was not formally measured as part of this project.
