Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

A correction to how plugins reach the menu bar, and two things about them that
were quietly wrong.

## A plugin belongs under utt's icon, not beside it

1.1.0 gave a plugin that asked for it an icon of its own in the menu bar. That
was the wrong shape. The menu bar is yours; a plugin is something you installed
*into utt*, and two of them meant three icons where there had been one.

A plugin now appears as a submenu inside utt's own menu, labelled with its name
and its symbol. What is in it has not changed — whatever the plugin reports
about itself, its daemon's state and a **Restart**, its own buttons, and a way
straight to its page. utt stays one mark in the menu bar however many plugins
you install.

## It asks before something you cannot take back

A plugin can mark a button as one that should not happen by accident, and utt
asks first. It was only asking on the plugin's page — pressed from the menu bar,
the same button went straight through. The menu bar is where a mis-click is
likelier, not less likely.

## A dropped setting no longer disappears in silence

utt refuses anything in a plugin's description it cannot show you honestly, and
drops it rather than guessing. That is still right, but the person who wrote the
plugin had no way to see it happen: they shipped three buttons, one appeared,
and nothing said why. utt now names what it refused in its log, once, so that is
a minute's work to find instead of an afternoon's.

## Updating

Nothing you have set up needs redoing. A plugin that asked for the menu bar
needs no change to move into utt's menu — it is the same flag.
