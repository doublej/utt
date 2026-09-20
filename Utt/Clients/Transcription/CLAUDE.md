# Transcription

## What this is

Engine dispatch — Parakeet TDT v3 via FluidAudio (default) and WhisperKit, plus
the streaming recogniser that drives the live-words preview.

## Invariants

- **A model is named, never assumed.** `selectedModel` is a stored string read
  through `ModelCatalog.resolve(id:engine:)`, which falls back to the engine's
  recommendation — a settings file can name a model from an older build or from
  the *other* engine, and the alternative to falling back is an app that cannot
  transcribe until you edit JSON. The engine actors track what they loaded, or
  switching model keeps transcribing on the old weights.
- **Live words are provisional and never reach the cursor.** The streaming
  recogniser (Parakeet EOU 120M, `LiveTranscriptionClient`) runs beside the real
  one — sharing `CaptureController`'s real-time boundary, see
  `.claude/rules/isolation-boundaries.md` — on its own weights and its own
  download; the clip on disk is still what becomes the transcript. It is
  English only, it decodes a quiet or synthetic clip to *nothing at all* rather
  than to something wrong — the spike proved both (see
  [docs/phase0-results.md](../../../docs/phase0-results.md)) — and FluidAudio's
  custom vocabulary biasing is batch-only, so streaming and a vocabulary list
  are alternatives rather than a stack.

## Common change patterns

- **Add a model** → one entry in `ModelCatalog` (`UttCore`), plus the matching
  case in `ParakeetClient.version(for:)` if it is a Parakeet one. Whisper ids
  are folder names in `argmaxinc/whisperkit-coreml` and are passed through
  verbatim, so a typo fails at download time, not at compile time.

## Related context

- [docs/phase0-results.md](../../../docs/phase0-results.md) — what the spike
  proved about FluidAudio's API surface
- `.claude/rules/isolation-boundaries.md`
