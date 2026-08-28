import SwiftUI

/// The four-letter status pill from utty. utt has no VAD, so there is no "LIVE"
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

    var tint: Color {
        switch self {
        case .idle: .secondary
        case .recording: Palette.recording
        case .transcribing: Palette.warning
        case .error: .red
        }
    }

    init(_ status: TranscriptionFeature.Status) {
        switch status {
        case .idle: self = .idle
        case .recording: self = .recording
        case .transcribing: self = .transcribing
        case .failed: self = .error
        }
    }
}

struct RecorderStatePill: View {
    let state: RecorderState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.tint)
                .frame(width: 6, height: 6)
                .modifier(PulseIfRecording(active: state == .recording))
            Text(state.label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(state.tint)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(state.tint.opacity(0.10)))
        .overlay(Capsule().strokeBorder(state.tint.opacity(0.25), lineWidth: 0.5))
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
