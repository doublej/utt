import ComposableArchitecture
import SwiftUI

/// The walkthrough for the three grants utt cannot work without.
///
/// The steps tick themselves off: `AppFeature` polls permissions every two seconds,
/// so a card collapses within a moment of the switch being flipped over in System
/// Settings. Nothing here asks the user to come back and press Continue.
struct PermissionGuide: View {
    let store: StoreOf<AppFeature>
    @Environment(\.dismiss) private var dismiss

    private var missing: [Permission] { store.missingPermissions }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: Spacing.small) {
                    ForEach(Array(Permission.allCases.enumerated()), id: \.element) { index, permission in
                        PermissionStepCard(
                            number: index + 1,
                            permission: permission,
                            granted: !missing.contains(permission),
                            store: store
                        )
                    }
                }
                .padding(Spacing.medium)
            }
            // Pinned outside the scroller: three ungranted cards already overflow the
            // band, and macOS overlay scrollbars are invisible until you scroll — so
            // the one card saying the switch will not reach utt until it restarts was
            // the only thing guaranteed not to be seen.
            if store.needsRelaunch {
                RelaunchCard(store: store)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, Spacing.medium)
            }
            Divider()
            footer
        }
        .frame(width: 460, height: 580)
        .onChange(of: missing) { old, new in
            // Whatever the floating card was helping with just landed.
            if new.count < old.count { DragToSettingsPanel.shared.hide() }
        }
        .onDisappear { DragToSettingsPanel.shared.hide() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Let macOS hear you out")
                .font(Typography.sectionTitle)
            Text("Three switches, once. Nothing you say leaves this Mac.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.medium)
    }

    private var footer: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: missing.isEmpty ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(missing.isEmpty ? Palette.success : Palette.textTertiary)
            Text(missing.isEmpty
                ? "All set — hold your hotkey and talk."
                : "\(missing.count) of \(Permission.allCases.count) still to go.")
                .font(Typography.metadata)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(Spacing.medium)
    }

}

/// The amber "macOS is holding this one back" row. Shared with the onboarding
/// flow, which shows the same three grants and hits the same wall.
struct RelaunchCard: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(Palette.warning)
            Text("A switch you just flipped only reaches utt on the next launch.")
                .font(Typography.hint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Restart") { store.send(.relaunchTapped) }
                .font(Typography.metadata)
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(Palette.warning.opacity(0.12))
        )
    }
}

/// One numbered grant, its rationale, and the script for finding it in System
/// Settings. Takes the store rather than a closure: both callers hold one, and the
/// deep link and the floating drag card have to be raised together every time.
struct PermissionStepCard: View {
    let number: Int
    let permission: Permission
    let granted: Bool
    let store: StoreOf<AppFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
            HStack(alignment: .top, spacing: Spacing.extraSmall) {
                badge
                VStack(alignment: .leading, spacing: 1) {
                    Text(permission.title).font(Typography.primaryRow)
                    Text(permission.rationale)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                if !granted {
                    Button("Open") { open() }.font(Typography.metadata)
                }
            }
            if !granted {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(index + 1).")
                                .font(Typography.monoSmall)
                                .foregroundStyle(Palette.accent)
                            Text(step)
                                .font(Typography.hint)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                // Badge (22) + the header row's `Spacing.extraSmall`, so the script
                // hangs off the title rather than off the badge. Moves if the badge does.
                .padding(.leading, 30)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentSurface(radius: Radius.medium)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(granted ? Palette.success : Palette.accentSoft)
                .frame(width: 22, height: 22)
            if granted {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("\(number)")
                    .font(Typography.label)
                    .foregroundStyle(Palette.accent)
            }
        }
    }

    /// `grantTapped` prompts when macOS still has a prompt left to spend and deep
    /// links when it does not. The floating card only ever shows itself once a
    /// System Settings window actually appears, so raising it either way is safe.
    private func open() {
        store.send(.grantTapped(permission))
        DragToSettingsPanel.shared.show(for: permission)
    }

    /// Microphone is a request-only pane — no `+` button, no drop target — so it
    /// gets the shorter script.
    private var steps: [String] {
        var steps = ["Click Open. System Settings opens on \(permission.settingsPath)."]
        if permission.supportsDropTarget {
            steps.append("Find utt in the list. Not there? Drag the floating card onto it.")
        } else {
            steps.append("If macOS asks, click OK. Otherwise find utt in the list.")
        }
        steps.append("Switch utt on.")
        return steps
    }
}
