import ComposableArchitecture
import SwiftUI

/// One settings page, chosen by the rail.
///
/// Eleven pages rather than four tabs because the four had become bins — "General"
/// held permissions, the model, sounds and the Dock icon, and the only way to find
/// a setting was to read every card. A category is one concern, named for the
/// thing it changes, and the page header says in a line what is on it.
struct SettingsPanel: View {
    let store: StoreOf<AppFeature>
    @Binding var showingGuide: Bool
    @Binding var showingOnboarding: Bool
    /// Shared, so the transcript panel can send someone straight to the Text page.
    @Bindable private var route = SettingsRoute.shared

    private var section: AppSection { route.section }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                PageHeader(section.systemImage, title: section.title, subtitle: section.blurb)
                content
            }
            .padding(.bottom, Spacing.medium)
            // A new id per page: the scroll position starts at the top of every
            // page, instead of wherever the previous one was left.
            .id(section)
            .transition(.opacity)
        }
        .animation(.smooth(duration: 0.18), value: section)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .history: EmptyView()
        case .hotkey: HotkeyPage(store: store)
        case .microphone: MicrophonePage(store: store)
        case .model: ModelPage(store: store)
        case .delivery: DeliveryPage()
        case .text: TextPage()
        case .retention: HistoryPage()
        case .sounds: SoundsPage()
        case .permissions: PermissionsPage(store: store, showingGuide: $showingGuide)
        case .general: GeneralPage(store: store, showingOnboarding: $showingOnboarding)
        case .about: AboutPage(store: store)
        case .api: ApiPage(store: store)
        case .plugins: PluginsPage(store: store)
        case let .plugin(manifest):
            // Resolved against the live list rather than drawn from the section:
            // the section carries the manifest as it was when the rail was built,
            // and the plugin's status and values move under it.
            if let plugin = store.settings.plugins.first(where: { $0.id == manifest.id }) {
                PluginPage(store: store, plugin: plugin)
            } else {
                Card {
                    Text("\(manifest.name) is no longer installed.")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }
}
