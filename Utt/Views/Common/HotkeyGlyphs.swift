import SwiftUI
import UttCore

/// Renders a hotkey as key caps. `HotKey.glyphs` decides *what* the symbols are;
/// this only decides what they look like.
struct HotkeyGlyphs: View {
    let hotkey: HotKey
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 4) {
            if hotkey.isUnset {
                Text("Not set")
                    .font(Typography.metadata)
                    .foregroundStyle(Palette.warning)
            } else {
                ForEach(hotkey.glyphs, id: \.self) { glyph in
                    cap(glyph)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(hotkey.isUnset ? "No hotkey set" : hotkey.displayString)
    }

    private func cap(_ glyph: String) -> some View {
        Text(glyph)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .frame(minWidth: size + 7, minHeight: size + 7)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
            )
    }
}
