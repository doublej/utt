//
//  ExtensionGuide+Dictation.swift
//  UttCore
//
//  The dictation an extension draws itself. Its own file because the guide is one
//  long string and the size rule is per file, not per idea.
//

import Foundation

/// What an extension gets when it starts the dictation instead of the person's key.
let extensionDictationGuide = #"""
    ## Starting a dictation of your own: `ownsDictation`

    Set `"ownsDictation": true`, and `"wantsTranscripts": true` beside it, and you can
    start a dictation that is yours to show: an editor with its own record button, a
    terminal that puts the words in its own prompt.

    - `open -g "utt://start?for=<id>"` starts it; `utt://stop` and `utt://cancel` end
      it, exactly as for any recording. `-g` keeps your app in front.
    - While it runs, utt shows none of its own panels — no indicator in the middle of
      the screen, no card above the Dock — and pastes nothing. The menu bar mark still
      shows that the microphone is on: that one is the person's, not yours.
    - The words still go through the person's engine, replacements, cleanup and
      formatting, and land in `<id>.transcript.json` with your `name` as `app`. Every
      other extension that asked for transcripts gets them too, as for any dictation.
    - **Every dictation you start ends in exactly one write to `<id>.transcript.json`.**
      When nothing came of it — it was cancelled, nothing was heard, or transcription
      failed — `text` is `""`. Stop waiting when it arrives.
    - The words as they are spoken still arrive in `<id>.partial.json`, if you asked
      for them and the person has "Show words while you speak" on.
    - Review mode and copy-only delivery do not apply: you are where the words go.
    - Starting while a recording is already running does nothing, the same as the
      person's own key. The person's key also stops yours.

    While you are waiting to be approved or are switched off, or without both flags,
    `for=` is ignored: it is an ordinary dictation, with utt's panels and a paste at
    the cursor. Tell the two apart from `<id>.level.json` — it is written from the
    first moment of a dictation that is yours, and never otherwise.

    ### The level: `<id>.level.json`

    About twenty times a second while your dictation records:

    ```json
    {"sequence": 812, "level": 0.083, "recording": true, "model": "Parakeet Standard"}
    ```

    - `level` is the microphone's peak, 0 to 1, linear, with a short decay. Draw it on
      a dB scale: `20 × log10(level)`, floored at -60. Speech sits around -30 to -10,
      which a linear bar would leave in its first few percent.
    - `recording` is `false` on exactly one write per dictation, when the microphone
      closes — stopped, cancelled, or the person's own key. The transcript follows.
    - `model` names the speech model that will write the transcript, as utt's
      picker shows it — what to show beside your meter.
    - `sequence` keeps counting across dictations. Read it once before you start and
      act only on writes after that one.
    """#
