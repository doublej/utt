import SwiftUI

/// The first stage: the bench, then the rules it is showing you. The bench stays
/// with the rules because a row's firing dot only means something next to the row
/// — and because it runs the whole pipeline, it doubles as the preview for the two
/// stages under this one.
struct ReplacementsPage: View {
    /// The text every rule below is measured against. Owned here because the bench
    /// edits it and the replacement rows read it.
    @State private var sample = RuleBench.cannedSample

    var body: some View {
        RuleBench(sample: $sample)
        ReplacementList(sample: sample)
    }
}
