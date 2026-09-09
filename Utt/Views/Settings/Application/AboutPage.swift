import ComposableArchitecture
import SwiftUI
import UttCore

struct AboutPage: View {
    let store: StoreOf<AppFeature>

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "0") (\(build ?? "0"))"
    }

    var body: some View {
        SettingsGroup {
            SettingRow("utt", detail: "Transcription that runs on this Mac. Nothing is uploaded.") {
                UttWordmark(size: 15, recording: false)
            }
            SettingRow("Version") {
                Text(version)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Palette.textTertiary)
                if store.updatesConfigured {
                    Button("Check for Updates…") { store.send(.checkForUpdatesTapped) }
                        .font(Typography.metadata)
                }
            }
        }

        SettingsGroup("Attribution") {
            // The converted model card lists Apache-2.0 in places; NVIDIA's upstream
            // NeMo licence is authoritative and it is CC-BY-4.0. Attribution is a
            // condition of that licence, not a courtesy.
            AttributionRow(
                title: "Parakeet TDT v3",
                detail: "NVIDIA NeMo, CC-BY-4.0",
                url: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3"
            )
            AttributionRow(
                title: "Whisper",
                detail: "OpenAI, MIT, via WhisperKit",
                url: "https://github.com/argmaxinc/argmax-oss-swift"
            )
        }
    }
}

private struct AttributionRow: View {
    let title: String
    let detail: String
    let url: String

    var body: some View {
        SettingRow(title, detail: detail) {
            if let link = URL(string: url) {
                Link("Open", destination: link).font(Typography.metadata)
            }
        }
    }
}
