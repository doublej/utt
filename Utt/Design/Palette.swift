import SwiftUI

enum Palette {
    static let accent = Color(red: 0.831, green: 0.314, blue: 0.118)
    static let accentSoft = accent.opacity(0.10)
    static let recording = accent
    static let success = Color(red: 0.239, green: 0.420, blue: 0.282)
    static let warning = Color.orange
    static let info = accent
    static let debug = Color.secondary
    static let strokeHairline = Color.primary.opacity(0.08)
    static let strokeGlass = Color.primary.opacity(0.05)
    static let strokeStrong = Color.primary.opacity(0.15)
    static let surfaceWindow = Color.clear
    static let surfacePrimary = Color(nsColor: .controlBackgroundColor).opacity(0.82)
    static let surfaceSecondary = Color.primary.opacity(0.035)
    static let lcdBackground = Color(red: 0.094, green: 0.094, blue: 0.078)
    static let lcdGreen = Color(red: 0.604, green: 0.820, blue: 0.478)
    static let lcdYellow = Color(red: 0.878, green: 0.627, blue: 0.133)
    static let lcdRed = Color(red: 1.0, green: 0.353, blue: 0.180)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color.secondary.opacity(0.7)
}
