# The transcription API

utt can serve its own engine over HTTP, so a phone, a script or another app can
send a clip and get the transcript back. The audio is still transcribed on this
Mac — the API moves the *recording* off the machine, never the transcription.

Off by default. Settings → General → Transcription API.

## Reach

One setting decides who can connect, and it is enforced twice: the listener binds
from it, and every accepted connection is filtered against the peer address.

| Setting | Binds to | Accepts |
| --- | --- | --- |
| This Mac only | `127.0.0.1` | loopback |
| This Mac and my local network | all interfaces | loopback, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `fc00::/7`, `fe80::/10` |
| Anywhere | all interfaces | anything that reaches the port |

"Anywhere" still needs a port forward to mean anything from outside the LAN, and
at that point the token is the only protection. There is no TLS: put it behind a
reverse proxy or a VPN if the traffic leaves your own network.

## Auth

Every request, `/health` included:

```
Authorization: Bearer <token>
```

The token is generated the first time the API is switched on and shown in the
settings card. "New" replaces it, which locks out every caller set up with the
old one. An empty token means the server does not start at all.

## Endpoints

Base URL is `http://<host>:<port>` — `127.0.0.1` for "This Mac only", otherwise
this Mac's Bonjour name (`something.local`), which survives the DHCP lease its IP
does not.

### `GET /health`

```json
{ "ok": true, "version": "0.5.2" }
```

### `POST /transcribe`

The body is the audio file itself. No multipart, no JSON envelope, no fields.

- `Content-Type` picks the file extension AVFoundation opens the clip with:
  `audio/wav` (the default for anything unrecognised), `audio/mp4`, `audio/mpeg`,
  `audio/aiff`, `audio/flac`, `audio/caf`.
- 25 MB maximum, refused before the body is read.
- Clips shorter than 0.3 s are rejected by the engine.

```bash
curl -X POST http://mac.local:8756/transcribe \
  -H "Authorization: Bearer $UTT_TOKEN" \
  -H "Content-Type: audio/wav" \
  --data-binary @clip.wav
```

```json
{ "text": "Hello world, this is a test of the transcription API." }
```

The transcript has been through the same pipeline the hotkey uses: the engine and
model named in Settings, then the word replacements and formatting rules. A
caller gets exactly what utt would have pasted.

Errors are `{"error": "..."}` with `400` (not audio, or an empty body), `401`
(token), `404` (path), `413` (too large) or `500` (the engine failed).

## Shape

One request per connection; the response carries `Connection: close`. There is no
keep-alive, no multipart parser and no routing table, because everything reachable
before the token is checked is attack surface. What is left of it —
`HttpRequestParser` and `ApiAccess` — lives in `UttCore` with tests.
