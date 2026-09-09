import ComposableArchitecture
import SwiftUI

/// The settings window: a column of categories on the left, one page on the right.
///
/// Ten pages rather than four tabs because the four had become bins — "General"
/// held permissions, the model, sounds and the Dock icon, and the only way to find
/// a setting was to read every card. A category is one concern, named for the
/// thing it changes, and the page header says in a line what is on it.
struct SettingsPanel: View {
    let store: StoreOf<AppFeature>
    @Binding var showingGuide: Bool
    @Binding var showingOnboarding: Bool
    /// Shared, so the transcript panel can send someone straight to the Text page.
    @Bindable private var route = SettingsRoute.shared

    private var tab: Tab { route.tab }

    enum Tab: String, CaseIterable, Identifiable {
        case hotkey, microphone, model
        case delivery, text, history
        case sounds, permissions, general, about
        case api

        var id: String { rawValue }

        /// The sidebar, in reading order: what starts a recording, what comes out
        /// of it, then the app around both.
        static let groups: [(title: String, tabs: [Tab])] = [
            ("Dictate", [.hotkey, .microphone, .model]),
            ("Output", [.delivery, .text, .history]),
            ("App", [.sounds, .permissions, .general, .about]),
            ("Connect", [.api])
        ]

        var title: String {
            switch self {
            case .hotkey: "Hotkey"
            case .microphone: "Microphone"
            case .model: "Model"
            case .delivery: "Delivery"
            case .text: "Text"
            case .history: "History"
            case .sounds: "Sounds & Indicator"
            case .permissions: "Permissions"
            case .general: "General"
            case .about: "About"
            case .api: "API"
            }
        }

        var systemImage: String {
            switch self {
            case .hotkey: "keyboard"
            case .microphone: "mic"
            case .model: "cpu"
            case .delivery: "text.cursor"
            case .text: "textformat"
            case .history: "clock.arrow.circlepath"
            case .sounds: "speaker.wave.2"
            case .permissions: "lock.shield"
            case .general: "gearshape"
            case .about: "info.circle"
            case .api: "network"
            }
        }

        /// One line under the page title: what is on this page, for someone who
        /// arrived by scanning the sidebar.
        var blurb: String {
            switch self {
            case .hotkey: "The key you hold to talk, and how a press is read."
            case .microphone: "Which input utt listens to, and what happens around it while it does."
            case .model: "The engine and the model doing the transcribing. Everything runs on this Mac."
            case .delivery: "Where a transcript goes when you let go of the key."
            case .text: "How the words are cleaned up before they are pasted."
            case .history: "What utt keeps of what you said."
            case .sounds: "What you hear and see while a recording is running."
            case .permissions: "What macOS has to allow before utt can hear you and type for you."
            case .general: "How utt sits in the system."
            case .about: "Version, updates and who made the models."
            case .api: "Let another app or device send audio to this Mac and get text back."
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            SettingsSidebar(selection: $route.tab)
                .frame(width: 190)
            Rectangle()
                .fill(Palette.strokeHairline)
                .frame(width: 1)
                .padding(.vertical, Spacing.small)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    PageHeader(tab.systemImage, title: tab.title, subtitle: tab.blurb)
                    content
                }
                .padding(.leading, Spacing.medium)
                .padding(.bottom, Spacing.medium)
                // A new id per page: the scroll position starts at the top of every
                // page, instead of wherever the previous one was left.
                .id(tab)
                .transition(.opacity)
            }
            .animation(.smooth(duration: 0.18), value: tab)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .hotkey: HotkeyPage(store: store)
        case .microphone: MicrophonePage(store: store)
        case .model: ModelPage(store: store)
        case .delivery: DeliveryPage()
        case .text: TextPage()
        case .history: HistoryPage()
        case .sounds: SoundsPage()
        case .permissions: PermissionsPage(store: store, showingGuide: $showingGuide)
        case .general: GeneralPage(store: store, showingOnboarding: $showingOnboarding)
        case .about: AboutPage(store: store)
        case .api: ApiPage(store: store)
        }
    }
}
