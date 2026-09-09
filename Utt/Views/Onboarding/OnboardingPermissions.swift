import ComposableArchitecture
import SwiftUI

/// Screen 2: the three grants, absorbed from `PermissionGuide` rather than
/// rewritten. utt needs three where every comparable app needs two — the third is
/// Input Monitoring, the price of a `CGEventTap`, which is what buys suppression
/// that matches key *and* modifiers and real press/hold/release semantics.
///
/// Nothing here blocks. The cards tick themselves off within ~2 s of the switch
/// flipping, so there is no "I granted it, now what" moment and no Continue to
/// press twice.
struct OnboardingPermissions: View {
    let store: StoreOf<AppFeature>

    /// Microphone first: it is the only one of the three macOS can satisfy with a
    /// single OK in a system prompt, and a first action that succeeds in one click
    /// is a user who keeps going.
    ///
    /// Ordered here rather than in `Permission.allCases`, which also numbers
    /// `PermissionGuide`, orders the settings rows, and decides *which* warning the
    /// main window's banner shows — today Input Monitoring, the grant whose absence
    /// makes the app do nothing at all. Demoting it there would be a real
    /// downgrade for a cosmetic win here.
    private let order: [Permission] = [.microphone, .inputMonitoring, .accessibility]

    private var missing: [Permission] { store.missingPermissions }

    var body: some View {
        // The relaunch card is pinned outside the scroller. Three ungranted cards
        // already overflow the band, and macOS overlay scrollbars are invisible until
        // you scroll — so the one card saying the switch will not reach utt until it
        // restarts was the only thing guaranteed not to be seen.
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Spacing.small) {
                    ForEach(Array(order.enumerated()), id: \.element) { index, permission in
                        PermissionStepCard(
                            number: index + 1,
                            permission: permission,
                            granted: !missing.contains(permission),
                            store: store
                        )
                    }
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.medium)
            }
            if store.needsRelaunch {
                RelaunchCard(store: store)
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, Spacing.medium)
            }
        }
        .onChange(of: missing) { old, new in
            // Whatever the floating card was helping with just landed.
            if new.count < old.count { DragToSettingsPanel.shared.hide() }
        }
    }
}
