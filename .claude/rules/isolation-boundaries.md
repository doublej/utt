---
paths:
  - "Utt/Clients/Recording/**"
  - "Utt/Clients/Input/**"
  - "Utt/Clients/Transcription/**"
---

# Isolation boundaries

`AVAudioPCMBuffer` and `CGEvent` never cross an isolation boundary as
themselves. Snapshot to values (peak, frame counts, keycode, flags) before
they leave the thread that produced them.

`CaptureController` is not actor-isolated — the audio tap runs on a real-time
thread, and inheriting main-actor isolation traps in
`_swift_task_checkIsolatedSwift` on the first buffer. `LiveTranscriptionClient`
runs beside it on the same real-time boundary.

This isn't style — a `Task`, or a closure that captures `Sendable` state,
silently hops onto the actor that created it, and a real-time audio or event-tap
callback cannot wait for the main actor without glitching or crashing.
