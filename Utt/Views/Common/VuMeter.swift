import SwiftUI

/// LCD-style segment meter. utty drove this from a backend-reported dB value; here
/// the input is the capture tap's own peak, 0...1, so the mapping happens in one
/// place instead of being invented twice.
struct VuMeter: View {
    /// 0...1 instantaneous level.
    let level: Float
    let active: Bool

    private static let segmentCount = 36
    private static let peakStart = segmentCount - 4
    private static let midStart = segmentCount - 12

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            KickerLabel(text: "VU", tint: active ? Palette.recording : .secondary)
            segments
            Spacer(minLength: 0)
            readout
        }
        .frame(height: 22)
    }

    private var readout: some View {
        Text(active ? String(format: "%.0f dB", decibels) : "standby")
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(active ? Palette.recording : .secondary)
            .monospacedDigit()
    }

    /// dBFS, floored at -60. A silent mic is `-inf` and would render as a dash.
    private var decibels: Double {
        guard level > 0.001 else { return -60 }
        return max(-60, 20 * log10(Double(level)))
    }

    private var segments: some View {
        HStack(spacing: 1) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                cell(index)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.lcdBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 0.5)
        )
    }

    private func cell(_ index: Int) -> some View {
        // Linear amplitude puts normal speech in the first few segments and leaves
        // most of the bar dark, so the fill follows the dB scale the readout shows.
        let normalized = (decibels + 60) / 60
        let activeCount = Int(min(max(normalized, 0), 1) * Double(Self.segmentCount))
        let isLit = active && index < activeCount
        let color = isLit ? segmentColor(index) : Color.white.opacity(active ? 0.12 : 0.05)
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 3, height: 12)
            .shadow(color: isLit ? color.opacity(0.45) : .clear, radius: 1.5)
    }

    private func segmentColor(_ index: Int) -> Color {
        if index >= Self.peakStart { return Palette.lcdRed }
        if index >= Self.midStart { return Palette.lcdYellow }
        return Palette.lcdGreen
    }
}

/// A fine-grained segment meter for the collapsed pill, horizontally laid out.
/// Shows instantaneous input level while recording or transcribing.
struct CompactVuMeter: View {
    /// 0...1 instantaneous level.
    let level: Float
    let active: Bool

    private static let segmentCount = 14
    private static let peakStart = Int(Double(segmentCount) * 0.86)
    private static let midStart = Int(Double(segmentCount) * 0.64)

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                cell(index)
            }
        }
        .frame(height: 10)
    }

    private func cell(_ index: Int) -> some View {
        let normalized = normalizedLevel
        let activeCount = Int(min(max(normalized, 0), 1) * Double(Self.segmentCount))
        let isLit = active && index < activeCount
        let color = isLit ? segmentColor(index) : Color.white.opacity(active ? 0.15 : 0.08)
        return RoundedRectangle(cornerRadius: 0.5, style: .continuous)
            .fill(color)
            .frame(width: 2, height: 10)
            .shadow(color: isLit ? color.opacity(0.5) : .clear, radius: 1)
    }

    /// dBFS-based, floored at -60 dB.
    private var normalizedLevel: Double {
        guard level > 0.001 else { return 0 }
        let decibels = max(-60, 20 * log10(Double(level)))
        return (decibels + 60) / 60
    }

    private func segmentColor(_ index: Int) -> Color {
        if index >= Self.peakStart { return Palette.lcdRed }
        if index >= Self.midStart { return Palette.lcdYellow }
        return Palette.lcdGreen
    }
}
