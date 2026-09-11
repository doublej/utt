//
//  ExtensionGuide+Jobs.swift
//  UttCore
//
//  The jobs lane's section of the guide. Split out because the guide is one long
//  string and the size rule is per file, not per idea.
//

import Foundation

/// The direct lane, in full: what to write, what comes back, and every field of
/// the answer — the stamps, the before-and-after, and what each stage cost.
let extensionJobsGuide = #"""
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
           {
             "text": "the words that were spoken",
             "raw": "um the words what were spoken",
             "stages": ["cleanup", "hints", "replacements"],
             "cleanupSkipped": "timeout",
             "startedAt": "2026-09-09T17:04:09Z",
             "finishedAt": "2026-09-09T17:04:11Z",
             "startedAtMs": 1789052649182,
             "finishedAtMs": 1789052651511,
             "duration": 3.4,
             "timings": {"decode": 1802.5, "replacements": 0.4, "cleanup": 511.2, "hints": 0.1}
           }
           ```

        ### Where each word was spoken

        Set `"wantsWordTimings": true` alongside `"sendsAudio"` and the answer carries
        one more field:

        ```json
        {
          "text": "the words that were spoken",
          "raw": "um the words what were spoken",
          "words": [
            {"word": "um", "start": 0.24, "end": 0.40},
            {"word": "the", "start": 0.56, "end": 0.72}
          ]
        }
        ```

        Seconds from the start of **your clip**, and they describe `raw` — not `text`.
        The stages after the recogniser delete filler and rewrite near misses, so a
        number pinned to `text` would name a word at a second where something else was
        said. Read `raw` when you are cutting audio; read `text` when you are showing
        prose.

        It is declared rather than always sent because it is the one field that grows
        with the clip: five minutes of speech is some seven hundred entries. Absent
        when you did not ask, and absent when the engine has none — WhisperKit gives
        no word times here, only Parakeet does.

           or, when it could not:

           ```json
           {"error": "Could not transcribe that clip.", "startedAt": "...",
            "finishedAt": "...", "startedAtMs": 0, "finishedAtMs": 0}
           ```

           Exactly one of `text` and `error` is present, and the write is atomic.
           `raw`, `stages`, `cleanupSkipped`, `duration` and `timings` mean exactly
           what they mean in `<id>.transcript.json` below, with one more stage name:
           `hints`, for your own list correcting a near miss. `raw` is what the
           recogniser heard, before your hints and before the person's stages. A file
           written by a utt older than this one has none of these keys, nor the
           stamps below — decode them all as optional.

           `startedAt` is when utt picked the clip up and `finishedAt` is when it was
           done: the gap between your own rename and `startedAt` is this watcher
           getting to you, and the gap between the two stamps is the work. The ISO
           strings are **whole seconds**, which is too coarse to attribute a
           three-second job, so both moments come again as `startedAtMs` and
           `finishedAtMs`, milliseconds since the epoch. They are siblings rather
           than a sharper `finishedAt` on purpose: a default `ISO8601DateFormatter`
           refuses a string with fractional seconds, so making that field finer would
           break every extension already parsing it.

           A clip sent before the person has approved you is answered too, with an
           `error` saying utt is waiting for them — so you can say why rather than
           poll until you time out. The clip is deleted with the answer; send it
           again once you are approved.
        4. The audio is deleted either way, and so is the hints file. The answer
           file is yours — read it and delete it; utt never touches it again.

        Extensions utt will open: `wav`, `m4a`, `mp3`, `aiff`, `flac`, `caf`. The
        extension is how AVFoundation picks its reader, so it must match the bytes —
        a wav named `.m4a` fails to open however correct it is. Your own clips are
        picked up oldest first, so two sent in order come back in order. Where you
        sit relative to *another* extension's clips is the person's choice, not
        yours — they can put an extension first or last in the queue — so do not
        time your work against someone else's. Maximum 25 MB.

        You get the same text the hotkey would have pasted: the engine and model
        the user chose, then their own replacement rules, transcript cleanup and
        formatting — minus any stage you named in `skipsTextStages`, and after any
        filtering extension has had its turn — and the answer says which of those
        stages changed the words and what each of them cost, the same way
        `<id>.transcript.json` and the filter lane below do. Transcription is on
        their Mac; nothing is sent anywhere.
        """#
