import CoreGraphics

enum Spacing {
    static let xxs: CGFloat = 4
    static let extraSmall: CGFloat = 8
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
}

enum Radius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 20
    static let pill: CGFloat = 999
}

enum Layout {
    /// The trailing column a setting's control sits in. Fixed, so a page of mixed
    /// switches, pickers, values and buttons reads as one column instead of a
    /// ragged edge that restarts at a different x on every row.
    static let controlColumn: CGFloat = 200
}
