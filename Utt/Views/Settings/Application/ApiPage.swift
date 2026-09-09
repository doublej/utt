import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// The transcription API's controls. The address, the token and the reference are
/// on screen because the thing being configured runs on another device, and showing
/// them is the app's only way to hand them over.
///
/// Unlike the other pages these bindings go through the store rather than writing
/// `@Shared` directly: a bare write reaches no reducer, and switching the API on
/// has to reach the listener.
struct ApiPage: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings
    /// Which button last copied, so it can say so. Cleared on a timer.
    @State private var copied: String?

    private var api: ApiSettings { settings.api }

    var body: some View {
        SettingsGroup {
            SettingToggle(
                "Let other apps and devices send audio",
                detail: "Serves POST /transcribe from this Mac. The clip is still transcribed here. Nothing leaves the machine.",
                isOn: bind(\.enabled)
            )
            if api.enabled {
                status
            }
        }
        if api.enabled {
            SettingsGroup("Reach") {
                SettingRow(
                    "Reachable from",
                    detail: api.access.detail,
                    detailTint: api.access == .anywhere ? Palette.warning : Palette.textTertiary
                ) {
                    Picker("Reachable from", selection: bind(\.access)) {
                        ForEach(ApiAccess.allCases, id: \.self) { access in
                            Text(access.title).tag(access)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                SettingRow("Address") {
                    Text(url)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                    Button(label("address", "Copy")) { copy(url, as: "address") }
                        .font(Typography.metadata)
                }
                SettingRow("Port") {
                    TextField("Port", value: bind(\.port), format: .number.grouping(.never))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                }
            }
            SettingsGroup("Token") {
                SettingRow(
                    "Bearer token",
                    detail: "Every request has to carry it. New replaces it at once: every client set up with the old one gets 401 until it is given this one."
                ) {
                    Text(api.token)
                        .font(Typography.monoSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                    Button(label("token", "Copy")) { copy(api.token, as: "token") }
                        .font(Typography.metadata)
                    Button("New") { replaceToken() }.font(Typography.metadata)
                }
            }
            SettingsGroup("Hand it over") {
                SettingRow(
                    "Guide for an LLM",
                    detail: "A complete brief: endpoints, audio format, worked code, with the token left as a placeholder to fill in."
                ) {
                    Button(label("guide", "Copy guide")) {
                        copy(ApiGuide.markdown(baseURL: url), as: "guide")
                    }
                    .font(Typography.metadata)
                }
                SettingRow("Reference", detail: "The full reference, served by utt itself.") {
                    if let reference {
                        Link("Open", destination: reference).font(Typography.metadata)
                    }
                }
            }
        }
    }

    /// What the listener is doing, which is not what the toggle says. A port
    /// already in use leaves the switch on and nothing answering, and without this
    /// the only way to find that out is a client that cannot connect.
    private var status: some View {
        SettingRow("Status") {
            switch store.apiState {
            case .off:
                Text("Starting…")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.textTertiary)
            case let .listening(port):
                Label("Listening on port \(String(port))", systemImage: "checkmark.circle.fill")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.success)
            case let .failed(reason):
                Text(reason)
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.warning)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Loopback for "this Mac only" — the listener is on no other address. Otherwise
    /// the Bonjour name, which is the one address a phone can keep: an IP is a DHCP
    /// lease and has to be looked up again every time it changes.
    private var url: String {
        let host = api.access == .thisMac ? "127.0.0.1" : ProcessInfo.processInfo.hostName
        return "http://\(host):\(api.port)"
    }

    /// The token rides in the query string because a browser address bar cannot set
    /// a header. `/docs` is the only endpoint that accepts it there.
    private var reference: URL? {
        let token = api.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? api.token
        return URL(string: "\(url)/docs?token=\(token)")
    }

    private func replaceToken() {
        var api = settings.api
        api.token = ApiToken.generate()
        store.send(.settings(.apiChanged(api)))
    }

    private func label(_ name: String, _ idle: String) -> String {
        copied == name ? "Copied" : idle
    }

    private func copy(_ text: String, as name: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = name
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == name { copied = nil }
        }
    }

    private func bind<Value>(_ keyPath: WritableKeyPath<ApiSettings, Value>) -> Binding<Value> {
        Binding(
            get: { api[keyPath: keyPath] },
            set: { newValue in
                var api = settings.api
                api[keyPath: keyPath] = newValue
                store.send(.settings(.apiChanged(api)))
            }
        )
    }
}
