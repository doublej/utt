import Foundation

/// The section of the guide about rewriting transcripts. Its own file only
/// because the guide is one long string and the size rule is per file.
let pluginFilterGuide = #"""
        ## Rewriting transcripts before they land: `filtersTranscripts` and `<id>.filter/`

        Set `"filtersTranscripts": true` and utt shows you every transcript before
        it is pasted, and uses whatever you hand back instead. This is where a
        rewrite, a translation, a filled-in template or a language model goes.

        1. utt creates `{{dir}}<id>.filter/` when it sees your manifest.
        2. When a transcript finishes, utt writes `<name>.in.json` there:

           ```json
           {"text": "the words that were spoken"}
           ```

           The text is what the person would have seen: their own replacement and
           formatting rules have already run. `<name>` is unique per transcript and
           means nothing.
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

        Plugins that filter run one after another in id order; the second sees
        what the first made of the text. Every transcript passes through here —
        the hotkey, the API, and clips other plugins sent — so a filter that is
        only meant for one of them has to decide that itself, from the text.

        This hands you everything dictated on that Mac, the same as
        `wantsTranscripts`, and lets you change it. The person is told so on your
        page. Do not ask for it unless you use it.
        """#
