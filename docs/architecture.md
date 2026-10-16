# Architecture

## Layout

```
Utt.xcodeproj        # generated — never edit, never commit changes by hand
project.yml          # XcodeGen source of truth for the project
Utt/
  App/               # @main, AppDelegate, lifecycle
  Clients/           # @DependencyClient wrappers around the system
    Api/             # http listener, routes, the settings it acts on
    Input/           # event tap, pasteboard
    Recording/       # capture, devices, idle suspension
    System/          # permissions, sleep, sounds, presence, updates
    Transcription/   # engine dispatch, Parakeet, Whisper
  Design/            # palette, typography, spacing, surfaces
  Features/          # TCA reducers: App, Transcription, Settings, History
  Views/             # SwiftUI, one directory per surface
    App/             # root view, AppSection (the rail's sections), route
    Chrome/          # AppRail, OnboardingRail, PageHeader, the pill
    Settings/        # SettingRow + SettingsGroup, one page per section in
                     #   Dictation/, Text/, Output/, Application/
  Resources/         # Info.plist, entitlements
UttCore/             # SPM package: pure logic + all the tests
raycast/             # Raycast extension — talks to the app through its JSON files
docs/                # specs (hotkeys, API, cleanup), phase 0, release notes
```

## Runtime path

event tap → `KeyEventMonitorClient` (one serial `AsyncStream`) → `AppFeature` →
`HotKeyProcessor` → `TranscriptionFeature` → `RecordingClient` →
`TranscriptionClient` → `PasteboardClient`.

Folder-level invariants live in the `CLAUDE.md` next to the code: `Utt/App/`,
`Utt/Clients/{Api,Input,Recording,System,Transcription,Extensions}/`, and
`UttCore/Sources/UttCore/{Api,Extensions}/`.
