import ComposableArchitecture
import SwiftUI

struct SettingsPanel: View {
    let store: StoreOf<AppFeature>
    @State private var tab: Tab = .recording

    enum Tab: String, CaseIterable, Identifiable {
        case recording, text, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .recording: "Recording"
            case .text: "Text"
            case .general: "General"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .recording: "mic"
            case .text: "textformat"
            case .general: "gearshape"
            case .about: "info.circle"
            }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.small) {
            picker
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    content
                }
                .padding(.bottom, Spacing.medium)
            }
        }
    }

    private var picker: some View {
        Picker("Section", selection: $tab) {
            ForEach(Tab.allCases) { tab in
                Label(tab.title, systemImage: tab.systemImage).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .recording: RecordingSettings(store: store)
        case .text: TextSettings()
        case .general: GeneralSettings(store: store)
        case .about: AboutSettings(store: store)
        }
    }
}
