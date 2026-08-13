# utt

> Native macOS on-device transcription — hold a hotkey, speak, release, text at the cursor

Full context is in [CLAUDE.md](CLAUDE.md). This file is the short operational loop.

## Stack

- Swift 6, strict concurrency, macOS 26.0
- XcodeGen project (`project.yml`) — `Utt.xcodeproj` is generated
- The Composable Architecture 1.26.1
- FluidAudio (Parakeet TDT v3) + WhisperKit
- `UttCore` is a plain SwiftPM package: pure logic, all the tests

## Commands

- `just check` — the gate: just-fmt-check + loc-check + dir-check + lint + build + test
- `just lint-fix` — `swiftlint --fix`, then relint
- `just build` / `just build-release`
- `just test` — `swift test` in `UttCore`
- `just run` — build, kill the running copy, launch
- `just dr` — print the designated requirement (TCC stability)
- `just generate` — regenerate the Xcode project from `project.yml`

## Verify loop

Run `just check` after every change. On failure, work in this order:

1. `just lint-fix`
2. `just build`
3. `just test`

## Conventions

- Reducer `switch` cases stay one line and delegate to a `private extension` method.
- Child → parent is pattern-matching on the child action, not a delegate action.
- Views read `@Shared(.uttSettings)` directly; `AppFeature.Action` is not
  `BindableAction`, so a child binding is routed by hand:
  `store.send(.history(.binding(.set(\.searchText, $0))))`.
- New pure logic goes in `UttCore` with a test. Anything needing a screen or a
  microphone does not.
- Comments explain *why*, especially where the platform misbehaves. There are a
  lot of those; they are the most valuable text in the repo.

## Testing

- Swift Testing (`@Test`, `@Suite`, `#expect`), not XCTest.
- Files: `UttCore/Tests/UttCoreTests/`
- One test: `cd UttCore && swift test --filter HotKeyProcessorTests`

## Gotchas that will cost you an hour

- `view.window` is nil in `makeNSView` **and** one runloop turn later. Subclass
  `NSView` and override `viewDidMoveToWindow`.
- `.fullSizeContentView` does not shrink the window frame; only removing
  `.titled` does.
- `import IOKit.pwr_mgt` — not `IOKit.pm`, not bare `IOKit`.
- `log stream` misbehaves under the rtk wrapper; use
  `/usr/bin/log show --last 30s --style compact --info --debug --predicate 'subsystem == "dev.jurrejan.utt"'`.
- `xcodebuild` needs `-skipMacroValidation -skipPackagePluginValidation`, or it
  demands an interactive trust click whenever a macro fingerprint moves.

## Boundaries

- Do not run `just xcode` — never open Xcode.
- Do not archive, notarize, push, or touch the signing identity without asking.
- Do not modify the deployment target without asking.
- Anything needing a live hotkey press needs the user physically present. Ask
  first; do not assume they are ready.
