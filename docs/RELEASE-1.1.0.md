Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

A release about plugins standing on their own.

## A plugin can have its own menu bar icon

Until now a plugin lived inside utt's window. If it wanted to be reachable
without opening that window — the way a background program usually is — it had
to ship a second menu bar app of its own, built and signed and updated
separately, whose entire job was to be an icon.

A plugin can now ask for a menu bar item beside utt's, drawn with its own symbol
and its own colour. There is nothing extra to set up: its menu is built from
what the plugin already tells utt. Whatever it reports about itself is at the
top, its daemon's state and a **Restart** below that, then its own buttons, and
last a way straight to its page in utt.

utt's own icon has not changed. It is still utt's, and it still flashes a
plugin's colour while it is transcribing that plugin's audio.

## Two things that were quietly wrong

A plugin that named a button or a setting in the usual `openLog` style was
having it thrown away. Keys were being held to the rule for a plugin's
*identifier*, which has to stay lowercase because it becomes a filename — but a
key never becomes a filename. A plugin could arrive with half its buttons
missing and nothing to say why.

And a plugin that utt knew about *and* you had installed was listed twice on the
Plugins page, once under each heading. It now appears once, where it belongs.

## Updating

Nothing you have set up needs redoing.
