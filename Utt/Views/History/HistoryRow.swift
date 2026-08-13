import SwiftUI
import UttCore

struct HistoryRow: View {
    let transcript: Transcript
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.text)
                    .font(Typography.primaryRow)
                    .foregroundStyle(Palette.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                metadata
            }
            Spacer(minLength: 0)
            // Actions appear on hover: a list of transcripts is for reading, and
            // two buttons per row turn it into a control panel.
            if hovering {
                actions
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.extraSmall)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(hovering ? Palette.surfaceSecondary : Color.clear)
        )
        .onHover { hovering = $0 }
    }

    private var metadata: some View {
        HStack(spacing: Spacing.extraSmall) {
            Text(transcript.timestamp, format: .dateTime.hour().minute())
            Text(ElapsedTimer.format(elapsed: transcript.duration))
            if let app = transcript.sourceAppName {
                Text(app)
            }
        }
        .font(Typography.monoSmall)
        .foregroundStyle(Palette.textTertiary)
    }

    private var actions: some View {
        HStack(spacing: 2) {
            button("doc.on.doc", help: "Copy", action: onCopy)
            button("trash", help: "Delete", action: onDelete)
        }
    }

    private func button(
        _ name: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
