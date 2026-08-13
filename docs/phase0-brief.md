## Confirmed pins (table: package, version/SHA, product, module, min macOS)

| Package | Version / SHA | Product | Module | Min macOS (manifest) |
|---|---|---|---|---|
| pointfreeco/swift-composable-architecture | **1.26.1** · `ead11e04e5011c437722c1990d22f80d87056978` | `ComposableArchitecture` | `ComposableArchitecture` | 13 |
| pointfreeco/swift-dependencies | **1.14.1** · `8dc1fbf2f6255a73dec53b4648164884898db4c5` | `Dependencies`, `DependenciesMacros` | `Dependencies` | 10.15 |
| FluidInference/FluidAudio | **0.15.5** · `19600a485baa4998812e4654b70d2bab8f2c9949` | `FluidAudio` | `FluidAudio` | 14 (+ Apple Silicon at runtime) |
| sparkle-project/Sparkle | **2.9.5** · `79bc9e872948e47877e76f194cb0c8e0412b0b90` | `Sparkle` | `Sparkle` | 10.13 |
| Clipy/Sauce | **2.5.2** · `1fce89ccc9cbb091022c17ef8f9939901d4e951a` | `Sauce` | `Sauce` | 11 |
| argmaxinc/argmax-oss-swift *(deferred, see below)* | 1.1.0 · `1e2a163736dfa5a198e637ae44c114e1c6d5cc2d` | `WhisperKit` | `WhisperKit` | 13 |

Use tags, not SHAs, everywhere: `exactVersion` for all five. Sauce's "no release cadence" is stale — `v2.5.2` peels to the same commit as `master` HEAD today, so `exactVersion: 2.5.2` is strictly better than a bare revision (readable, and re-tag risk is theoretical).

Do **not** copy the reference app's pins — it is on TCA 1.26.0, Sparkle 2.9.4, Sauce `branch: master` (floating — actively wrong for a reproducible build), and WhisperKit 0.15.0 from a repo that no longer receives releases. Only its FluidAudio pin (0.15.5, exact) matches reality.

Toolchain floor: **Swift 6.3 / Xcode 26.3+**, hard. swift-dependencies 1.14.1 declares `swift-tools-version: 6.3`; an older toolchain does not error, it silently falls back to `Package@swift-6.0.swift`. Deployment target 26.0 (utty already requires it — `Surface.swift` uses `.glassEffect`).

XcodeGen `project.yml` packages block:

```yaml
packages:
  ComposableArchitecture: { url: https://github.com/pointfreeco/swift-composable-architecture, exactVersion: 1.26.1 }
  Dependencies:           { url: https://github.com/pointfreeco/swift-dependencies,          exactVersion: 1.14.1 }
  FluidAudio:             { url: https://github.com/FluidInference/FluidAudio,               exactVersion: 0.15.5 }
  Sparkle:                { url: https://github.com/sparkle-project/Sparkle,                 exactVersion: 2.9.5 }
  Sauce:                  { url: https://github.com/Clipy/Sauce,                             exactVersion: 2.5.2 }
```

## FluidAudio call sequence (compile-accurate snippet for the spike)

Verified to compile *and run* against 0.15.5 on macOS 26.6 / M2 Pro.

```swift
import FluidAudio
import Foundation

actor TranscriptionEngine {
    private var asr: AsrManager?

    func load() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)  // download + load, no progress
        let manager = AsrManager(config: .default)                      // .default already matches v3
        try await manager.loadModels(models)
        self.asr = manager
    }

    func transcribe(url: URL) async throws -> ASRResult {
        guard let asr else { throw ASRError.modelLoadFailed }
        // MUST be a local `var`: `inout` into an async actor method.
        // A stored property fails: "actor-isolated var cannot be passed 'inout' to 'async' function call".
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(url, decoderState: &state)
    }
}
// ASRResult: .text .confidence .duration .processingTime .rtfx .tokenTimings
```

Facts that shape the design around it:

- Minimum clip is **0.3 s** (4800 samples @ 16 kHz), from `ASRConstants.minimumAudioDurationSeconds`. Under that → `ASRError.invalidAudioData`. 0.3–15 s is zero-padded internally to 240 000 samples.
- Files > 480 000 samples (~30 s) auto-route to `transcribeDiskBacked`. For >15 s audio, grab `await asr.transcriptionProgressStream` **before** calling transcribe.
- Model cache: `~/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3/`, ~461 MB. Override only via `to:`/`from:` URLs on `download`/`load`/`downloadAndLoad`, and a custom dir must itself end in `parakeet-tdt-0.6b-v3` (`load(from:)` does `deletingLastPathComponent().appendingPathComponent(folderName)`).
- **First load after install pays a one-time ~27 s ANE compile of Encoder.mlmodelc**, separate from the download, even when files are already cached. Budget first-run UX for it.
- Apple Silicon only. `AsrModels.isModelValid` throws `unsupportedPlatform` on Intel.
- Build logs will carry a benign `found 1 file(s) which are unhandled` warning for `benchmark.md`. Ignore.

