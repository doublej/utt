Two fixes to how utt feels in use. Everything in 0.1.0 still holds: hold a hotkey,
speak, release, and the transcript lands at your cursor, transcribed on-device.

## The first press after typing now records

The hotkey used to need pressing twice if you had not used it recently — and
pressing it twice quickly enough instead tripped the double-tap lock, so the way
out of the bug was the other bug.

The event tap reported a key-up as *still holding* the key it had just released,
which made a press and its release identical events. The processor tracks whether
other typing has happened since the hotkey was last idle, and that flag could only
clear on a genuinely empty chord — which, with a key-up that never let go, only
arrived when you lifted the last modifier. So the first hotkey after any typing was
spent clearing the flag, and only the second one recorded.

## The recording indicator no longer bands on a light background

The darkening behind the dot grid was four hand-placed gradient stops, and every
stop is a kink in the slope. The eye finds a slope change far sooner than a value
change, so on a white document it read as concentric rings. It is now sampled off a
smootherstep curve, which arrives out of nothing and leaves into nothing.

What survives that is plain 8-bit banding: a ramp this wide holds each of its 255
available levels for tens of points. A layer of alpha noise, composited last so it
lands before the framebuffer rounds, dithers it away. Its amplitude is the new
`dither` key in `overlay.json`; `0` turns it off.

## Install

**Requires macOS 26 or later on Apple silicon.**

This build is signed with a self-signed certificate and is **not notarized by
Apple**, so Gatekeeper will not open it unaided.

1. Download `utt.zip` below, unzip, drag `utt.app` into `/Applications`.
2. Clear the quarantine flag:

   ```bash
   xattr -dr com.apple.quarantine /Applications/utt.app
   ```

   Without this, the first launch fails with *"utt is damaged and can't be
   opened"* or *"Apple could not verify utt is free of malware."* Neither message
   means what it says — both are the same missing-notarization check.

3. Grant **Microphone**, **Input Monitoring** and **Accessibility**. macOS asks
   for each exactly once per app, ever. Restart utt after granting the last two; a
   hotkey listener created before the grant landed stays dead until the app
   relaunches.
4. First launch downloads Parakeet TDT v3 (~650 MB) into
   `~/Documents/huggingface/`. That is the only network traffic utt makes.

Upgrading from 0.1.0: replace the app and relaunch. The signing certificate has not
changed, so the permission grants carry over.

Full guide, including uninstall: [docs/INSTALL.md](../blob/main/docs/INSTALL.md).

## Known limits

Unchanged from 0.1.0: not notarized, no auto-update (Sparkle is wired in but has no
feed URL or signing key), Apple silicon only, macOS 26 floor.
