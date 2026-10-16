# Api

## What this is

The HTTP listener utt exposes locally. `ApiServer` here binds the socket and
filters peers; `UttCore/Sources/UttCore/Api/` (see its `CLAUDE.md`) parses
requests and renders responses — the part a stranger's bytes actually reach.
Reach modes, auth and endpoints: `docs/api.md`.

## Invariants

- **The API's reach is enforced twice.** `ApiAccess` decides both the bind
  address and which peers are accepted; loopback mode still runs the peer
  filter. "Local network" means a subnet `getifaddrs` reports, not a private
  range (VPN peers are private and elsewhere; same-Wi-Fi phones are often
  global IPv6). Peer addresses parse through `inet_pton` or not at all — a
  split-on-separator reader lets `127.0.0.1.extra` through as loopback, failing
  *open*.
- **Every endpoint, `/health` included, needs the bearer token**; an empty token
  yields no `ApiConfiguration` and so no listener. `/docs` alone also takes the
  token from the query string (a browser bar cannot set a header), which is why
  the `Host` header is sanitised before `ApiDocs` puts it in a `<script>`.
- **A failed listener takes its configuration with it.** `NWListener` reports a
  failed bind asynchronously and terminally; keeping `configuration` set would
  make the next apply a no-op with the port dead and settings reading "on". So
  `.failed` tears down and `AppFeature.apiState` shows the reason in the card.
- **The API card binds through the store, not `@Shared`.** Writing the shared
  file reaches no reducer, so nothing would start the listener.
  `SettingsFeature.apiChanged` is the only write path and mints the token on
  first switch-on.

## Common change patterns

- **Add an endpoint** → one `case` in `ApiRoutes.respond`, one path in
  `ApiDocs.paths`, one section in `docs/api.md`. Anything parsed before the token
  is checked belongs in `UttCore/Api/` with tests. The OpenAPI document is a
  hand-escaped string parsed in a test: a bad escape renders a blank reference
  rather than failing to build.
