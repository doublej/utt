# App

## What this is

`@main`, `AppDelegate`, and process lifecycle — where activation policy and
the `utt://` URL scheme are decided.

## Invariants

- **No `LSUIElement`.** It makes every launch start as an accessory, so the
  window opens *behind* whatever is on screen. The Dock icon is a runtime
  `setActivationPolicy` decision; a login-item launch is detected through
  `launchIsDefaultUserInfoKey`.
- **Fronting the app goes through `AppActivation.front()`.** Since macOS 14
  activation is cooperative, so a bare `NSApp.activate()` is a silent no-op for
  a menu bar app. `AppActivation` takes `ignoringOtherApps:` and falls back to
  LaunchServices; a SwiftLint rule fails the build on the bare call.
- **A `utt://` caller must use `open -g`.** `utt://start|stop|toggle|cancel`
  reach `TranscriptionFeature` through `AppDelegate.application(_:open:)`. utt
  never activates itself there, but a plain `open` activates it for the
  caller — and the frontmost app when a recording *stops* is the app the
  transcript is pasted into, so a foregrounding caller dictates into utt's own
  window.

## Common change patterns

- **Add a `utt://` verb** → one `case` in `AppDelegate.action(for:)` and one
  line in the `CFBundleURLTypes` comment in `Info.plist`.
