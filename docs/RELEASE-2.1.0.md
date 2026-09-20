Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

The panel can fill in while you are still talking. utt can be run with its
microphone closed, for the programs that use it as a transcriber and never as a
microphone. And when something goes wrong with an extension, utt now says so
somewhere you can read it.

## The words appear while you are still speaking

Switch on **Output → Show words while you speak** and the panel fills in as you
talk, from a second, smaller recogniser running beside the real one. It decodes
a third of a second at a time and hands back everything it has so far.

What you see is a preview and nothing more. The clip on disk is still what
becomes your transcript, the full model still produces it, and the preview is
cleared the moment the real one arrives — two versions of the same sentence on
screen is worse than either.

It is off by default, and it costs something: English only, and about 100 MB
downloaded the first time you dictate with it on.

## utt can run unarmed

utt is two things now. It is something you dictate into, and it is a
transcriber other programs use — over its HTTP API, or as extensions that hand
it audio recorded somewhere else. The second kind never needs your microphone.

Switch off **Dictation → Listen for the hotkey** and utt runs unarmed: no
microphone is opened, not even the rolling buffer that catches the first
syllable, and your hotkey is left alone for whatever else you have bound it to.
The menu bar says so, and **Run unarmed** there flips it without opening the
window. The API, your extensions and pasting the last transcript go on working
exactly as before.

Dictation is on unless you turn it off. Nothing about an existing setup
changes.

## utt says what it did with an extension

Everything utt decided about an extension — a key it refused, a clip that
failed, a filter that never answered, a file it could not write — went to the
system log and nowhere else, which is to say nowhere. An extension utt had
thrown out looked exactly like one that was not running.

Each extension's page now has a **Log** of its own, and the Extensions page has
the whole book, including manifests utt could not read at all. Those have no
page of their own, and until now their only symptom was that nothing happened.
A line that repeats is one entry with a count rather than a wall of the same
sentence.

Around it, three things for when an extension is the problem:

- A **Reveal** button for the extension's own `daemon.log`. utt serves it, so it
  still works when the extension's process is the thing that is broken — every
  other button on that page is answered by that process. It reveals the file in
  the Finder rather than opening it.
- A daemon that keeps crashing reads as **Crashed**, with the exit status,
  instead of as "not running". The advice changes with it: "Restart starts it"
  is wrong for a program that will die again in a second.
- **Copy diagnostics** on the Extensions page: every page's contents as text,
  plus the log, for a bug report. Anything you typed into an extension's
  settings is counted, never quoted.

## An extension can hear you as you speak

An extension that asks for it now receives the same live words the panel shows,
rewritten as they are decoded and once more when you let the key go.

They are closer to what was heard than to what will be pasted: none of your
text rules have run, they come from the smaller recogniser, and the real
transcript arrives separately and may differ from them in any way.

## An extension can ask where each word was spoken

Parakeet reports when each word was said, and utt was dropping the numbers on
the floor. An extension that sends audio can now ask for them and get a start
and an end beside every word — which is what a caption, a cut list or a
searchable recording is made of.

They describe what was heard, never what was rewritten: cleanup deletes filler
and your replacement rules change near misses, so a time pinned to the finished
text would name a word at a second where something else was said. Whisper
returns none rather than approximate ones, and an extension that does not ask
is sent nothing, since five minutes of speech is some seven hundred entries.

## Updating

Nothing you have set up needs redoing.
