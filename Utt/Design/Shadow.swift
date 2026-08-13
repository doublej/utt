import SwiftUI

struct SoftShadow: ViewModifier {
    var radius: CGFloat = 18
    var yOffset: CGFloat = 8
    var opacity: Double = 0.18

    func body(content: Content) -> some View {
        content.shadow(color: Color.black.opacity(opacity), radius: radius, x: 0, y: yOffset)
    }
}

extension View {
    func softShadow(radius: CGFloat = 18, yOffset: CGFloat = 8, opacity: Double = 0.18) -> some View {
        modifier(SoftShadow(radius: radius, yOffset: yOffset, opacity: opacity))
    }
}
