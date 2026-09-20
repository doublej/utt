# Api

## What this is

The HTTP listener utt exposes locally. `ApiServer` here binds the socket and
filters peers; `UttCore/Sources/UttCore/Api/` (see its `CLAUDE.md`) parses
requests and renders responses — the part a stranger's bytes actually reach.

## Invariants

- **The API's reach is enforced twice.** `ApiAccess` decides both what the
  listener binds to and which peers are accepted; "This Mac only" binds loopback
  so the port never appears on an interface, and the peer filter still runs.
  "Local network" means a subnet `getifaddrs` says this Mac is on, not a private
  address range — a VPN peer is private and elsewhere, and a phone on the same
  Wi-Fi is very often globally addressed over IPv6. Peer addresses parse through
  `inet_pton` or not at all: a split-on-the-separator reader lets `127.0.0.1.extra`
  through as loopback, which is the access filter failing *open*.
  Everything, `/health` included, needs the bearer token, and an enabled API with
  an empty token yields no `ApiConfiguration` and therefore no listener. `/docs`
  is the one endpoint that also takes the token from the query string — a browser
  address bar cannot set a header — and it is the reason the `Host` header is
  sanitised before `ApiDocs` interpolates it into a `<script>`.
- **A failed listener takes its configuration with it.** `NWListener` reports a
  failed bind asynchronously and documents it as terminal. Leaving
  `configuration` set means the next apply matches, does nothing, and the port
  stays dead while the settings still read "on" — so `.failed` tears down and
  `AppFeature.apiState` puts the reason in the card.
- **The API card binds through the store, not `@Shared`.** Every other settings
  control writes the shared file directly, which reaches no reducer — fine for a
  value something reads later, useless for one that has to start a listener now.
  `SettingsFeature.apiChanged` is the only write path, and it is what mints the
  token on first switch-on.

## Common change patterns

- **Add an endpoint** → one `case` in `ApiRoutes.respond`, one path in
  `ApiDocs.paths`, one section in `docs/api.md`. Anything parsed before the token
  is checked belongs in `UttCore/Api/` with tests — that is the part a stranger
  can reach. The OpenAPI document is a hand-escaped string, so it is parsed in a
  test: a bad escape renders a blank reference rather than failing to build.

## Related context

- [docs/api.md](../../../docs/api.md) — the HTTP API: reach, auth, endpoints
- `UttCore/Sources/UttCore/Api/CLAUDE.md` — request parsing and response
  rendering, with tests
