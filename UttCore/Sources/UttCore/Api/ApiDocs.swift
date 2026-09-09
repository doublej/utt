import Foundation

/// The API's own reference: an OpenAPI document and the Redoc page that renders it.
///
/// Served from the app rather than hosted, so the reference always describes the
/// build that is answering, at the address the browser actually reached, with the
/// user's own port in the examples. A hosted copy would be a second thing to keep
/// in step with the routes.
public enum ApiDocs {
    /// `server` is the base URL the caller reached, so the examples name a host
    /// that works. Callers must have sanitised it — it is interpolated into a page.
    public static func openAPI(server: String, version: String) -> String {
        #"""
        {
          "openapi": "3.1.0",
          "info": {
            "title": "utt transcription API",
            "version": "\#(version)",
            "summary": "On-device speech to text, over HTTP.",
            "description": "\#(overview)"
          },
          "servers": [{ "url": "\#(server)", "description": "The Mac running utt" }],
          "security": [{ "bearer": [] }],
          "tags": \#(tags),
          "paths": \#(paths),
          "components": \#(components)
        }
        """#
    }

    /// The base URL to put in the reference, taken from the `Host` header the
    /// caller used so the examples name an address that actually works.
    ///
    /// The header is written by the caller and ends up inside a `<script>`, so it
    /// is checked rather than trusted: anything outside a hostname, an address and
    /// a port is dropped for loopback, and a `</script>` can never reach a browser.
    public static func server(host: String?, fallbackPort: UInt16) -> String {
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")
        guard let host, !host.isEmpty, host.count <= 255,
              host.unicodeScalars.allSatisfy(allowed.contains)
        else { return "http://127.0.0.1:\(fallbackPort)" }
        return "http://\(host)"
    }

    /// A self-contained page: the document is inlined rather than fetched, so the
    /// browser makes one authenticated request and Redoc never needs the token.
    /// `no-referrer` is what keeps the token in the address bar out of the Referer
    /// header the CDN would otherwise be handed.
    public static func redocPage(server: String, version: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <title>utt transcription API</title>
        <link rel="preconnect" href="https://cdn.redoc.ly">
        <style>
          body { margin: 0; font-family: -apple-system, system-ui, sans-serif; }
          #redoc { padding: 2rem; color: #444; }
        </style>
        </head>
        <body>
        <div id="redoc">Loading the reference. This page pulls Redoc from a CDN, so it needs the internet once.</div>
        <script src="https://cdn.redoc.ly/redoc/latest/bundles/redoc.standalone.js"></script>
        <script>
        Redoc.init(
          \(openAPI(server: server, version: version)),
          { expandResponses: "200", hideDownloadButton: false, jsonSampleExpandLevel: 3,
            theme: { typography: { fontFamily: "-apple-system, system-ui, sans-serif", code: { fontFamily: "ui-monospace, SFMono-Regular, monospace" } } } },
          document.getElementById("redoc")
        );
        </script>
        </body>
        </html>
        """
    }

