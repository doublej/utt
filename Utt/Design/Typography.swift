import SwiftUI

enum Typography {
    static let pageTitle = Font.system(size: 20, weight: .semibold)
    static let subtitle = Font.system(size: 12, weight: .regular)
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let primaryRow = Font.system(size: 14, weight: .regular)
    static let label = Font.system(size: 12, weight: .semibold)
    static let metadata = Font.system(size: 11, weight: .regular)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let hint = Font.system(size: 11, weight: .regular)
    static let timer = Font.system(size: 13, weight: .semibold, design: .monospaced)
}
