//
//  ExtensionGuide+Partials.swift
//  UttCore
//
//  The live lane. Its own file because the guide is one long string and the size
//  rule is per file, not per idea.
//

import Foundation

/// What utt writes while the person is still speaking, for an extension that asked
/// to hear them as they go.
let extensionPartialsGuide = #"""
    ## What utt writes if you asked for partials: `<id>.partial.json`

    Set `"wantsPartials": true` and the words are written here as they are decoded,
    while the person is still holding the key.

    ```json
    {
      "sequence": 41,
      "text": "the words so far",
      "speaking": true,
      "writtenAt": "2026-09-10T22:14:43Z"
    }
    ```

    - `sequence` increments on every write, the closing one included. Poll it, the
      same way you poll `revision`.
    - `text` is everything heard **this recording**, not a delta. The recogniser
      revises what it already said, so treat each write as replacing the last.
    - `speaking` is `false` on exactly one write per recording: the key has come up
      and no more partials are coming. It is how you tell a pause from an ending.
    - `writtenAt` is ISO 8601.

    Four things to know before you build on this.

    1. **It is a different, smaller recogniser.** Parakeet's streaming model, not the
       one that makes the transcript. English only, and less accurate.
    2. **None of utt's text stages have run.** No replacements, no cleanup, no
       formatting — this is closer to `raw` than to `text`, and an extension is not
       the place to reimplement them.
    3. **The real transcript is a separate event** and may differ from the last
       partial in any way at all. It arrives in `<id>.transcript.json` if you asked
       for transcripts, which is the file to act on. Nothing here is final.
    4. **It only exists while the person has "Show words while you speak" on.** With
       the setting off, this file is never written and your extension sees nothing —
       so it cannot be the only way your extension works.
    """#
