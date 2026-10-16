# utt for OpenCode

Dictate into OpenCode's prompt. OpenCode shows the whole dictation: a level
meter in the footer, the words in the prompt as utt hears them, and then the
finished transcript in their place. utt shows none of its own panels for it and
pastes nothing. Enter sends the prompt, as with anything you typed.

## Keys

| Key | What it does |
| --- | --- |
| `ctrl+s` | Start talking. Press it again to stop. Pressed while a transcript is still on its way, it starts the next take. |
| `ctrl+y` | Clear the prompt and start a new take. Works at any point. |
| `esc` | Throw the dictation away, also while it is still being transcribed. It only does this while a dictation is open; otherwise Esc does what it always does. |
| `enter` | Held while a dictation is open, so the prompt cannot go out before the transcript has replaced the live words. A toast says what it is waiting for. |

No key ever waits on utt, apart from Enter, which waits on purpose. The same
commands are in the palette (`utt: dictate`, `utt: clear and dictate again`) and
as `/dictate` and `/redictate`.

While a dictation is open, it takes over the whole prompt footer: `● listening`
with utt's level meter in its own green, yellow and red, or `◌ transcribing`,
then the speech model writing the transcript (`Parakeet Standard`), and the keys
that end it. The token count, cost and command hints come back when
the dictation closes. The live words are drawn italic in the theme's info colour.
The transcript lands in ordinary text, so you can tell when the words are final.

Words you already typed stay. The dictation goes in at the cursor, with a space
added where it would otherwise run into the text around it.

## Install

```sh
opencode plugin add utt-opencode
```

This adds `utt-opencode` to `plugins` in `~/.config/opencode/cli.json`. Restart
OpenCode to load it. The plugin needs macOS and [utt](https://utt.jurrejan.com/download).
Without utt it stays quiet until you press the key, then says where to get it.

Other keys go in the object form:

```json
{
  "plugins": [{ "package": "utt-opencode", "options": { "key": "ctrl+s", "redoKey": "ctrl+y" } }]
}
```

To run it from a checkout instead, put the folder's path where the package name
is, for example `"/Users/you/dev/swift/utt/opencode"`.

On first start the plugin registers itself with utt as the **OpenCode**
extension, and utt waits for you to approve it. The first time you press
`ctrl+s` before you have, utt opens on that page in place of recording. Approve
it there, then press `ctrl+s` again.

Until you approve it, and with a utt older than `ownsDictation`, the dictation is
an ordinary one: utt shows its own indicator and panel and pastes the text at the
cursor. The plugin then stays out of the prompt.

Words appear while you speak only if **Show words while you speak** is on in
utt. Those live words come from utt's smaller streaming model and are English
only. The transcript that replaces them comes from your chosen model, after your
replacements, cleanup and formatting.

## How it talks to utt

It uses the same two channels as the Raycast extension. Commands go through utt's
URL scheme, always opened with `open -g` so this terminal stays frontmost:

- `utt://start?for=opencode` starts a dictation of the plugin's own.
- `utt://stop` and `utt://cancel` end it.

Everything the plugin reads is an extension file in
`~/Library/Application Support/dev.jurrejan.utt/extensions/`:

| File | Direction | What for |
| --- | --- | --- |
| `opencode.json` | write | The manifest, rewritten at every start. Declares `ownsDictation`, `wantsTranscripts` and `wantsPartials` |
| `opencode.level.json` | read | The microphone level, about 20 times a second, for the meter, and the name of the speech model writing the transcript |
| `opencode.partial.json` | read | Words heard so far, while you speak |
| `opencode.transcript.json` | read | The finished transcript, or `""` when nothing came of it |
| `opencode.consent.json` | read | Whether you approved it, for the first-press detour |

The first write to `opencode.level.json` after the plugin starts a dictation is
how it knows utt handed that dictation over. Without one, utt is showing and
pasting the dictation itself, and the plugin stays out of the prompt. Every
dictation utt hands over ends in exactly one transcript write, so the plugin
never has to guess when to stop waiting. The full contract is the
`ownsDictation` section of utt's extension guide, which you can copy from the
Extensions page.

`wantsTranscripts` hands the plugin every transcript you dictate anywhere. It
only reads the file while a dictation it started is open, and it never sends
anything anywhere.

Every decision is logged to `~/Library/Logs/utt-opencode.log`. The log has one
line per event and records lengths, never the words.

## Development

```sh
just opencode-check   # typecheck, tests and the npm build
```

The npm package ships `dist/tui.js`, built by `bun build.ts` when it is packed.
OpenCode compiles a plugin's JSX only outside `node_modules`, so the package
cannot ship the `.tsx` source. A local checkout still loads `tui.ts` directly.

Changes load on the next OpenCode start. To try it without utt listening, start
OpenCode with `UTT_APPLICATION_SUPPORT` pointed at a scratch folder and a fake
`open` first on `PATH`. Then write `opencode.consent.json`, `opencode.level.json`,
`opencode.partial.json` and `opencode.transcript.json` by hand.
