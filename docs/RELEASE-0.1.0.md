Hold a hotkey, speak, release. The transcript lands at your cursor in whatever app
you were already typing in. Transcription runs on-device with Parakeet TDT v3
(WhisperKit is selectable as the alternative engine). Nothing is uploaded, ever.

Recording actually starts about 0.45 s *before* the keypress — a rolling buffer
means a word already in flight when you reach for the key still makes the
transcript. That is why the microphone indicator stays lit while utt runs; the
engine stands down on sleep and screen lock, and the whole thing has an off
switch in Settings → Recording.

| Gesture | What happens |
|---|---|
| Hold the hotkey | Records while held, transcribes on release |
| Double-tap it | Locks recording on; tap again to stop |
| Escape | Cancels without transcribing |
| ⌥⇧V | Pastes the last transcript again |

Releasing *any* part of the combination ends the recording — with ⌃P, letting go
of either ⌃ or P is enough. So is tapping P twice with ⌃ held down.

While recording, a dot-matrix indicator sits in the middle of the screen, above
full-screen apps and on every space, cycling faster the louder you speak. It never
takes focus, so it cannot disturb the app you are dictating into. Its size, glow
and darkening are all editable in
`~/Library/Application Support/dev.jurrejan.utt/overlay.json`.

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

   Prefer clicking? Double-click `utt.app`, click **Done** on the block, then
   **System Settings → Privacy & Security → Open Anyway**. If the message said
   *damaged* and there is no Open Anyway button, use the command instead.
3. Grant **Microphone**, **Input Monitoring** and **Accessibility**. macOS asks
   for each exactly once per app, ever — miss a prompt and the only route back is
   System Settings. Restart utt after granting the last two; a hotkey listener
   created before the grant landed stays dead until the app relaunches.
4. First launch downloads Parakeet TDT v3 (~650 MB) into
   `~/Documents/huggingface/`. That is the only network traffic utt makes.

Full guide, including uninstall: [docs/INSTALL.md](../blob/main/docs/INSTALL.md).

## Known limits

- **Not notarized.** Every fresh download needs the quarantine step. A Developer
  ID account fixes it; there isn't one yet.
- **No auto-update.** Sparkle is wired in but has no feed URL or signing key, so
  the update affordances stay hidden. Updating means swapping the app by hand.
- **Apple silicon only**, macOS 26 floor.
- **Permission grants are certificate-bound.** They survive updates as long as
  the signing certificate holds. If a future release ever resets them, that is
  why — re-grant once and they stick again.
