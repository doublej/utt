# Recording

## What this is

Audio capture — device selection, idle suspension, and the tap that hands
buffers to transcription.

## Invariants

- **`CaptureController` is not actor-isolated.** The audio tap runs on a
  real-time thread; inheriting main-actor isolation traps in
  `_swift_task_checkIsolatedSwift` on the first buffer.
- **`AVAudioPCMBuffer` never crosses an isolation boundary as itself** — see
  `.claude/rules/isolation-boundaries.md`. Snapshot peak and frame counts to
  values before they leave the real-time thread.
- **A device is named by its CoreAudio UID, not its `AudioDeviceID`.** A UID is
  not something any system tool hands out outside a CoreAudio client —
  `devices.json` exists to export it, and `SettingsFeature` re-enumerates
  devices every 3 s to keep it current. This is also what the Raycast
  extension's `microphonePriority` list is written in (see
  `raycast/README.md`), since an `AudioDeviceID` is only valid until the next
  reboot.

## Related context

- `.claude/rules/isolation-boundaries.md`
- `raycast/README.md` — the device-UID contract from the other side
