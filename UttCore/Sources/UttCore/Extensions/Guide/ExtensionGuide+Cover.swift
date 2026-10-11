//
//  ExtensionGuide+Cover.swift
//  UttCore
//
//  The full-screen sign. Its own file because the guide is one long string and the
//  size rule is per file, not per idea.
//

import Foundation

/// The `cover` key: a sign over every screen, raised and lowered by an address the
/// extension serves and utt polls.
let extensionCoverGuide = #"""
    ## A sign over the screen: `cover`

    ```json
    {"id": "deckhand", "name": "Deckhand", "cover": {"url": "http://127.0.0.1:4180/health"}}
    ```

    Declare an address and utt asks it about every two seconds, while you are
    approved and switched on, whether to show a sign across every screen of this
    Mac. It is for saying the Mac is being driven from somewhere else, so that
    someone walking up to it knows touching it will interrupt something.

    utt sends a plain `GET`, with no token, and reads the top-level `cover` of the
    JSON answer:

    ```json
    {"cover": {"title": "Driven from the phone", "detail": "Two sessions are working. Touch anything to take over."}}
    ```

    - An object with a `title` raises the sign: the title large, the `detail`
      smaller beneath it. Both are one line each, trimmed — about 80 characters of
      title and 240 of detail. Write them to be read from across the room.
    - `cover` absent or `null` lowers it. Anything else in the answer is ignored, so
      this can be an endpoint you already serve, such as a health check.
    - **No answer is down.** Not answering within about a second and a half, an
      error status, or JSON utt cannot read all lower the sign. That is on purpose:
      if your process dies, its sign comes down with it rather than standing in
      front of the person about work that is no longer happening.
    - **The person at the Mac always wins.** The sign never takes focus and never
      swallows a click or a key, and any input at all — a key, a click, the mouse
      moving — takes it down at once. utt then ignores your "up" until the Mac has
      been left alone for a few seconds again, so an answer you wrote just before
      they sat down does not put it straight back. Lower it yourself as soon as you
      know they are there.
    - It is a sign, not a lock. There is no password and nothing on it to press,
      and it sits below the menu bar, the Dock and the system's own alerts.

    The address must be `http` or `https` on this Mac's loopback — `127.0.0.1`,
    `localhost` or `::1`. Any other is dropped and named in your **Log**: a manifest
    is a file any local program can write, and it must not be able to make utt poll
    the network. Redirects are not followed. Switching you off, or removing the key,
    takes the sign down and stops the polling.
    """#
