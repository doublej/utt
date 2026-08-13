import CoreGraphics

/// Marks keyboard events utt generates itself so the global hotkey monitor does
/// not treat its own paste as unrelated user input.
enum SyntheticKeyEvent {
    private static let marker: Int64 = 0x757474

    static func mark(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: marker)
    }

    static func isMarked(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == marker
    }
}
