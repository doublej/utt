import SwiftUI

/// The four-letter status readout from utty. utt has no VAD, so there is no "LIVE"
/// state — the app is either waiting for the hotkey, recording, decoding, or broken.
enum RecorderState {
    case idle, recording, transcribing, error

    var label: String {
        switch self {
        case .idle: "IDLE"
        case .recording: "REC"
        case .transcribing: "BUSY"
        case .error: "ERR"
        }
    }

    /// The lamp's colour, and only the lamp's. utt's own LCD palette rather than
    /// the system's grey/orange/red, which is what made the badge read as
    /// something any app could have shipped.
    var tint: Color {
        switch self {
        case .idle: Palette.lcdGreen
        case .recording: Palette.recording
        case .transcribing: Palette.lcdYellow
        case .error: Palette.lcdRed
        }
    }
}

extension RecorderState {
    init(_ status: TranscriptionFeature.Status) {
        switch status {
        case .idle: self = .idle
        case .recording: self = .recording
        case .transcribing: self = .transcribing
        case .failed: self = .error
        }
    }
}

/// A lamp and a word. No capsule and no border: the bloom is what separates a lit
/// indicator from a printed swatch, and once the dot carries the colour the label
/// can stay text-coloured — which is also what keeps it legible on the light
/// surface the practice screen puts it on.
struct RecorderStatePill: View {
    let state: RecorderState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 5, height: 5)
                .shadow(color: state.tint.opacity(0.85), radius: 3.5)
                .modifier(PulseIfRecording(active: state == .recording))
            Text(state.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(state == .idle ? Palette.textSecondary : Palette.textPrimary)
        }
        .accessibilityLabel(state.label)
    }
}

private struct PulseIfRecording: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            content.symbolEffect(.pulse, options: .repeating)
        } else {
            content
        }
    }
}
