# utt for Windows

Hold **Right Ctrl**, speak, release: the words are pasted at the cursor. It also serves utt
extensions' **jobs lane**, the same files and answer keys as utt 2.5.0 on the Mac, so an
extension built for the Mac (Deckhand) transcribes here unchanged.

This is a separate Rust program, not a build of the Swift app. SwiftUI, TCA, CoreML and
AVFoundation do not exist on Windows. It keeps the parts an extension depends on:

| | Mac utt | utt for Windows |
|---|---|---|
| Model | Parakeet TDT 0.6b v3 (FluidAudio, CoreML) | the same model, int8 ONNX through sherpa-onnx, on the CPU |
| Folder | `~/Library/Application Support/dev.jurrejan.utt/extensions` | `%APPDATA%\dev.jurrejan.utt\extensions` (`UTT_APPLICATION_SUPPORT` overrides) |
| Consent | the approval sheet writes `<id>.consent.json` | `utt approve <id>` writes the same file |
| Jobs lane | `<id>.jobs\<clip>` → `<stem>.json`; audio and `<stem>.hints.json` deleted | same, including priority bands and oldest-first order |
| Answer keys | `text`/`error`, `raw`, `stages`, `startedAt(Ms)`, `finishedAt(Ms)`, `duration`, `timings` | same; `timings` holds `decode` and `hints` |
| Text stages | replacements, cleanup (FoundationModels), formatting, filters, hints | **hints only**: no replacements, no cleanup, no formatting, no `filtersTranscripts` |
| Clips | wav, m4a, mp3, aiff, flac, caf | same (symphonia) |
| Menu bar | status lines, actions, daemon, Quit | tray icon: each approved extension's status lines, and Quit |
| Values | `<id>.values.json` on every settings edit | written once from the manifest's defaults (no settings page) |
| Not built | — | settings window, extension actions (`action.json`), HTTP API, partials, word timings, cover, `wantsTranscripts` |

## Build and install

Built on Windows with the MSVC toolchain. Windows cannot read the WSL tree here, so the source is
mirrored to `C:\dev\utt-windows` first:

```bash
rsync -a --delete --exclude target ~/dev/swift/utt/windows/ /mnt/c/dev/utt-windows/
cmd.exe /c "cd /d C:\dev\utt-windows && cargo build --release"
cp /mnt/c/dev/utt-windows/target/release/{utt.exe,*.dll} /mnt/c/Users/jurre/AppData/Local/utt/bin/
```

The model goes in `%LOCALAPPDATA%\utt\models\` (`UTT_MODEL_DIR` overrides):
`sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` from the sherpa-onnx `asr-models` release.
`HKCU\...\Run\utt` starts it at login. The log is `%LOCALAPPDATA%\utt\utt.log`.

```bat
utt                       :: the app: hotkey and jobs lane, one copy per login
utt approve deckhand      :: approve an extension
utt transcribe clip.m4a [hint…]
```

## Traps

- **The Windows onnxruntime.** Windows 11 keeps an older `onnxruntime.dll` (1.17) in System32,
  and a process that loads sherpa-onnx at start-up gets that one ("API version [28] is not
  available"). `build.rs` delay-loads `sherpa-onnx-c-api.dll` so `asr.rs` can load the bundled
  copy by full path first. Ship the four DLLs beside `utt.exe`.
- **Static sherpa-onnx needs a newer MSVC STL** (`__std_search_1`) than Build Tools 14.41, so
  the crate uses the `shared` feature.
- **Right Ctrl alone is the hotkey**, so a Right-Ctrl shortcut held for 0.3 s or more while
  speaking also dictates. Each dictation replaces the clipboard, and nothing shows that the
  microphone is open.
- **Start it in the desktop session.** A copy started from a service or from WSL's session 0
  has no keyboard to hook. `explorer.exe C:\...\utt.exe` or the Run key starts it in the right one.
