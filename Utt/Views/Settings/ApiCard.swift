import AppKit
import ComposableArchitecture
import SwiftUI
import UttCore

/// The transcription API's controls. The address and the token are on screen
/// because the thing being configured runs on another device, and showing them is
/// the app's only way to hand them over.
///
/// Unlike the other settings cards these bindings go through the store rather than
/// writing `@Shared` directly: a bare write reaches no reducer, and switching the
/// API on has to reach the listener.
struct ApiCard: View {
    let store: StoreOf<AppFeature>
    @Shared(.uttSettings) private var settings

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
            Button("Copy") { copy(url) }.font(Typography.metadata)
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
            Button("Copy") { copy(api.token) }.font(Typography.metadata)
            Button("New") { replaceToken() }.font(Typography.metadata)
        }
    }

    /// Loopback for "this Mac only" — the listener is on no other address. Otherwise
    /// the Bonjour name, which is the one address a phone can keep: an IP is a DHCP
    /// lease and has to be looked up again every time it changes.
    private var url: String {
        let host = api.access == .thisMac ? "127.0.0.1" : ProcessInfo.processInfo.hostName
        return "http://\(host):\(api.port)"
    }

    private func replaceToken() {
        var api = settings.api
        api.token = ApiToken.generate()
        store.send(.settings(.apiChanged(api)))
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
