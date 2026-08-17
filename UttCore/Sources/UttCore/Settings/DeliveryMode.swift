import Foundation

/// What happens to a finished transcript.
///
/// `.review` exists because a paste into somebody else's document is not undoable
/// in any way utt controls — holding the text until the user says so is the only
/// honest way to offer a look before it lands.
public enum DeliveryMode: String, Codable, CaseIterable, Sendable {
    /// Paste at the cursor, then show what was pasted.
    case immediate
    /// Hold the transcript in the panel; paste only on confirm.
    case review

    public var title: String {
        switch self {
        case .immediate: "Paste immediately"
        case .review: "Review first"
        }
    }
}
