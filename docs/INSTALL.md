# Installing utt

utt is **not notarized by Apple**. It is signed with a self-signed certificate,
which is enough to keep macOS permission grants stable but not enough for
Gatekeeper to let it open on its own. Getting past that is one command or four
clicks — both are below.

**Requirements:** macOS 26.0 or later, Apple silicon (M1 or newer).

## 1. Download

Grab `utt.zip` from the [latest release](../../releases/latest) and unzip it.
Drag `utt.app` into `/Applications`.

## 2. Get past Gatekeeper

Because the build is not notarized, macOS quarantines it on download and refuses
the first launch with *"utt is damaged and can't be opened"* or *"Apple could not
verify utt is free of malware"*. Neither message means what it says — they are
both the same missing-notarization check.

### The one-liner (recommended)

```bash
xattr -dr com.apple.quarantine /Applications/utt.app
```

That strips the download flag. Open utt normally afterwards. Nothing else about
the app changes — the signature stays intact, which matters for step 4.

### The click path

If you would rather not run a terminal command:

1. Double-click `utt.app`. macOS blocks it — click **Done**.
2. Open **System Settings → Privacy & Security**.
3. Scroll to the **Security** section. There is a line saying *"utt was blocked
   to protect your Mac"* with an **Open Anyway** button. Click it.
4. Authenticate, then confirm **Open Anyway** in the dialog that follows.

macOS remembers the decision; you only do this once per installed copy.

> If you see *"damaged and can't be opened"* with **no** Open Anyway button, the
> click path won't work — use the one-liner above. That variant of the message
> appears when the quarantine flag survived unzipping and Gatekeeper never got as
> far as checking the signature.

## 3. Grant three permissions

On first launch utt asks for:

| Permission | Why |
|---|---|
| **Microphone** | to hear you |
| **Input Monitoring** | to see the hotkey while another app is focused |
| **Accessibility** | to paste the transcript at your cursor |

macOS prompts for each of these **exactly once per app, ever**. If you dismiss a
prompt, the only way back is System Settings → Privacy & Security → the relevant
list. utt deep-links you there instead of re-prompting, because re-prompting is
not something an app is allowed to do.

Input Monitoring and Accessibility need utt to be **restarted** after you toggle
them on. A hotkey listener created before the grant landed stays dead until the
app relaunches.

## 4. First run downloads the model

utt transcribes on-device, so it fetches Parakeet TDT v3 (~650 MB) the first
time. It lands in `~/Documents/huggingface/`. Nothing is uploaded, then or ever.

## Updating

In-app updates are not wired up yet (no signed appcast). To update: quit utt,
replace `/Applications/utt.app` with the new build, and run the `xattr` command
again.

Your permission grants survive the swap as long as the release is signed with the
same certificate, which is the plan for every build from this repo. If a future
release ever resets your permissions, that is why — re-grant them once and they
stick again.

## Uninstalling

```bash
rm -rf /Applications/utt.app
rm -rf ~/Library/Application\ Support/dev.jurrejan.utt
rm -rf ~/Documents/huggingface        # the transcription model, ~650 MB
defaults delete dev.jurrejan.utt 2>/dev/null
```

Then remove utt from System Settings → Privacy & Security → Microphone, Input
Monitoring and Accessibility.

## Building it yourself instead

If you have Xcode, skipping the whole Gatekeeper question is an option:

```bash
git clone <this repo>
cd utt
just install   # generate the Xcode project
just run       # build and launch
```

You need [XcodeGen](https://github.com/yonaskolb/XcodeGen),
[SwiftLint](https://github.com/realm/SwiftLint) and
[just](https://just.systems). Note that `project.yml` pins a signing identity
that only exists on the author's Mac — set `CODE_SIGN_IDENTITY` to your own, or
to `-` for ad-hoc signing, and accept that ad-hoc changes the designated
requirement on every build, so macOS re-asks for all three permissions each time
you rebuild.
