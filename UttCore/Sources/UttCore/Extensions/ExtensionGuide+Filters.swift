import Foundation

/// The guide's overflow sections. Here rather than inline for one reason: the
/// guide is one long string and the size rule is per file — and a seventh file in
/// this directory would break the other rule.
let extensionFilterGuide = #"""
        ## Rewriting transcripts before they land: `filtersTranscripts` and `<id>.filter/`

        Set `"filtersTranscripts": true` and utt shows you every transcript before
        it is pasted, and uses whatever you hand back instead. This is where a
        rewrite, a translation, a filled-in template or a language model goes.

        1. utt creates `{{dir}}<id>.filter/` when it sees your manifest.
        2. When a transcript finishes, utt writes `<name>.in.json` there:

           ```json
           {
             "text": "the words that were spoken",
             "raw": "the words what were spoken",
             "stages": ["cleanup"]
           }
           ```

           `text` is what the person would have seen: their own replacement and
           formatting rules have already run, and so has every filtering extension
           before you. `raw` is what the recogniser heard before any of that, and
           `stages` names the stages that changed the words — `replacements`,
           `cleanup`, `formatting`, and `filter` for an extension ahead of you in
           the chain. An empty `stages` means nothing has touched it. A
           `cleanupSkipped` field appears when the user has cleanup on and it did
           not run. Rewrite `text`; `raw` is context, not a transcript to hand back
           unless you mean to undo what the user configured. `<name>` is unique per
           transcript and means nothing.
        3. Write `<name>.out.json` beside it, atomically:

           ```json
           {"text": "the words you want pasted instead"}
           ```

           An empty string drops the transcript; nothing is pasted. A file utt cannot
           read is not a reply, and the original text goes through.
        4. utt deletes both files. Anything else it finds in the directory is a
           question it stopped waiting for, and is deleted too.

        **You have two seconds.** utt is sitting between the key coming up and the
        text appearing, so it waits that long and then pastes what it had. Poll
        the directory fast — every 50 ms is right — and if your rewrite needs a
        model, have it loaded before the first question arrives. Nothing is
        retried and nothing is queued: a missed question is gone.

        Extensions that filter run one after another in id order; the second sees
        what the first made of the text. Every transcript passes through here —
        the hotkey, the API, and clips other extensions sent — so a filter that is
        only meant for one of them has to decide that itself, from the text.

        This hands you everything dictated on that Mac, the same as
        `wantsTranscripts`, and lets you change it. The person is told so on your
        page. Do not ask for it unless you use it.
        """#

/// The section of the guide about opting out of the user's text pipeline.
let extensionTextStagesGuide = #"""
        ### Skipping the user's text rules

        The text utt hands back has been through the user's own pipeline: their
        replacement rules, then their formatting. That is tuned for a person
        writing prose at a cursor, and your clips may want something else — a
        terminal wants the replacements but not a lowercased line, a note-taker
        wants the words exactly as spoken.

        Name the stages you do not want and utt skips them **for your clips only**:

        ```json
        "skipsTextStages": ["formatting"]
        ```

        `"replacements"` is the user's word rules and the spoken-punctuation tidying
        that goes with them. `"formatting"` is lowercasing and punctuation
        stripping. Names utt does not know are ignored, so a manifest written
        against a later version still loads.

        This never touches what the person dictates, and it is shown on your page
        under Access — a user editing a rule can see why your extension ignores it.
        Ask for it because your clips genuinely want raw text, not to save yourself
        undoing utt's work afterwards.

        ## Switched off, or removed: `<id>.disabled`

        The person can switch you off from your page. utt writes an empty
        `<id>.disabled` beside your manifest, and while it is there nothing you
        declare is acted on: no transcripts, no clips, no filtering, no menu bar.
        Your page and your values file stay. Respect it — do not act on their
        behalf while it exists, and do not delete it.

        They can also remove you. Every file utt keeps for you goes to the Trash.
        You write your manifest at start-up, so your next start-up puts you back;
        that is expected, and it is why the switch exists.
        """#

/// The closing checklist.
let extensionImplementingGuide = #"""
        ## Implementing it

        1. Write `<id>.json` at start-up, every start-up. It is cheap and it is what
           survives an uninstall, a settings reset, or a user deleting the directory.
        2. Poll `<id>.values.json` (once a second is plenty) and act when `revision`
           moves. Treat a missing file as "the user has not opened the page yet" and
           use your manifest's own defaults until it appears.
        3. To transcribe audio, set `sendsAudio` and use the jobs directory. Reach
           for `needsApi` only if you need the HTTP API for something else — talking
           to utt from another device, say. An extension on the same Mac has no reason to
           open a socket to a program it can already write a file to.
        4. If you do need the API, take the token from the values file. Never read
           utt's `settings.json`.
        5. To change transcripts before they land, set `filtersTranscripts` and
           answer every question in the filter directory within two seconds.
        6. If the user's text rules are wrong for your clips, name the stages in
           `skipsTextStages` rather than undoing them yourself.
        7. Nothing in the values file is a command. It is the user's configuration,
           and it is the only thing utt promises to put there.

        Do not put secrets of your own in the manifest: it is a plain file, and its
        contents are shown in utt's window.
        """#
