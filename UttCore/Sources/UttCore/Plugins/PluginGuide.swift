import Foundation

/// The brief the "Copy guide for an LLM" button puts on the clipboard.
///
/// Same intent as `ApiGuide`: pasteable into a model with no other context. What a
/// model otherwise gets wrong here is the *shape* — it invents a registration call,
/// or assumes utt will merge a partial values file. Both are stated plainly below,
/// along with the rules that decide whether a manifest is accepted at all.
public enum PluginGuide {
    public static func markdown(directory: String) -> String {
        pluginGuideTemplate.replacingOccurrences(of: "{{dir}}", with: directory)
    }
}

// The guide lives outside the enum because it is one long document, and a type
// whose body is a page of prose trips every size rule there is.
private let pluginGuideTemplate = #"""
        # Write a plugin for utt

        **utt** is a macOS app that transcribes speech on-device. A plugin is any
        program of yours that wants a settings page inside utt's own window — a
        daemon, a menu bar app, a script. utt renders the page; your program keeps
        running on its own and reads what the user chose. A plugin can also send
        utt audio to transcribe, receive every transcript as it finishes, show its
        daemon's live state, and offer buttons.

        There is no API to call and nothing to register. Everything happens through
        files in `{{dir}}`, which utt creates at launch. Both programs may start and
        restart in any order.

        Write every label, blurb and detail for the person using the page, not for
        yourself: say what happens when they change it, in plain words, and never
        name a key, a file or a process in it. utt's own rows read "Mute other audio
        while recording · Whatever is playing pauses, so it does not end up in the
        transcript." Match that.

        ## What you write: `<id>.json`

        ```json
        {
          "id": "deckhand",
          "name": "Deckhand",
          "blurb": "One sentence under your name: what the plugin does for the person.",
          "systemImage": "sailboat",
          "needsApi": false,
          "wantsTranscripts": false,
          "sendsAudio": false,
          "tint": "#3EAFB4",
          "showsInMenuBar": true,
          "daemon": {"label": "com.example.mydaemon"},
          "actions": [
            {"key": "stop", "label": "Stop", "detail": "What it does.", "confirms": true},
            {"key": "openLog", "label": "Open log"}
          ],
          "settings": [
            {"key": "route", "kind": "choice", "label": "Route",
             "options": ["auto", "keyboard"], "value": "auto",
             "detail": "Explains the setting, shown under the label."},
            {"key": "deliver", "kind": "bool", "label": "Send into sessions", "value": true},
            {"key": "prefix", "kind": "string", "label": "Prefix", "value": ""},
            {"key": "delay", "kind": "number", "label": "Delay", "value": 0}
          ]
        }
        ```

        - `id` must equal the filename without `.json`, and may hold only lowercase
          letters, digits, `.`, `_` and `-`. A manifest whose id disagrees with its
          filename is ignored, as is one with a path separator in it.
        - `kind` is `bool`, `string`, `number` or `choice`. `value` is the default and
          must match the kind; `choice` needs `options` and a default among them.
        - `systemImage` is an SF Symbol and is the only icon field. An unknown
          symbol is dropped, not drawn.
        - `tint` is your colour, `#RGB` or `#RRGGBB`. utt lights the menu bar mark in
          it while it is transcribing *your* clip, so the user can see that work
          arriving from your plugin is not dictation at their Mac. One that cannot be
          parsed is dropped rather than guessed at.
        - Only `id` and `name` are required. Omitted keys take their defaults —
          write the keys you care about.
        - `detail` on a setting is the sentence under its label. It is where the
          explanation goes; utt has no tooltips.
        - At most 24 settings. Long labels are trimmed; newlines are flattened.
        - A setting that cannot be rendered honestly is dropped rather than repaired
          into something the user did not ask for. If a row is missing from the page,
          that is why.

        ## Buttons: `actions`, and `<id>.action.json`

        Each entry in `actions` is a button on your page. Pressing one writes:

        ```json
        {"sequence": 3, "key": "openLog", "requestedAt": "2026-09-09T17:31:02Z"}
        ```

        Poll `sequence` exactly as you poll `revision` — acting on `key` alone means
        pressing the same button twice looks like nothing happened. `detail` is the
        sentence under the button. Set `"confirms": true` on anything a mis-click
        should not do; utt asks first, with your `label` as the title and your
        `detail` as the question, so write the detail as the question's answer:
        "Stops the daemon. Sessions stay open; nothing is lost." At most 8 actions.

        **utt never runs anything for you.** It writes the key you named and your
        program decides what it means. A manifest is a file any process on this Mac
        can write, so one that could name a command to execute would turn "drop a
        file in a folder" into "run this as the user".

        ## A menu bar item of your own: `showsInMenuBar`

        Set it and you get an item in the menu bar beside utt's own, drawn with your
        `systemImage` and your `tint`. There is nothing else to declare — its menu is
        built from what you have already said:

        - your `<id>.status.json` lines, at the top
        - your daemon's live state and a **Restart**, if you declared `daemon.label`
        - your `actions`, which behave exactly as they do on your page
        - **<Your name> settings…**, which opens utt on your page

        A tinted icon is drawn in your colour; without a `tint` it is a template
        image, which is what lets the menu bar invert it on a light or dark
        background. The menu is rebuilt every time it is opened, so a status line you
        rewrote a second ago is the one shown. An action that `confirms` is asked
        about here too, and writes the same `<id>.action.json` with the same
        `sequence` — you cannot tell a menu press from a page press, deliberately.

        This is your item, not a second copy of utt's. utt's own mark stays what it
        is, and still flashes your `tint` while transcribing your clip.

        ## Daemons: `daemon.label`

        Give the label of your launchd job and utt shows its **live state** — running
        with a pid, loaded but not running, or not loaded at all — read from launchd
        rather than from your own status file. This is the one state your status file
        cannot report: a daemon that crashed leaves its last cheerful file behind.

        utt offers one button, **Restart** (`launchctl kickstart -k`), which starts a
        stopped job and restarts a running one. It will not bootstrap or unload a
        job, and it takes a label only — never a path to a plist. Loading a plist
        named by a manifest would be running whatever that plist points at. If you
        want Stop, declare it as an action and stop yourself; your job's `KeepAlive`
        is between you and launchd.

        Labels beginning `com.apple.` are refused: a plugin may report on its own
        daemon, not reach into the system's.

        ## What utt writes: `<id>.values.json`

        ```json
        {
          "revision": 4,
          "values": {"route": "auto", "deliver": true, "prefix": "", "delay": 0},
          "api": {"token": "…", "port": 8756}
        }
        ```

        - Written when the user changes something, and once after you install the
          manifest so the file exists before anyone touches the page. Not written
          when nothing changed.
        - It holds **every** setting, always — utt does not merge. Read the whole
          `values` object; do not assume a missing key means "unchanged".
        - `revision` increases by one on every write utt makes. Compare it against
          the last one you saw; do not use the modification time, which has
          one-second granularity on some filesystems.
        - A text setting arrives **per keystroke**, not per commit — every keystroke
          is a real change, so a typed sentence is forty revisions. Act on the value
          you care about, and debounce anything expensive.
        - The write is atomic (write to a temporary file, then rename), so a poll can
          never read a half-written file. Polling once a second is fine.
        - `api` appears only if your manifest set `"needsApi": true` **and** the user
          has utt's API switched on. Its absence means "not available right now" —
          do not fall back to reading utt's own settings file.

        ## Sending audio to be transcribed: `<id>.jobs/`

        Set `"sendsAudio": true` and utt creates `{{dir}}/<id>.jobs/`. This is the
        direct lane — **do not use the HTTP API for this.** No listener, no token,
        nothing on the network, and it works whether or not the API is switched on.

        1. Write your clip there under a name that is not yet an audio file —
           `clip-1.wav.part` — then **rename** it to `clip-1.wav`. utt only picks up
           the audio extensions below, so a half-written file is invisible until the
           rename makes it whole. Skip this and utt will read your file mid-write.
        2. Optionally write `clip-1.hints.json` **before** the rename — a flat list
           of words you already know are likely to appear:

           ```json
           ["deckhand", "launchd", "onenv", "xcodegen", "DotMatrix"]
           ```

           A recogniser hears sound and guesses words; you often know the vocabulary
           before you send the clip — the repo, the session, your own product's name.
           Those are exactly the terms that come back wrong. utt corrects near
           misses against your list ("cockwheel" to "cogwheel", "Tu Y" to "TUI",
           "deck hand" to "deckhand") and leaves everything else alone: a term only
           displaces text that is already nearly it and starts with the same letter,
           because a wrong correction reads perfectly and says something else.
           It cannot fix an ordinary word misheard as another ordinary word.
        3. utt transcribes it and writes `clip-1.json` beside it:

           ```json
           {"text": "the words that were spoken", "finishedAt": "2026-09-09T17:04:11Z"}
           ```

           or, when it could not:

           ```json
           {"error": "Could not transcribe that clip.", "finishedAt": "..."}
           ```

           Exactly one of `text` and `error` is present, and the write is atomic.
        4. The audio is deleted either way, and so is the hints file. The answer
           file is yours — read it and delete it; utt never touches it again.

        Extensions utt will open: `wav`, `m4a`, `mp3`, `aiff`, `flac`, `caf`. The
        extension is how AVFoundation picks its reader, so it must match the bytes —
        a wav named `.m4a` fails to open however correct it is. Clips are picked up
        oldest first, so two sent in order come back in order. Maximum 25 MB.

        You get the same text the hotkey would have pasted: the engine and model the
        user chose, then their own replacement and formatting rules. Transcription is
        on their Mac; nothing is sent anywhere.

        ## What utt writes if you asked for transcripts: `<id>.transcript.json`

        Set `"wantsTranscripts": true` and every transcript utt produces is written
        here as it finishes:

        ```json
        {
          "sequence": 12,
          "text": "the words that were spoken",
          "finishedAt": "2026-09-09T16:58:03Z",
          "duration": 3.4,
          "app": "Ghostty"
        }
        ```

        - The **newest one only**. This is not a log — utt already keeps the history,
          and a file that grew forever would be a second copy of everything ever
          said. Keep your own log if you need one.
        - `sequence` increments per transcript. Poll it exactly as you poll
          `revision`; it survives a restart because it is read from the file.
        - `app` is where the text was pasted, and is absent when nothing received it
          — a failed paste, or a transcript that came in through the API.
        - Written whether or not the user keeps history: retention governs what utt
          stores, not what it hands to a plugin they installed.
        - This hands you everything dictated on that Mac. The user is told so on your
          plugin's page. Do not ask for it unless you use it, and do not send it
          anywhere they have not asked you to.

        ## What you may also write: `<id>.status.json`

        ```json
        {"daemon": "up 0.1.0", "sessions": "9 live", "lastRelay": "2 min ago"}
        ```

        A flat object of strings, shown read-only at the top of your page. utt never
        interprets these — they are your words. camelCase keys are split for display
        (`lastRelay` becomes "Last relay"). A missing file means "not running", which
        is exactly how it is shown. Rewrite it when something changes, at most about
        once a second.

        ## Implementing it

        1. Write `<id>.json` at start-up, every start-up. It is cheap and it is what
           survives an uninstall, a settings reset, or a user deleting the directory.
        2. Poll `<id>.values.json` (once a second is plenty) and act when `revision`
           moves. Treat a missing file as "the user has not opened the page yet" and
           use your manifest's own defaults until it appears.
        3. To transcribe audio, set `sendsAudio` and use the jobs directory. Reach
           for `needsApi` only if you need the HTTP API for something else — talking
           to utt from another device, say. A plugin on the same Mac has no reason to
           open a socket to a program it can already write a file to.
        4. If you do need the API, take the token from the values file. Never read
           utt's `settings.json`.
        5. Nothing in the values file is a command. It is the user's configuration,
           and it is the only thing utt promises to put there.

        Do not put secrets of your own in the manifest: it is a plain file, and its
        contents are shown in utt's window.
        """#
