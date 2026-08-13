import ComposableArchitecture
import SwiftUI
import UttCore

struct AboutSettings: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "0") (\(build ?? "0"))"
    }

    var body: some View {
        Card("utt") {
            HStack {
                UttWordmark(size: 15, recording: false)
                Spacer()
                Text(version)
                    .font(Typography.monoSmall)
                    .foregroundStyle(Palette.textTertiary)
            }
            Text("Transcription that runs on this Mac. Nothing is uploaded.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
            if store.updatesConfigured {
                Button("Check for Updates…") { store.send(.checkForUpdatesTapped) }
                    .font(Typography.metadata)
            }
        }

        Card("Shortcuts") {
            ShortcutRow(label: "Push to talk", hotkey: settings.hotkey)
            ShortcutRow(label: "Paste last transcript", hotkey: AppFeature.pasteLastHotKey)
        }

        Card("Attribution") {
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

private struct ShortcutRow: View {
    let label: String
    let hotkey: HotKey

    var body: some View {
        HStack {
            Text(label).font(Typography.primaryRow)
            Spacer()
            HotkeyGlyphs(hotkey: hotkey)
        }
    }
}

private struct AttributionRow: View {
    let title: String
    let detail: String
    let url: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Typography.primaryRow)
                Text(detail)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer()
            if let link = URL(string: url) {
                Link("Open", destination: link).font(Typography.metadata)
            }
        }
    }
}
