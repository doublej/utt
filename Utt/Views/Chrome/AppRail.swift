import ComposableArchitecture
import SwiftUI

/// The dark left column of the window: the mark, the recorder state, and every
/// section as a rail. It is the walkthrough's rail, kept — the ground a new user
/// met on the first screen is the ground they navigate on from then on.
///
/// Flush to the window edge and under the title bar; the top padding is what
/// clears the traffic lights. Rendered in the dark scheme whatever the window is
/// in, so the wordmark, the pill and `.secondary` text draw themselves right.
struct AppRail: View {
    let store: StoreOf<AppFeature>
    @Binding var selection: AppSection
    let collapse: () -> Void

    private var recorderState: RecorderState { RecorderState(store.transcription.status) }
    private var recording: Bool { recorderState == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.small) {
                UttMark(
                    size: 56,
                    tint: recording ? Palette.recording : Palette.accent,
                    recording: recording,
                    level: Double(store.transcription.meterLevel),
                    hotCore: 0.3
                )
                Spacer(minLength: 0)
                RecorderStatePill(state: recorderState)
            }
            .padding(.bottom, Spacing.large)
            ForEach(AppSection.groups(plugins: store.settings.plugins.map(\.manifest)), id: \.title) { group in
                RailGroup(title: group.title, sections: group.sections, selection: $selection)
            }
            Spacer(minLength: Spacing.medium)
            HStack {
                UttWordmark(size: 13, recording: recording)
                Spacer()
                Button(action: collapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Collapse")
                .accessibilityLabel("Collapse")
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.top, 44)
        .padding(.bottom, Spacing.medium)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.lcdGround)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }
}

private struct RailGroup: View {
    let title: String
    let sections: [AppSection]
    @Binding var selection: AppSection

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !title.isEmpty {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.extraSmall)
                    .padding(.top, Spacing.small)
                    .padding(.bottom, Spacing.xxs)
            }
            ForEach(sections) { section in
                RailRow(section: section, selected: section == selection) { selection = section }
            }
        }
    }
}

private struct RailRow: View {
    let section: AppSection
    let selected: Bool
    let select: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.extraSmall) {
                CategoryIcon(section.systemImage, size: 20, prominent: selected)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                    .fill(Color.primary.opacity(selected ? 0.10 : hovering ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
