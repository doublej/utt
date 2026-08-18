# utt for Raycast

Pick utt's microphone and reuse recent transcriptions, without leaving Raycast.

## Commands

- **Toggle Dictation** — start a recording, or stop it and paste what you said.
  Worth a Raycast hotkey or an alias; utt's own push-to-talk still works.
- **Microphone** — the priority list, in order, plus every input utt can see.
  Promote a device, add fallbacks, or drop back to the system default. utt
  records from the first device on the list that is actually plugged in.
- **Recent Transcriptions** — search what utt has already transcribed and paste
  it into whatever is in front, or copy it.

## How it talks to utt

Two ways, both utt's own. Anything it needs to *know* comes from the files utt
already reads, in `~/Library/Application Support/dev.jurrejan.utt`:

| File | Direction | What for |
| --- | --- | --- |
| `settings.json` | read + write | `microphonePriority` |
| `history.json` | read | past transcripts |
| `devices.json` | read | input names and their CoreAudio UIDs |

There is no scripting bridge, no URL scheme and no relaunch: utt watches
`settings.json`, so a microphone change from here takes effect in the running
app immediately. `devices.json` is exported by utt while it runs — a UID is not
something any system tool will hand out, and `microphonePriority` is written in
UIDs because an `AudioDeviceID` is only valid until the next reboot.

Writes are atomic, and unknown keys are preserved, so a newer utt's settings
survive an older copy of this extension.

Anything it needs utt to *do* goes through utt's URL scheme — `utt://start`,
`utt://stop`, `utt://toggle`, `utt://cancel`. Always opened with `open -g`: utt
pastes into whatever is frontmost when a recording stops, and foregrounding utt
would make that utt itself.

## Development

```sh
just raycast-dev     # loads it into Raycast, reloads on save
just raycast-check   # typecheck + tests
```
