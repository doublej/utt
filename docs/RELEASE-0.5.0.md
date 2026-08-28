Hold a key, speak, release. The text lands at your cursor. Nothing leaves the
machine.

This release is about the copy of utt you already have. Until now the only way
to get a newer one was to notice a release existed, find the disk image, and
drag it over the old app yourself. From this version on utt does that itself.

## utt updates itself

utt checks once a day for a newer version and tells you when it finds one. You
get the release notes, and a choice: install now, remind me later, or skip this
version. Nothing is downloaded in the background and nothing is swapped in
underneath you — an update installs when you say so, never in the middle of a
recording.

There is a **Check for Updates…** button in Settings → About if you would rather
ask than wait.

The check talks to one file in utt's own public repository and sends nothing
about you or your machine. Every update is signed with a key that never leaves
this Mac, and utt refuses to install one whose signature does not match — a
tampered download is rejected before it is unpacked.

Updating keeps utt's permissions. Accessibility, Input Monitoring and Microphone
are granted to the app's signature rather than to a copy of it, and the
signature does not change across an update, so you are not walked back through
System Settings after every release.

## The window comes to the front

Clicking utt in the menu bar, opening Settings from the transcript panel, or
double-clicking the app while something else was in front used to open the
window *behind* whatever you were looking at. macOS 14 changed how an app is
allowed to take focus, and the call utt was making had quietly stopped working
for a menu bar app. utt now asks a way that works, checks whether it landed, and
asks the system to do it if not.

## The walkthrough stays where you left it

Whether you have seen the first-run walkthrough is now a single saved setting,
so it opens once on a genuinely new install and not again. It used to be
inferred from whether a settings file existed, which was true a fraction of a
second after launch on the very first run — so the one launch that needed the
walkthrough was the one that sometimes did not get it.

Settings → General has a **Show the walkthrough again** button for when you
want it back.

Settings written by an earlier version still load, and a file from before the
walkthrough existed counts as already seen.
