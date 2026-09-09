import Foundation

/// The brief the "Copy guide for an LLM" button puts on the clipboard.
///
/// Written to be pasted into a model with no other context: it states what utt is,
/// what the wire format is, and what will bite a client author — the parts a model
/// otherwise guesses wrong, like reaching for multipart or expecting keep-alive.
/// The token stays a placeholder on purpose; a guide pasted into a chat window
/// should not carry the secret with it.
public enum ApiGuide {
    public static func markdown(baseURL: String) -> String {
        template.replacingOccurrences(of: "{{base}}", with: baseURL)
    }

    private static let template = #"""
        # Write a client for the utt transcription API

        You are implementing a client that records audio and gets text back from
        **utt**, a macOS app that transcribes speech on-device. Audio goes to the
        user's Mac, not a cloud transcription service. Model setup may download weights.
        Use the existing project's language and architecture. Implement recording,
        connection settings, secure token entry, upload, and unchanged transcript display.

        ## Connection

        - Base URL: `{{base}}`
        - `127.0.0.1` and `localhost` mean the device running the client. On a phone,
          use the Mac's `.local` hostname or LAN IP and enable "This Mac and my local
          network" in utt. Make the base URL editable; do not guess a remote address.
        - Every request needs `Authorization: Bearer <token>`.
        - The token is shown in utt: Settings, General, Transcription API. Let the
          user enter it in the client UI, not in this chat. Store it in the Keychain
          (or platform equivalent); never put it in source, analytics, or logs.
        - Plain HTTP exposes audio and the token in transit. Use a trusted network;
          do not expose this port to the internet or silently switch hosts.
        - Interactive OpenAPI reference: `{{base}}/docs?token=<token>` in a browser.
          Only `/docs` accepts query-token auth. Treat that URL as a secret (including
          browser history); use the header for `/health` and `/transcribe`.

        ## Hints

        Send `X-Utt-Hints: cogwheel, TUI, deckhand` with a clip when you already know
        the vocabulary — the project, the screen, the terms in play. utt corrects
        near misses against that list and leaves everything else alone. These are
        exactly the words a recogniser gets wrong, and the ones carrying the meaning.

        ## Endpoints

        ### `GET /health`

        ```json
        { "ok": true, "version": "0.5.2" }
        ```

        The version above is illustrative. Use health to check reachability and auth;
        it does not load the model or prove transcription is ready.

        ### `POST /transcribe`

        The request body is **the audio file itself**. Raw bytes.

        - Not multipart/form-data. Not base64. Not a JSON envelope with a field in it.
          Getting this wrong is the single most common failure — set the body to the
          file's contents and nothing else.
        - `Content-Type` selects the decoder: `audio/wav` (also the fallback for
          anything unrecognised), `audio/mp4`, `audio/mpeg`, `audio/aiff`,
          `audio/flac`, `audio/caf`.
        - Send `Content-Length` equal to the file's byte count. Chunked transfer and
          streaming uploads are unsupported. Do not use `Expect: 100-continue`.
        - Maximum 26,214,400 bytes (25 MiB), including the audio container. Oversized
          declared lengths are rejected from the headers; check size before uploading.

        Success is `200`:

        ```json
        { "text": "Hello world, this is a test of the transcription API." }
        ```

        Failure is a status plus one sentence:

        ```json
        { "error": "POST the audio bytes as the request body." }
        ```

        | Status | Means | What the client should do |
        | --- | --- | --- |
        | 400 | Empty body or malformed HTTP request | Fix the request; do not retry as-is |
        | 401 | Missing or wrong token | Ask the user for the token again |
        | 404 | Unsupported path or method | Fix the URL and method |
        | 413 | Body over 25 MiB or headers over 8 KiB | Reduce size; split audio at valid container boundaries |
        | 500 | Audio decoding, model, or transcription failed | Surface the error; inspect the clip before manual retry |

        ## Audio

        The engine wants **16 kHz mono**. It resamples anything else, so a 44.1 kHz
        stereo recording works, it is just wasted bytes over the network. Record at
        16 kHz mono where the platform lets you.

        Parakeet rejects clips shorter than 0.3 s. Guard for that client-side;
        silence and engine-dependent output still need graceful handling.

        On iOS, `AVAudioRecorder` with these settings produces exactly what the API
        wants, in a file you can upload with no conversion:

        ```swift
        import AVFoundation

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: clipURL, settings: settings)
        ```

        Give the file a `.wav` extension and send `Content-Type: audio/wav`.
        Stop the recorder before uploading so the WAV header is finalised. Keep the
        file unchanged until upload completes; remove temporary audio when finished.

        On iOS, configure and activate an AVAudioSession for recording and request
        microphone permission with `NSMicrophoneUsageDescription`. Handle denial.
        LAN clients need `NSLocalNetworkUsageDescription`; for local HTTP configure
        `NSAppTransportSecurity` → `NSAllowsLocalNetworking`, checking target-OS rules.
        See [Apple's local network guidance](https://developer.apple.com/documentation/Technotes/tn3179-understanding-local-network-privacy)
        and [ATS local networking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking).
        A sandboxed macOS client also needs outgoing network and microphone capabilities.
        This API has no CORS/preflight support; do not assume a browser frontend can call it.

        ## A complete request

        Uploads to `{{base}}/transcribe`. URLSession supplies the file's Content-Length.

        ```swift
        import Foundation

        struct Transcript: Decodable { let text: String }
        struct ApiError: Decodable { let error: String }
        enum TranscribeError: Error {
            case rejected(status: Int, message: String?)
        }

        // Pass the user's configured base URL, initially {{base}}.
        func transcribe(clip: URL, baseURL: URL, token: String) async throws -> String {
            var request = URLRequest(url: baseURL.appendingPathComponent("transcribe"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
            // Transcription is fast, but a cold model load is not: allow minutes.
            request.timeoutInterval = 180

            let (data, response) = try await URLSession.shared.upload(for: request, fromFile: clip)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else {
                throw TranscribeError.rejected(
                    status: http.statusCode,
                    message: (try? JSONDecoder().decode(ApiError.self, from: data))?.error
                )
            }
            return try JSONDecoder().decode(Transcript.self, from: data).text
        }
        ```

        ## Things that will bite you

        - **One request per connection.** The response carries `Connection: close`.
          URLSession handles this automatically; reuse the session. Custom socket
          clients must reconnect for each request and must not pipeline.
        - **Cold transcription can take tens of seconds or longer.** Models load on
          demand; downloads and compilation can add time. Show an indeterminate
          transcribing state, not invented server progress; allow cancellation.
        - **A timeout does not prove the server stopped.** Do not automatically retry
          POSTs; preserve the clip for user-initiated retry. There is no job ID,
          streaming response, idempotency key, or server cancellation endpoint.
        - **The text is finished.** utt has already applied the user's word
          replacements and formatting rules. Do not capitalise, trim punctuation or
          "clean up" the transcript — you would be undoing what the user configured.
        - **The Mac's address moves.** Prefer the Bonjour name (`something.local`)
          the settings card shows over a DHCP-assigned IP.
        - **utt may simply be asleep or quit.** A connection refused is the normal
          case, not an error state worth a crash report. Poll `/health` before
          recording if useful, but avoid tight polling and still handle upload failures.
        """#
}
