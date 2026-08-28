# Installing utt

utt is signed with a Developer ID certificate and notarized by Apple, so it
installs like any other Mac app — no terminal commands, no security overrides.

**Requirements:** macOS 26.0 or later, Apple silicon (M1 or newer).

## 1. Install

Grab `utt-<version>.dmg` — the file name carries the version it installs — from
the [latest release](../../releases/latest), open it, and
drag `utt.app` onto the `Applications` shortcut in the same window. Eject the
disk image afterwards.

## 2. Grant three permissions

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

## 3. First run downloads the model

utt transcribes on-device, so it fetches Parakeet TDT v3 (~650 MB) the first
time. It lands in `~/Documents/huggingface/`. Nothing is uploaded, then or ever.

## Updating

utt updates itself. It looks for a new version once a day and tells you when
there is one, with a summary of what changed and the choice to install it, be
reminded later, or skip it. Nothing installs on its own. **Check for Updates…**
in the menu bar asks straight away.

Checking sends nothing about you or your machine, and every update is signed —
utt will not install one that is not.

Your permissions survive an update. Every release is signed by the same
Developer ID team, and macOS keys the grants to that team rather than to an
individual certificate, so even a certificate renewal leaves them alone.

Replacing `/Applications/utt.app` from a new disk image by hand still works if
you would rather do it that way.

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

If you have Xcode:

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
