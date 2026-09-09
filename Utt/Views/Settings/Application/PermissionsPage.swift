import ComposableArchitecture
import SwiftUI
import UttCore

struct PermissionsPage: View {
    let store: StoreOf<AppFeature>
    @Binding var showingGuide: Bool

    var body: some View {
        SettingsGroup {
            ForEach(Permission.allCases, id: \.self) { permission in
                PermissionRow(
                    permission: permission,
                    granted: !store.missingPermissions.contains(permission),
                    action: { store.send(.grantTapped(permission)) }
                )
            }
        }

        SettingsGroup("Help") {
            if store.needsRelaunch {
                SettingRow("A permission was just granted", detail: "utt has to restart to pick it up.") {
                    Button("Restart utt") { store.send(.relaunchTapped) }
                        .font(Typography.metadata)
                }
            }
            SettingRow(
                "Something still not working?",
                detail: "The walkthrough opens System Settings on the right pane for each one."
            ) {
                Button("Walk me through it") { showingGuide = true }
                    .font(Typography.metadata)
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool
    let action: () -> Void

    /// The rationale is written as a clause for the banner ("Turn it on so utt
    /// can hear you"); here it stands alone, so it gets a capital and a stop.
    private var detail: String {
        permission.rationale.prefix(1).uppercased() + permission.rationale.dropFirst() + "."
    }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? Palette.success : Palette.warning)
            SettingRow(permission.title, detail: detail) {
                if granted {
                    Text("Allowed")
                        .font(Typography.metadata)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    Button("Allow", action: action).font(Typography.metadata)
                }
            }
        }
    }
}
