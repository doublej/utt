Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

This release is about the first ninety seconds and about reaching utt from
somewhere other than utt: a first run that walks you through the switches macOS
puts in three different places, a microphone choice that survives being
unplugged, and a Raycast extension and a URL scheme that let other things start
a recording.

## First run is a walkthrough now

Launching utt for the first time opens five screens instead of a window full of
settings you have not been told the meaning of yet.

They go: what the gesture is, the three permissions macOS wants, the model
downloading in the background, the hotkey utt already picked for you, and two
practice rounds where you dictate something and watch it appear. Setup takes
about ninety seconds and the model download does not block any of it — it starts
at launch and is usually finished before you reach screen three.

Each screen carries one idea and does not restate it. The permission screen
pins the "utt has to restart before the switch reaches it" card outside the
scroller, so it is no longer the thing that falls below a fold macOS gives no
scrollbar for. The model card names the engine you actually selected, and a
CoreML compile that fails now says so instead of reporting a download failure.

## A microphone list, not a microphone

The Recording tab takes an ordered list of inputs rather than one pick. The
first device that is actually plugged in wins; if none of them is, utt falls
back to the system default. A headset you take to a meeting and a desk mic you
come back to no longer need switching between by hand.

A device that is not attached right now is still named in the list — "RØDE
NT-USB", marked *not connected*, not a bare CoreAudio UID. Only the machine the
device is plugged into can supply that name, which is exactly the machine that
cannot supply it when it matters, so utt remembers it. Plug the device back in
and utt reacquires it mid-session.

Settings written before this release still load: a single saved microphone
becomes a one-entry list.

## Raycast

`raycast/` is a Raycast extension with three commands:

- **Toggle Dictation** — start recording, or stop and paste what you said
- **Microphone** — set which microphone utt records from, with fallbacks
- **Recent Transcriptions** — paste or copy something utt already transcribed

It talks to the running app through its files in Application Support rather than
a bridge, so a microphone reordered in Raycast reaches utt with no relaunch.

## utt:// URLs

`utt://start`, `utt://stop`, `utt://toggle` and `utt://cancel` drive a recording
from a script, a Shortcut, or a Stream Deck.

Call them with `open -g`. The `-g` matters: the frontmost app when a recording
*stops* is the app the transcript is pasted into, so a caller that foregrounds
utt would dictate into utt's own window.

## Fixes

- Clicking utt in the Dock or Spotlight while it was already running brought
  nothing to the front. The window now shows and takes focus on activation.
- A genuine first launch skipped the walkthrough entirely. The settings store
  creates its file as it initialises, so "does settings.json exist" was already
  true by the time anything asked.
- The permission banner's sentence was broken, and said "Settings" where the
  walkthrough needed it to name a specific pane.
