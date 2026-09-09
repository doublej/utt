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
        **utt**, a macOS app that transcribes speech on-device. Nothing is sent to a
        cloud service: the client uploads a clip to the user's own Mac over the local
        network, and the Mac does the transcription.

        ## Connection

        - Base URL: `{{base}}`
        - Every request needs `Authorization: Bearer <token>`.
        - The token is shown in utt: Settings, General, Transcription API. Ask the
          user for it. Store it in the Keychain (or the platform equivalent), never
          in source and never in a URL you log.
        - Plain HTTP, no TLS. Assume the LAN. Do not add certificate pinning; do not
          silently retry against a different host.
        - Interactive OpenAPI reference: `{{base}}/docs?token=<token>` in a browser.

        ## Endpoints

        ### `GET /health`

        ```json
        { "ok": true, "version": "0.5.2" }
        ```

        Use it to check reachability and to validate a token the user just typed.

        ### `POST /transcribe`

        The request body is **the audio file itself**. Raw bytes.

        - Not multipart/form-data. Not base64. Not a JSON envelope with a field in it.
          Getting this wrong is the single most common failure — set the body to the
          file's contents and nothing else.
        - `Content-Type` selects the decoder: `audio/wav` (also the fallback for
          anything unrecognised), `audio/mp4`, `audio/mpeg`, `audio/aiff`,
          `audio/flac`, `audio/caf`.
        - Maximum 25 MB, refused before the body is read.

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
        | 400 | Empty body, or bytes no decoder recognised | Fix the request; do not retry as-is |
        | 401 | Missing or wrong token | Ask the user for the token again |
        | 404 | No such path | Fix the URL |
        | 413 | Over 25 MB | Split or re-encode the clip |
        | 500 | The engine failed — often a clip under 0.3 s | Surface it; a retry may work |

        ## Audio

        The engine wants **16 kHz mono**. It resamples anything else, so a 44.1 kHz
        stereo recording works, it is just wasted bytes over the network. Record at
        16 kHz mono where the platform lets you.

        Clips shorter than 0.3 s are rejected. Guard for that client-side rather than
        sending a tap of silence and showing the user a 500.

        On iOS, `AVAudioRecorder` with these settings produces exactly what the API
        wants, in a file you can upload with no conversion:

        ```swift
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

        ## A complete request

        ```swift
        struct Transcript: Decodable { let text: String }
        struct ApiError: Decodable { let error: String }

        func transcribe(clip: URL, token: String) async throws -> String {
            var request = URLRequest(url: URL(string: "{{base}}/transcribe")!)
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
          Do not hold a pooled socket open expecting keep-alive, and do not pipeline.
        - **The first request after utt launches can take ~30 seconds.** The model is
          compiled and loaded on demand. Show progress; do not time out at 10 s.
        - **The text is finished.** utt has already applied the user's word
          replacements and formatting rules. Do not capitalise, trim punctuation or
          "clean up" the transcript — you would be undoing what the user configured.
        - **The Mac's address moves.** Prefer the Bonjour name (`something.local`)
          the settings card shows over a DHCP-assigned IP.
        - **utt may simply be asleep or quit.** A connection refused is the normal
          case, not an error state worth a crash report. Poll `/health` before
          recording if you want to disable the button.
        """#
}
