# utt

Native macOS on-device transcription — hold a hotkey, speak, release, text at the cursor.

Nothing is uploaded. Transcription runs locally on Parakeet TDT v3 (via
FluidAudio), with WhisperKit as the alternative engine.

## Install

Download `utt-<version>.dmg` from the [latest release](../../releases/latest),
open it, and drag `utt.app` onto the `Applications` shortcut inside.

The disk image is signed and notarized, so there is no quarantine flag to clear.
[docs/INSTALL.md](docs/INSTALL.md) has the three permissions utt needs and how to
uninstall.

## Requirements

- macOS 26.0+, Apple silicon
- To build it yourself: Xcode 26,
  [XcodeGen](https://github.com/yonaskolb/XcodeGen),
  [SwiftLint](https://github.com/realm/SwiftLint), [just](https://just.systems)

## Getting started

```bash
just install   # generate the Xcode project
just run       # build and launch
just check     # the full gate before committing
```

The first launch downloads the model (~650 MB) and asks for three permissions:
Microphone, Input Monitoring and Accessibility. macOS prompts for each of these
exactly once per app, ever — after that the only route is System Settings, which
is why utt deep-links there instead of re-prompting.

## Using it

| | |
|---|---|
| Hold the hotkey | record while held, transcribe on release |
| Double-tap it | lock recording on; tap again to stop |
| Escape | cancel without transcribing |
| ⌥⇧V | paste the last transcript again |

The window has two shapes: a floating pill that stays out of the way, and a panel
with history and settings. The chevron switches between them.

Recording starts ~0.45 s *before* the keypress — the engine keeps a rolling
buffer, so a word already in flight when you reach for the key still lands in the
transcript. That costs a permanently lit microphone indicator while utt is
running; the engine stands down on sleep and screen lock, and the whole feature
has an off switch in Settings → Recording.

## Layout

```
Utt/         SwiftUI app — App, Clients, Design, Features, Views
UttCore/     SwiftPM package: pure logic and all the tests
docs/        hotkey semantics spec, phase 0 spike results
project.yml  XcodeGen source of truth (Utt.xcodeproj is generated)
```

See [CLAUDE.md](CLAUDE.md) for the architecture and the invariants that are
load-bearing.

## Attribution

- Parakeet TDT v3 — NVIDIA NeMo, CC-BY-4.0
- Whisper — OpenAI, MIT, via WhisperKit
