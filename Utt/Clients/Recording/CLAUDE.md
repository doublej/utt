# Recording

## What this is

Audio capture — device selection, idle suspension, and the tap that hands
buffers to transcription.

## Invariants

- **The real-time boundary** (`CaptureController` not actor-isolated,
  `AVAudioPCMBuffer` snapshotted to values) — see
  `.claude/rules/isolation-boundaries.md`.
- **A device is named by its CoreAudio UID, not its `AudioDeviceID`**, which is
  only valid until the next reboot. No system tool hands out UIDs, so
  `devices.json` exports them and `SettingsFeature` re-enumerates devices every
  3 s to keep it current. The Raycast extension's `microphonePriority` list is
  written in UIDs too (see `raycast/README.md`).
