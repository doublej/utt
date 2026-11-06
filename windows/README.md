# utt for Windows

Hold **Right Ctrl**, speak, release: the words are pasted at the cursor. It also serves utt
extensions' **jobs lane**, the same files and answer keys as utt 2.5.0 on the Mac, so an
extension built for the Mac (Deckhand) transcribes here unchanged.

This is a separate Rust program, not a build of the Swift app. SwiftUI, TCA, CoreML and
AVFoundation do not exist on Windows. It keeps the parts an extension depends on:

| | Mac utt | utt for Windows |
|---|---|---|
| Model | Parakeet TDT 0.6b v3 (FluidAudio, CoreML) | the same model, fp32 ONNX through sherpa-onnx on the GPU (CUDA); int8 on the CPU as the fallback |
| Folder | `~/Library/Application Support/dev.jurrejan.utt/extensions` | `%APPDATA%\dev.jurrejan.utt\extensions` (`UTT_APPLICATION_SUPPORT` overrides) |
| Consent | the approval sheet writes `<id>.consent.json` | `utt approve <id>` writes the same file |
| Jobs lane | `<id>.jobs\<clip>` → `<stem>.json`; audio and `<stem>.hints.json` deleted | same, including priority bands and oldest-first order |
| Answer keys | `text`/`error`, `raw`, `stages`, `startedAt(Ms)`, `finishedAt(Ms)`, `duration`, `timings` | same; `timings` holds `decode` and `hints` |
| Text stages | replacements, cleanup (FoundationModels), formatting, filters, hints | **hints only**: no replacements, no cleanup, no formatting, no `filtersTranscripts` |
| Clips | wav, m4a, mp3, aiff, flac, caf | same (symphonia) |
| Menu bar | status lines, actions, daemon, Quit | tray icon: each approved extension's status lines, and Quit |
| Values | `<id>.values.json` on every settings edit | written once from the manifest's defaults (no settings page) |
| Not built | — | settings window, extension actions (`action.json`), HTTP API, partials, word timings, cover, `wantsTranscripts` |

## GPU

`UTT_PROVIDER` defaults to `cuda`. Measured 2026-11-06 on the RTX 4080 SUPER, warm, 3–5 s clips:

| | CPU | CUDA |
|---|---|---|
| int8 model | 210–300 ms | 230–300 ms (quantized ops leave the GPU) |
| fp32 model | 175–275 ms | **60–86 ms** |

So the GPU build wants the fp32 export (`csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3` on
Hugging Face, 2.4 GB, into `%LOCALAPPDATA%\utt\models\sherpa-onnx-nemo-parakeet-tdt-0.6b-v3`);
`paths::model` takes it when present. Start-up spends ~285 ms warming CUDA so the first clip does not.
The model holds about 2.5 GB of VRAM while utt runs.

It links against sherpa-onnx's CUDA 12 build, not the crate's CPU download:

- `C:\dev\_cache\sherpa-onnx-cuda\lib` = the `lib\` of
  `sherpa-onnx-v2.0.1-cuda-12.x-cudnn-9.x-onnxruntime1.28.2-win-x64-cuda.tar.bz2`, **plus**
  `onnxruntime.lib` copied from the CPU shared archive (same ORT 1.28.2; the CUDA one ships none).
- Beside `utt.exe`: NVIDIA's redistributable `cudart64_12`, `cublas64_12`, `cublasLt64_12`
  (CUDA 12.9) and the `cudnn*64_9` DLLs (cuDNN 9.28, cuda12) from developer.download.nvidia.com
  redist, unzipped in `C:\dev\_cache\cuda-redist`. The CUDA 12.6 on PATH is too old for ORT 1.28:
  the provider fails with error 127 and falls back to the CPU.

## Build and install

Built on Windows with the MSVC toolchain; leave out `SHERPA_ONNX_LIB_DIR` for a CPU-only build. Windows cannot read the WSL tree here, so the source is
mirrored to `C:\dev\utt-windows` first:

```bash
rsync -a --delete --exclude target ~/dev/swift/utt/windows/ /mnt/c/dev/utt-windows/
cmd.exe /c "cd /d C:\dev\utt-windows && set SHERPA_ONNX_LIB_DIR=C:\dev\_cache\sherpa-onnx-cuda\lib&& cargo build --release"
cp /mnt/c/dev/utt-windows/target/release/{utt.exe,*.dll} /mnt/c/Users/jurre/AppData/Local/utt/bin/
find /mnt/c/dev/_cache/cuda-redist -name '*.dll' -exec cp {} /mnt/c/Users/jurre/AppData/Local/utt/bin/ \;
```

The model goes in `%LOCALAPPDATA%\utt\models\` (`UTT_MODEL_DIR` overrides):
the fp32 export above, or `sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` from the sherpa-onnx `asr-models` release.
`HKCU\...\Run\utt` starts it at login. The log is `%LOCALAPPDATA%\utt\utt.log`.

```bat
utt                       :: the app: hotkey and jobs lane, one copy per login
utt approve deckhand      :: approve an extension
utt transcribe clip.m4a another.wav   :: one process; the second timing is the warm one
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
