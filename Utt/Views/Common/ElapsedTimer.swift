import SwiftUI

/// Counts up from a start date. Driven by `TimelineView` rather than a reducer
/// action so a running clock does not push 120 state mutations a minute through
/// the store.
struct ElapsedTimer: View {
    let startedAt: Date?
    var font: Font = Typography.timer
    var tint: Color = Palette.recording

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            Text(Self.format(elapsed: elapsed(now: context.date)))
                .font(font)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
    }

    private func elapsed(now: Date) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now.timeIntervalSince(startedAt))
    }

    static func format(elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
