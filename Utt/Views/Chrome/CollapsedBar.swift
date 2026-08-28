import ComposableArchitecture
import SwiftUI

/// The 360×48 pill. This is the shape utt spends most of its life in, so it shows
/// the two things worth glancing at: whether it is recording, and which mic.
struct CollapsedBar: View {
    let store: StoreOf<AppFeature>
    @Binding var showingSettings: Bool
    @Binding var collapsed: Bool

    private var recording: Bool { store.transcription.isRecording }
    private var transcribing: Bool { store.transcription.status == .transcribing }
    private var active: Bool { recording || transcribing }

    var body: some View {
        HStack(spacing: Spacing.small) {
            UttMark(
                size: 16,
                tint: active ? Palette.recording : Color.secondary.opacity(0.7),
                recording: recording,
                level: Double(store.transcription.meterLevel)
            )
            label
            Spacer(minLength: Spacing.extraSmall)
            // The pair reads as one control cluster; 12pt between them made the
            // gear look like it had drifted off on its own.
            HStack(spacing: Spacing.xxs) {
                iconButton("gearshape", size: 12, help: "Settings") {
                    collapsed = false
                    showingSettings = true
                }
                // A chevron carries less ink than a gear at the same point size.
                iconButton("chevron.down", size: 13, help: "Expand") { collapsed = false }
            }
        }
        .padding(.leading, Spacing.extraLarge)
        .padding(.trailing, Spacing.large)
        .padding(.vertical, Spacing.xxs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Centred on the pill itself, not on the space left between the wordmark
        // and the buttons — those two are not the same width.
        .overlay { gauge.allowsHitTesting(false) }
        .chromeGlass(in: Capsule())
        .compositingGroup()
        .animation(.smooth(duration: 0.25), value: active)
    }

    /// The level readout, whatever form it takes. Lives in the middle of the pill
    /// so it does not shove the wordmark around as it appears and disappears.
    @ViewBuilder
    private var gauge: some View {
        if active {
            statusIndicator
        } else if case .ready = store.model, !store.needsRelaunch, store.missingPermissions.isEmpty {
            CompactVuMeter(level: store.transcription.meterLevel, active: false)
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if recording {
            HStack(spacing: 6) {
                CompactVuMeter(level: store.transcription.meterLevel, active: true)
                ElapsedTimer(
                    startedAt: store.transcription.recordingStartedAt,
                    font: .system(size: 12, weight: .semibold, design: .monospaced)
                )
            }
        } else if transcribing {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Processing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.recording)
            }
        }
    }

    private var label: some View {
        HStack(spacing: 6) {
            UttWordmark(size: 13, recording: active)
            if !active {
                subtitleView
            }
        }
    }

    /// The pill is small enough that only one line of context fits, so problems win
    /// it: a missing permission or an unloaded model matters more than the meter,
    /// which has the middle of the pill to itself.
    @ViewBuilder
    private var subtitleView: some View {
        if store.needsRelaunch {
            subtitleText("Restart to apply")
        } else if let first = store.missingPermissions.first {
            subtitleText("Needs \(first.title)")
        } else {
            switch store.model {
            case let .downloading(fraction): subtitleText("Downloading model \(Int(fraction * 100))%")
            case .idle, .loading: subtitleText("Loading model…")
            case .failed: subtitleText("Model needs setting up")
            case .ready: EmptyView()
            }
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(Typography.metadata)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func iconButton(
        _ name: String, size: CGFloat, help: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}
