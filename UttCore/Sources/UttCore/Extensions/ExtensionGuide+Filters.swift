//
//  ExtensionGuide+Filters.swift
//  UttCore
//
//  The guide's overflow sections. Here rather than inline for one reason: the
//  guide is one long string and the size rule is per file — and a seventh file
//  in this directory would break the other rule.
//

import Foundation

/// What utt hands an extension that asked to watch, and what it hands one that
/// asked to rewrite: the two lanes that carry `raw`, `stages` and `cleanupSkipped`.
let extensionTranscriptsGuide = #"""
        ## What utt writes if you asked for transcripts: `<id>.transcript.json`

        Set `"wantsTranscripts": true` and every transcript the person dictates is
        written here as it finishes. Dictation only: a clip you sent to the jobs
        directory comes back in its own answer file, and an API caller's clip is
        that caller's business.

        ```json
        {
          "sequence": 12,
          "text": "the words that were spoken",
          "raw": "um the words what were spoken",
          "stages": ["cleanup", "replacements"],
          "cleanupSkipped": "timeout",
          "finishedAt": "2026-09-09T16:58:03Z",
          "duration": 3.4,
          "app": "Ghostty"
        }
        ```

        `sequence`, `text`, `raw`, `stages`, `finishedAt` and `duration` are on
        every transcript. `cleanupSkipped` and `app` are **absent** when there is
        nothing to say — absent, not null, so decode them as optional.

        - `sequence` increments per transcript. Poll it exactly as you poll
          `revision`; it survives a restart because utt reads it back off this file.
        - `text` is what was typed, and is the one to use unless you have a reason
          not to.
        - `raw` is what the recogniser heard, before anything ran. It is not a
          better transcript and the person did not choose it: it is there so a
          mishearing can be told apart from a word a stage took out. A file written
          by a utt older than this one has no `raw`; read that as "same as `text`".
        - `stages` names the stages that actually **changed** the words, sorted. A
          stage that ran and left the text alone is not in it, and `[]` means `text`
          and `raw` are the same words:
          - `replacements` — the person's own word rules
          - `cleanup` — the on-device model taking out fillers and false starts
          - `formatting` — lowercasing and punctuation stripping
          - `filter` — an extension rewriting the transcript, possibly yours

        - `cleanupSkipped` appears only when the person has cleanup switched **on**
          and it did not run on this transcript. **The transcript arrived anyway** —
          utt keeps the words whole rather than handing over a half-cleaned line —
          and a skipped stage is never in `stages`, having changed nothing. One of:

          | Value | What happened |
          | --- | --- |
          | `unavailable` | No usable on-device model: the Mac is not eligible, Apple Intelligence is off, or the weights are still landing |
          | `guardrail` | The model's own content check fired on the transcript |
          | `timeout` | The model was still generating when the deadline passed |
          | `tooLong` | More transcript than the model's context window holds |
          | `tooShort` | The result came back empty, or dropped more of the words than a cleanup may |
          | `failedVerification` | The result was not a deletion-only edit of what went in — utt refuses a model that rewrites rather than tidies |

          Names are added as the stage learns new ways to fail, so treat one you do
          not know as "it did not run" rather than failing to decode the file.

        - `finishedAt` is ISO 8601 and `duration` is the seconds of audio behind it.
        - `app` is the app the text was pasted into. Absent means nothing received
          it: the paste failed, or utt could not name what was in front.
        - The **newest one only**. This is not a log — utt already keeps the
          history, and a file that grew forever would be a second copy of everything
          ever said. Keep your own log if you need one.
        - Written whether or not the person keeps history: retention governs what
          utt stores, not what it hands to an extension they installed.
        - This hands you everything dictated on that Mac. The person is told so on
          your extension's page. Do not ask for it unless you use it, and do not
          send it anywhere they have not asked you to.
        """#

/// The rewrite lane.
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
             "raw": "um the words what were spoken",
             "stages": ["cleanup", "replacements"],
             "cleanupSkipped": "timeout"
           }
           ```

           You are handed the whole transcript, not just a line of text:

           - `text` is what the person would have seen had you not been installed:
             their replacement rules, cleanup and formatting have already run, and
             so has every filtering extension ahead of you. **This is the one to
             rewrite.**
           - `raw` is what the recogniser heard before any of that.
           - `stages` says which of the two you are looking at, with the same
             names as `<id>.transcript.json` above — `filter` there meaning an
             extension ahead of you in the chain, never you. `[]` means `text` and
             `raw` are the same words and nothing has touched this one yet.
           - `cleanupSkipped` is the same optional field, with the same six values:
             cleanup was on and did not run. Worth reading if your rewrite assumed
             a tidy sentence — it may be looking at "um, so, I was, I was going".

           `text` and `raw` are always there; `stages` is always there and may be
           empty; `cleanupSkipped` is absent unless there is a reason. `raw` is
           context, not a transcript to hand back — returning it undoes what the
           person configured. `<name>` is a UUID, unique per transcript, and means
           nothing.
        3. Write `<name>.out.json` beside it, atomically:

           ```json
           {"text": "the words you want pasted instead"}
           ```

           `text` is the only key; there is nothing to echo back. An empty string
           drops the transcript and nothing is pasted. A file utt cannot read is
           not a reply, and the original text goes through unchanged.

           Hand back different text and utt records `filter` in `stages` from
           there on — the next filter in the chain sees it, and so does the history
           and any extension watching transcripts. Hand back what you were given
           and nothing is recorded: a filter that ran and changed nothing is not
           worth showing anybody. `raw` never moves whatever you do; it is what was
           heard, and you did not hear it.
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
        replacement rules, then transcript cleanup, then their formatting. That is
        tuned for a person writing prose at a cursor, and your clips may want
        something else — a terminal wants the replacements but not a lowercased
        line, a note-taker wants the words exactly as spoken.

        Name the stages you do not want and utt skips them **for your clips only**:

        ```json
        "skipsTextStages": ["formatting"]
        ```

        Three stages, in the order they run:

        - `"replacements"` — the user's word rules, and the spoken-punctuation
          tidying that goes with them.
        - `"cleanup"` — the on-device model taking out filler words, false starts
          and mid-sentence self-corrections, and putting sentence punctuation back.
          Skip it when the words matter more than the prose does: a terminal wants
          the user's replacement rules, and does not want a language model deciding
          that a command was a false start. Skip it too if you are about to run a
          model of your own.
        - `"formatting"` — lowercasing and punctuation stripping.

        Names utt does not know are ignored, so a manifest written against a later
        version still loads. Skipping a stage is not the same as it being off: skip
        `cleanup` and no `cleanupSkipped` is reported, because nothing was skipped
        — you asked for it not to run.

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
