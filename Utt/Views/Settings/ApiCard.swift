import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// The transcription API's controls. The address, the token and the reference are
/// on screen because the thing being configured runs on another device, and showing
/// them is the app's only way to hand them over.
///
/// Unlike the other settings cards these bindings go through the store rather than
/// writing `@Shared` directly: a bare write reaches no reducer, and switching the
/// API on has to reach the listener.
struct ApiCard: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings
    /// Which button last copied, so it can say so. Cleared on a timer.
    @State private var copied: String?

    private var api: ApiSettings { settings.api }

    var body: some View {
        Card("Transcription API") {
            Toggle("Let other apps and devices send audio", isOn: bind(\.enabled))
                .help("Serves POST /transcribe from this Mac. The clip is still transcribed here — nothing leaves the machine.")
            if api.enabled {
                Divider()
                reach
                address
                port
                token
                Divider()
                handover
            }
        }
    }

    private var reach: some View {
        VStack(alignment: .leading, spacing: 2) {
            Picker("Reachable from", selection: bind(\.access)) {
                ForEach(ApiAccess.allCases, id: \.self) { access in
                    Text(access.title).tag(access)
                }
            }
            Text(api.access.detail)
                .font(Typography.hint)
                .foregroundStyle(api.access == .anywhere ? Palette.warning : Palette.textTertiary)
        }
    }

    private var address: some View {
        HStack {
            Text("Address").font(Typography.primaryRow)
            Spacer()
            Text(url)
                .font(Typography.monoSmall)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
            Button(label("address", "Copy")) { copy(url, as: "address") }
                .font(Typography.metadata)
        }
    }

    private var port: some View {
        HStack {
            Text("Port").font(Typography.primaryRow)
            Spacer()
            TextField("", value: bind(\.port), format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
    }

    private var token: some View {
        HStack {
            Text("Token").font(Typography.primaryRow)
            Spacer()
            Text(api.token)
                .font(Typography.monoSmall)
                .foregroundStyle(Palette.textSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button(label("token", "Copy")) { copy(api.token, as: "token") }
                .font(Typography.metadata)
            Button("New") { replaceToken() }.font(Typography.metadata)
        }
    }

    /// The two ways to hand this API to someone who has to build against it: a brief
    /// for a model, and the reference for a person.
    private var handover: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button(label("guide", "Copy guide for an LLM")) {
                    copy(ApiGuide.markdown(baseURL: url), as: "guide")
                }
                Spacer()
                if let reference {
                    Link("API reference", destination: reference)
                }
            }
            .font(Typography.metadata)
            Text("The guide is a complete brief — endpoints, audio format, worked code — with the token left as a placeholder to fill in.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)
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
