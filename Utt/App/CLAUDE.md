# App

## What this is

`@main`, `AppDelegate`, and process lifecycle — where activation policy and
the `utt://` URL scheme are decided.

## Invariants

- **No `LSUIElement`.** It made every launch start as an accessory, so
  double-clicking utt opened its window *behind* whatever was already on
  screen. The Dock icon is a runtime `setActivationPolicy` decision, and the
  login-item launch the key used to cover is detected through
  `launchIsDefaultUserInfoKey` instead.
- **Fronting the app goes through `AppActivation.front()`.** macOS 14 made
  activation cooperative: a bare `NSApp.activate()` only works if the active
  app yielded, which nothing does for a menu bar app, so it is a silent no-op
  and the window opens behind everything. `AppActivation` takes
  `ignoringOtherApps:` and falls back to LaunchServices; a SwiftLint rule fails
  the build on the bare call.
- **A `utt://` caller must use `open -g`.** `utt://start|stop|toggle|cancel`
  reach `TranscriptionFeature` through `AppDelegate.application(_:open:)`. utt
  never activates itself there, but a plain `open` activates it for the
  caller — and the frontmost app when a recording *stops* is the app the
  transcript is pasted into, so a foregrounding caller dictates into utt's own
  window.

## Common change patterns

- **Add a `utt://` verb** → one `case` in `AppDelegate.action(for:)` and one
  line in the `CFBundleURLTypes` comment in `Info.plist`.
