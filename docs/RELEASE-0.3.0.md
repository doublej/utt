Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

This release is about what happens to the text *after* the model is done with
it: how it is rewritten, where it is delivered, and what you can do about it
when it comes out wrong.

## The Text tab is a tool now, not a page of checkboxes

Replacements are one ordered list of literal rules — "claude code" → "Claude
Code", "new line" → an actual line break — applied top to bottom, so a later
rule can rewrite an earlier one's output. The list can be dragged into the order
you want, each rule can be switched off without deleting it, and leaving the
written side empty deletes the word instead of replacing it.

Above the list is a live bench: a sample of text run through the whole pipeline
as you type, with a dot next to every rule that fires against it. "Why is my
rule not doing anything" is now something you can see rather than something you
have to dictate to find out. A preset seeds the punctuation people expect to be
able to *say*, and every seeded rule is yours to edit from there.

## Look before it lands

A paste into somebody else's document is not undoable in any way utt controls,
so delivery is now a choice. **Paste immediately** is the default and behaves as
it always has. **Review first** holds the transcript in a panel instead: ⏎
pastes it, ⎋ throws it away.

The panel itself is new either way. It shows what was transcribed without ever
taking focus, so you can keep typing straight through it, and it offers the one
action worth having at that moment: send a word straight to the replacement list
so the next transcript gets it right. It hides itself after a delay you set, or
stays until you dismiss it.

Pasting can also be switched off entirely, and whether utt leaves the text on
your clipboard is its own switch — honoured on the ⌥⇧V "paste that again" route
too.

## Models say what they are doing

The model card lists every model for the selected engine at once, with what each
one speaks, what it weighs, whether it is on this disk and which one is in
memory. Downloads show a real percentage; the CoreML compile that follows shows
the time it has taken, because it reports nothing to be a percentage of.

## Permissions, walked through

utt needs Accessibility, Input Monitoring and Microphone, and macOS grants each
one in a different place. First launch now opens a walkthrough that takes them
one at a time, with the app bundle draggable straight into the pane that wants
it.

## Fixes

- Switching model while the previous one was still loading no longer reports
  "could not load the transcription model" for a model that loaded fine. The
  engines load one model at a time; before, two loads could overlap and the
  slower one won, leaving the app holding the model you did not pick.