Download progress: FluidAudio exposes none. One reference app fakes it by polling directory size every 250 ms against a hardcoded 650 MB target. Either port that with the **correct 461 MB** target, or ship an indeterminate spinner. The spinner is one line and never lies — take it.

## WhisperKit delta vs the reference pin (what changed, what it costs us)

**Recommendation: do not ship WhisperKit in v1.** utt is Parakeet-first (`~/.uttertype/settings.json` has `currentProvider: "builtin"`, model `parakeet-tdt-0.6b-v3`). Adding WhisperKit buys a second 600 MB+ model, a second download UX, and the whole migration below, for a path the user's own settings say is unused. Add it when someone actually asks for non-Apple-Silicon or a Whisper-specific language.

If/when it goes in, this is what changed from the 0.15.0 the reference app pins:

- **Repo and SPM identity moved.** `argmaxinc/WhisperKit` → `argmaxinc/argmax-oss-swift`; identity `whisperkit` → `argmax-oss-swift`. You cannot in-place bump — the old reference must be removed and the `WhisperKit` product re-linked, or you get a duplicate-product conflict. Cost: one project.yml edit for us (the reference app has to surgically edit pbxproj lines 616-622; we don't).
- **Module name unchanged.** `import WhisperKit` still works and re-exports `ArgmaxCore`. Use the `WhisperKit` product, not the `ArgmaxOSS` umbrella — the umbrella drags in TTSKit + SpeakerKit compile time for nothing.
- **swift-transformers dependency is gone**, vendored into ArgmaxCore. 1.1.0 has exactly one dependency (swift-argument-parser, CLI-only). Zero cost to us; we never touch `Hub`/`Tokenizers`.
- **Callbacks are `@Sendable` and non-optional aliases.** `TranscriptionCallback` is now `@Sendable (TranscriptionProgress) -> Bool?`; new `ProgressCallback = @Sendable (Progress) -> Void`. `callback: nil` and trailing closures still compile; `let cb: TranscriptionCallback = nil` no longer does. Any progress closure we pass must be `@Sendable` — under Swift 6 language mode that's an error, not a warning.
- **All 0.15 top-level free functions deleted** (`loadTokenizer`, `modelSupport(for:from:)`, `formatSegments`, `mergeTranscriptionResults`, …). Replacements namespaced under `ModelUtilities.*` / `TextUtilities.*` / `TranscriptionUtilities.*`. Cost: zero if we write fresh; nonzero if we paste the reference app's code.
- **Single-result `transcribe` overloads removed** — only the `[TranscriptionResult]` forms remain. The reference app already used the array form.
- **`DecodingOptions`**: `usePrefillCache` removed, `supressTokens` → `suppressTokens`. Everything the reference app passes (`language:`, `detectLanguage:`, `chunkingStrategy: .vad`) is unchanged.
- **`AudioInputConfig` → `AudioInputOptions`**, moved from config-level to a per-call parameter that sits *between* `audioPath:` and `decodeOptions:`. Labeled calls are unaffected. New `.incremental` loading mode keeps peak memory low on long files.
- Manifest floor is macOS 13 (README's "14.0" is Argmax's build statement, not the manifest). Irrelevant at our 26.0 target.

Net cost if we adopt: roughly half a day, almost all of it in "don't paste the reference app's client verbatim."

## Self-signed identity: the commands to run

**This machine already has the identity.** `A4F985E255EAA49E09BCA155A81331F318CA59CB "utt Dev"` (CN=utt Dev, O=jurrejan, valid to 2036, CA:FALSE / digitalSignature / codeSigning all critical). **Do not regenerate it** — the DR pins the cert's SHA-1, and a new cert resets every Accessibility / Input Monitoring / Microphone grant. Skip straight to signing:

```bash
codesign -f -s A4F985E255EAA49E09BCA155A81331F318CA59CB --options runtime .build/release/utt.app
codesign --verify -vvv .build/release/utt.app
codesign -d -r- .build/release/utt.app   # expect: identifier "…" and certificate root = H"a4f985e2…59cb"
```

Back up the key **now** — losing it loses every TCC grant:

```bash
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 \
  -P "$P12PASS" -o ~/.config/codesign/utt-Dev.p12
chmod 600 ~/.config/codesign/utt-Dev.p12
```

To recreate from scratch on another machine, the tested script is at
`/private/tmp/claude-501/-Users-jurrejan-Documents-development-python/cc95fedf-246e-4f1e-8371-abb69675e803/scratchpad/make-signing-identity.sh` — key points: `/usr/bin/openssl` (LibreSSL, produces the legacy p12 `security import` accepts; Homebrew's OpenSSL 3.x needs `-legacy`), `-days 7300` (expiry breaks `codesign -s "Name"` lookup, existing signatures stay valid forever), critical `CA:FALSE` / `digitalSignature` / `codeSigning` extensions, and `security import … -T /usr/bin/codesign`.

**Trust settings are not required.** `codesign` signs and verifies with an untrusted self-signed cert, no keychain prompt. TCC keys on the Designated Requirement — `identifier "<id>" and certificate root = H"<cert sha1>"` — derived by `DRMaker::nonAppleAnchor()`; same cert + same signing identifier ⇒ byte-identical DR ⇒ grants survive rebuilds. Ad-hoc (`-s -`) gets no DR at all, which is exactly why permissions churn.

Add trust **only** if a tool gates on `security find-identity -v -p codesigning` — which currently reports `0 valid identities found` for this cert (unverified: `-v` runs the trust policy). Xcode, fastlane and electron-builder all do this. `xcodebuild`-based signing therefore needs:

```bash
# GUI password dialog, no sudo, not scriptable headlessly:
security add-trusted-cert -p codeSign -r trustRoot -k ~/Library/Keychains/login.keychain-db cert.pem
```

Ship a real `.app`, never a bare Mach-O: since Tahoe 26.1, bare Unix executables stopped appearing in the Privacy & Security UI, and TCC keys them by path. Keep `CFBundleIdentifier` frozen — changing it mints a new TCC identity.

## Plan corrections (bullet list — anything in the plan that is now known wrong)

- **TCA is 1.26.1, not 1.26.0.** Sparkle is **2.9.5, not 2.9.4** (2.9.4 = `b6496a74…`; 2.9.5 binary checksum `34b9b2071f3de0012eca3faa3a9290bb94e62131e9a74f6dc91514a000097a6c`).
- **Sauce has releases.** Drop "pin a SHA because no release cadence" — use `exactVersion: 2.5.2`. Also drop the reference app's `branch: master`; a floating branch pin is not a pin.
- **Swift 6.3 is a hard floor, not a preference.** swift-dependencies 1.14.1 is tools-version 6.3 and silently degrades on older toolchains instead of failing. Pin CI to Xcode 26.3+.
- **The 1.5 s audio pad is wrong.** FluidAudio's real floor is **0.3 s** (`ASRConstants.minimumAudioDurationSeconds`). The reference app's `ParakeetClipPreparer.defaultMinimumDuration = 1.5` is 5× over-conservative — it silently stretches every short utterance. Pad to 0.3 s or don't pad at all.
- **FluidAudio download exposes no progress.** Any plan step assuming a progress callback on `downloadAndLoad` is wrong. The reference app's polling hack also uses a **650 MB** target against a real **461 MB** payload, so its bar stalls at ~69% and snaps to 100.
- **First-run latency is not just the download.** ~27 s one-time ANE compile on first load, on top of the ~461 MB fetch. Any "model ready in N seconds" estimate that only counts bytes is wrong.
- **`TdtDecoderState` cannot be a stored property.** Any design that caches decoder state on an actor or class will not compile. It must be a local `var` per call.
- **utty's Justfile signing is unsafe as written.** It takes "identity from `UTTY_SIGNING_IDENTITY` or first `security find-identity` match, **falling back to `-`**". Since `utt Dev` is untrusted, a `-v` lookup returns nothing and the build silently ad-hoc-signs → new DR every build → TCC permissions reset on every `just ship`. Hardcode the SHA-1 and **fail the build** if the identity is missing; never fall back to `-`.
- **`codesign --deep` is deprecated** and it's what utty uses. Sign the nested backend binary explicitly (inside-out), then the outer bundle.
- **No `.entitlements` file exists** in utty. Fine for unsandboxed, but Sparkle needs none only because we're unsandboxed — if sandboxing ever comes back, FluidAudio has no container/app-group API at all and the model cache lands in the app container.
- **The reference app's own docs drift from its code.** `docs/hotkey-semantics.md` says a modifier-only release under 0.3 s DISCARDs; `HotKeyProcessor` actually emits `.stopRecording` on every release and the discard is enforced downstream in `RecordingDecisionEngine.decide`. Port the code and the 46 tests, not the prose.
- **Two different tap strategies are on the table and they are not interchangeable.** utty uses `.cgSessionEventTap` + `.listenOnly` (never swallows). The reference app uses `.cghidEventTap` + `.defaultTap` (swallows via `nil` return). If the plan says "port utty's hotkey service and add the reference app's key interception", that's a rewrite of the tap, not a merge.

## Open risks

1. **The .p12 is a single point of failure.** Cert SHA-1 is baked into the DR. Lose it → every Accessibility / Input Monitoring / Microphone grant is gone, for every user of that build. Upgrade path if this ever bites: self-signed **root CA + leaf sharing the same O**, which makes the DR pin the CA hash and lets leaves be reissued forever. Not worth it for a single-dev app today.
2. **Untrusted identity + `find-identity -v` = 0 results.** Anything in the release path that enumerates identities (Xcode, notarization tooling, future CI) will report "no valid identity". Mitigation is the GUI-only `add-trusted-cert` dialog, which cannot be scripted headlessly.
3. **Gatekeeper rejects self-signed** (`spctl -a -t exec` → `rejected`). Harmless for locally-built apps (no quarantine xattr), fatal for anything downloaded. **This collides with Sparkle**: shipping auto-updates to other machines requires Developer ID + notarization. Either Sparkle is dev-only for now, or the plan needs a paid Apple account.
4. **Apple Silicon only, no fallback.** FluidAudio throws `unsupportedPlatform` on Intel and the CoreML models won't run there. If any target user is on Intel, WhisperKit stops being deferrable.
5. **Swift 6 strict concurrency reaches our call sites.** Under Xcode 26, both FluidAudio (tools 6.0) and any argmax package (`Package@swift-6.2.swift`, Swift 6 mode + `-enable-library-evolution`) surface Sendable diagnostics into consumer code. The `inout` decoder-state trap is the first one; expect more around progress closures.
6. **TCA 1.26.1 CI is still Xcode 16.4-only** upstream (only its format job runs on macos-26). We're the ones exercising it on 26.3 — if something breaks in TCA under the new toolchain, there's no upstream signal, and pinning back is not an option since swift-dependencies forces 6.3.
7. **Migration decode from `~/.uttertype/settings.json`**: all four `window` values are `null` (must decode as optionals) and both timestamps are naive ISO-8601 with no zone offset. `hotkeys.start_recording = "ctrl+globe"` is modifier-only with `keyCode == nil` — the debounced-release path, i.e. exactly the branch with the most doc/code drift in both reference apps. Port the reference app's 934-line `HotKeyProcessorTests` before touching that logic.
8. **Stray `.function` flags.** macOS opportunistically sets `.function` on plain modifier events. utty's fix — only enforce `.function` when the combo actually requires Globe — plus a 100 ms latched-release debounce, is load-bearing for this exact `ctrl+globe` binding. Its constant comment is worth porting verbatim: `<50 ms re-introduces the false deactivate; >150 ms hides fast double-tap patterns.`
9. **Tap silently dies.** A `tapCreate` issued before Input Monitoring is granted returns nil forever (needs full `restart()`, not `tapEnable`), and macOS kills taps on timeout / user input / wake. Both reference apps carry re-enable logic; one adds a 100 ms watchdog and recreates on `didWakeNotification`. Neither gates on `IOHIDCheckAccess` — it returns stale denials.

**Paths**

- `/private/tmp/claude-501/-Users-jurrejan-Documents-development-python/cc95fedf-246e-4f1e-8371-abb69675e803/scratchpad/make-signing-identity.sh`
- `/private/tmp/claude-501/-Users-jurrejan-Documents-development-python/cc95fedf-246e-4f1e-8371-abb69675e803/scratchpad/refs/{FluidAudio,argmax-oss-swift}`
- `/private/tmp/claude-501/-Users-jurrejan-Documents-development-python/cc95fedf-246e-4f1e-8371-abb69675e803/scratchpad/deps/{tca,deps141,sparkle,sauce}`
- `/Users/jurrejan/Documents/development/python/utty/utty/Hotkey/{GlobalHotkeyService.swift,GlobalHotkeyService+TapCallback.swift,HotkeyMatcher.swift,HotkeyFSM.swift}`
- `/Users/jurrejan/Documents/development/python/utty/utty/Design/{Palette,Typography,Spacing,Surface,Shadow}.swift`
- `/Users/jurrejan/Documents/development/python/utty/{Justfile,.quality.json,.swiftlint.yml,scripts/Info.plist}`
- `/Users/jurrejan/.uttertype/settings.json`