import ComposableArchitecture
import SwiftUI

struct HeaderBar: View {
    let store: StoreOf<AppFeature>
    @Binding var showingSettings: Bool
    @Binding var collapsed: Bool

    private var recorderState: RecorderState { RecorderState(store.transcription.status) }

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            UttMark(
                size: 17,
                tint: recorderState == .recording ? Palette.recording : Palette.accent,
                recording: recorderState == .recording,
                level: Double(store.transcription.meterLevel)
            )
            UttWordmark(recording: recorderState == .recording)
            RecorderStatePill(state: recorderState)
            Spacer()
            iconButton("gearshape", help: "Settings") { showingSettings.toggle() }
                .keyboardShortcut(",", modifiers: .command)
            iconButton("chevron.up", help: "Collapse") {
                showingSettings = false
                collapsed = true
            }
        }
        .padding(.horizontal, Spacing.medium)
        .frame(height: 32)
        .contentShape(Rectangle())
        .chromeGlass(radius: Radius.medium)
    }

    private func iconButton(
        _ name: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