    private static let overview = #"""
        utt transcribes speech on the Mac serving this page. Send a clip, get the text back — the audio never leaves the machine, only the recording does.\n\nThe transcript has already been through the engine, model and text rules configured in utt, so it is exactly what the hotkey would have pasted at the cursor. Do not post-process it.\n\nEvery endpoint needs the bearer token, which utt generates when the API is switched on and shows in Settings, General, Transcription API.
        """#

    private static let tags = #"""
        [
            { "name": "Transcription", "description": "Turn a clip into text." },
            { "name": "Status", "description": "Is utt there, and which build is it." }
          ]
        """#

    private static let paths = #"""
        {
            "/health": {
              "get": {
                "tags": ["Status"],
                "summary": "Check that utt is listening",
                "operationId": "health",
                "responses": {
                  "200": {
                    "description": "utt is running and the token was accepted.",
                    "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Health" } } }
                  },
                  "401": { "$ref": "#/components/responses/Unauthorized" }
                }
              }
            },
            "/transcribe": {
              "post": {
                "tags": ["Transcription"],
                "summary": "Transcribe an audio clip",
                "operationId": "transcribe",
                "description": "The request body is the audio file itself. No multipart form, no base64, no JSON envelope.\n\n`Content-Type` chooses the decoder: `audio/wav` (also the fallback for anything unrecognised), `audio/mp4`, `audio/mpeg`, `audio/aiff`, `audio/flac`, `audio/caf`.\n\nClips are capped at 25 MB and refused before the body is read. Anything shorter than 0.3 s is rejected by the engine. 16 kHz mono is what it wants; it resamples anything else.\n\nOne request per connection: the response carries `Connection: close`, so do not hold a pooled socket open expecting keep-alive.",
                "requestBody": {
                  "required": true,
                  "description": "The audio file, raw.",
                  "content": {
                    "audio/wav": { "schema": { "type": "string", "format": "binary" } },
                    "audio/mp4": { "schema": { "type": "string", "format": "binary" } },
                    "audio/mpeg": { "schema": { "type": "string", "format": "binary" } },
                    "audio/aiff": { "schema": { "type": "string", "format": "binary" } },
                    "audio/flac": { "schema": { "type": "string", "format": "binary" } },
                    "audio/caf": { "schema": { "type": "string", "format": "binary" } }
                  }
                },
                "responses": {
                  "200": {
                    "description": "The transcript, already through utt's own text rules.",
                    "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Transcript" } } }
                  },
                  "400": { "$ref": "#/components/responses/BadRequest" },
                  "401": { "$ref": "#/components/responses/Unauthorized" },
                  "413": { "$ref": "#/components/responses/TooLarge" },
                  "500": { "$ref": "#/components/responses/EngineFailed" }
                },
                "x-codeSamples": [
                  {
                    "lang": "Shell",
                    "label": "curl",
                    "source": "curl -X POST \"$UTT_URL/transcribe\" \\\n  -H \"Authorization: Bearer $UTT_TOKEN\" \\\n  -H \"Content-Type: audio/wav\" \\\n  --data-binary @clip.wav"
                  },
                  {
                    "lang": "Swift",
                    "label": "URLSession",
                    "source": "struct Transcript: Decodable { let text: String }\n\nvar request = URLRequest(url: URL(string: \"\\(baseURL)/transcribe\")!)\nrequest.httpMethod = \"POST\"\nrequest.setValue(\"Bearer \\(token)\", forHTTPHeaderField: \"Authorization\")\nrequest.setValue(\"audio/wav\", forHTTPHeaderField: \"Content-Type\")\n\nlet (data, response) = try await URLSession.shared.upload(for: request, fromFile: clipURL)\nguard (response as? HTTPURLResponse)?.statusCode == 200 else { throw TranscribeError.rejected(data) }\nlet text = try JSONDecoder().decode(Transcript.self, from: data).text"
                  },
                  {
                    "lang": "Python",
                    "label": "requests",
                    "source": "import requests\n\nwith open(\"clip.wav\", \"rb\") as clip:\n    reply = requests.post(\n        f\"{base_url}/transcribe\",\n        data=clip,\n        headers={\"Authorization\": f\"Bearer {token}\", \"Content-Type\": \"audio/wav\"},\n        timeout=180,\n    )\nreply.raise_for_status()\ntext = reply.json()[\"text\"]"
                  }
                ]
              }
            }
          }
        """#

    private static let components = #"""
        {
            "securitySchemes": {
              "bearer": {
                "type": "http",
                "scheme": "bearer",
                "description": "The token utt generated when the API was switched on. Settings, General, Transcription API. Send it on every request, this reference included."
              }
            },
            "schemas": {
              "Health": {
                "type": "object",
                "required": ["ok", "version"],
                "properties": {
                  "ok": { "type": "boolean", "const": true },
                  "version": { "type": "string", "description": "utt's marketing version.", "examples": ["0.5.2"] }
                }
              },
              "Transcript": {
                "type": "object",
                "required": ["text"],
                "properties": {
                  "text": {
                    "type": "string",
                    "description": "The transcript. Word replacements and formatting rules have already been applied.",
                    "examples": ["Hello world, this is a test of the transcription API."]
                  }
                }
              },
              "Error": {
                "type": "object",
                "required": ["error"],
                "properties": {
                  "error": { "type": "string", "description": "One sentence about what went wrong. Never a stack trace." }
                }
              }
            },
            "responses": {
              "Unauthorized": {
                "description": "Missing or wrong bearer token.",
                "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Error" },
                  "example": { "error": "Send Authorization: Bearer <token>. The token is in utt's settings." } } }
              },
              "BadRequest": {
                "description": "An empty body, or bytes no audio decoder recognised.",
                "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Error" },
                  "example": { "error": "POST the audio bytes as the request body." } } }
              },
              "TooLarge": {
                "description": "The clip is over the 25 MB cap.",
                "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Error" },
                  "example": { "error": "That clip is larger than 25 MB." } } }
              },
              "EngineFailed": {
                "description": "The clip arrived but the engine could not transcribe it. Too short, or a model that failed to load.",
                "content": { "application/json": { "schema": { "$ref": "#/components/schemas/Error" },
                  "example": { "error": "Could not transcribe that clip." } } }
              }
            }
          }
        """#
}
