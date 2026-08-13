# Phase 0 — results

All four feasibility checks pass, plus the signing prerequisite. Verified on
macOS 26.6 (25G72), Xcode 26.6, Swift 6.3.3, M2 Pro.

## Signing

| | |
|---|---|
| Identity | `utt Dev` — `A4F985E255EAA49E09BCA155A81331F318CA59CB` |
| Keychain | `~/Library/Keychains/utt-dev.keychain-db` (password `uttdev`, no-timeout) |
| Backup | `<scratchpad>/signing/utt-dev.p12` — **move to 1Password; losing it resets every TCC grant** |
| Designated requirement | `identifier "dev.jurrejan.utt" and certificate root = H"a4f985e2…59cb"` |

Trust settings turned out to be **unnecessary**. `codesign` accepts the identity by
SHA-1 hash with no sudo, no trust dialog, and no login-keychain password. The cost is
that `security find-identity -v -p codesigning` reports **0 valid identities**, because
`-v` applies the trust policy. Anything in the build path that enumerates identities
that way (Xcode's automatic signing, fastlane, CI) will claim no identity exists.

**The Justfile must hardcode the hash and fail if it is missing.** utty's recipe falls
back to `-` (ad-hoc) when the lookup returns nothing — which here would silently
ad-hoc-sign every build, changing the DR each time and resetting all TCC grants.

## The four checks

| # | Check | Result |
|---|---|---|
| 1 | `.cgSessionEventTap` + `.defaultTap` delivers keys and can swallow | ✅ |
| 2 | `CGEvent.post` of ⌘V lands in another app | ✅ |
| 3 | `AVAudioEngine` captures with a real usage description | ✅ |
| 4 | FluidAudio downloads, loads, transcribes | ✅ |

Checks 1 and 2 were proven together against a throwaway TextEdit document, which ended
up containing exactly `autt-spike-paste-ok`:

- `a`, with the tap returning the event → arrived
- `b`, with the tap returning `nil` → **never arrived**, so `.defaultTap` genuinely suppresses
- `utt-spike-paste-ok` → synthesized ⌘V pasted into a foreign app

Check 4 timings, cold: models 25.9 s (download + ANE compile), manager load 0.0 s,
transcribe 0.1 s for a 3.0 s clip (rtfx 23×; 51× on a 6.6 s clip).

## What the spike changed about the plan

1. **`com.apple.security.device.audio-input` is required after all.** The plan dropped it
   on the grounds that disabling the App Sandbox made it unnecessary. True for the
   sandbox, false for the **Hardened Runtime**, which is mandatory for notarization.
   Without it the mic is denied outright: no prompt, instant `false`, no TCC record.
   This cost an hour of misdiagnosis.

2. **Never block the main thread waiting on a TCC prompt.** A `DispatchSemaphore.wait`
   around `AVCaptureDevice.requestAccess` starves the run loop the prompt needs, so the
   dialog never renders and the callback never fires. Pump the run loop instead.

3. **Audio capture must not be main-actor isolated.** Top-level Swift code is `@MainActor`,
   so a tap closure written inline inherits that isolation and traps with
   `EXC_BREAKPOINT` in `dispatch_assert_queue_fail` → `_swift_task_checkIsolatedSwift`
   the moment the real-time audio thread calls it. Capture state belongs in a plain
   nonisolated class. (Plan correction #6, now with a stack trace.)

4. **`TdtDecoderState` needs a nonisolated *context*, not just a local var.** The recon's
   "must be a local `var`" is incomplete — a local var in main-actor-isolated top-level
   code still fails with *"actor-isolated var cannot be passed 'inout' to async function
   call"*. It must be local to a nonisolated function.

5. **Input level is load-bearing.** The raw 3 s recording peaked at 0.0189 (−34 dBFS) and
   transcribed to **empty text**. Normalized to −3 dBFS, the same audio transcribed fine.
   Neither reference app normalizes. Phase 3 needs gain handling or at minimum a
   too-quiet warning, or users hit silent empty transcripts.

6. **`NSPasteboard.changeCount` is bumped by `clearContents()`, not `setString`.** The
   value to capture for the restore guard is `clearContents()`'s return value.

7. **TCC prompting is a product problem, not spike friction.** macOS prompts *once per app
   per service, ever*, and a granted permission never reaches a process that already
   asked — it needs a relaunch. Four of the spike's runs failed on this. Phase 4's
   first-run bootstrap must check state, deep-link the exact pane, and detect-and-relaunch
   after a grant rather than assuming a prompt appears.

8. **AirPods present a 24 kHz input format**, so the resample-to-16 kHz path is exercised
   on ordinary hardware, not an edge case.

## Reproducing

```
spike/build.sh          # compile + sign Spike.app as dev.jurrejan.utt
spike/run.sh            # throwaway TextEdit doc → run → results → cleanup
spike/asr/  swift run asrspike [wav]   # FluidAudio check
```

`tccutil reset ListenEvent|PostEvent|Accessibility|Microphone dev.jurrejan.utt` re-arms
the prompts. It works unprivileged.
