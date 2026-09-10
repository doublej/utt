import ComposableArchitecture
import SwiftUI
import UttCore

/// A page utt did not write. The controls come from the extension's manifest, so
/// this view renders a schema rather than a fixed list of settings — the one
/// place in the app where that is true.
///
/// Everything shown here was written by another process. It is displayed, never
/// interpreted: the status block is the extension's own words, and the settings are
/// whatever survived `ExtensionManifest.sanitized()`.
struct ExtensionPage: View {
    let store: StoreOf<AppFeature>
    let installed: InstalledExtension
    @Shared(.uttSettings) private var settings
    @State private var confirming: ExtensionAction?
    @State var removing = false

    var body: some View {
        // Two pages, not one with things greyed out. Until the person has ruled on
        // it there is nothing here to operate — its settings are not being read, its
        // buttons reach a program utt is not talking to — so the page is the
        // decision: what it says it is, what it asked for, yes or no.
        if installed.consent == .pending {
            pendingConsent
            about
            access
            removalConfirmation
        } else {
            approved
        }
    }

    @ViewBuilder
    private var approved: some View {
        if !installed.status.isEmpty {
            SettingsGroup("Status") {
                // Alphabetical: a JSON object has no order to preserve, and
                // inventing one would put the fields in an order the extension
                // did not choose either.
                ForEach(installed.status.keys.sorted(), id: \.self) { key in
                    SettingRow(key.asFieldLabel) {
                        Text(installed.status[key] ?? "")
                            .font(Typography.metadata)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
        }

        if let daemon = installed.manifest.daemon {
            SettingsGroup("Daemon") {
                SettingRow(
                    daemon.label,
                    detail: daemonDetail,
                    detailTint: daemonState == .stopped ? Palette.warning : Palette.textTertiary
                ) {
                    Button("Restart") {
                        store.send(.settings(.extensionDaemonRestartTapped(installed.id)))
                    }
                    .font(Typography.metadata)
                }
            }
        }

        if !installed.manifest.actions.isEmpty {
            SettingsGroup("Actions") {
                ForEach(installed.manifest.actions) { action in
                    SettingRow(action.label, detail: action.detail) {
                        Button(action.label) { press(action) }
                            .font(Typography.metadata)
                    }
                }
            }
        }

        if installed.settings.isEmpty {
            Card {
                Text("\(installed.manifest.name) has no settings to change here.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textTertiary)
            }
        } else {
            SettingsGroup("Settings") {
                ForEach(installed.settings) { setting in
                    row(setting)
                }
            }
        }

        about
        confirmation
        access
        management
        removalConfirmation
    }

    /// utt's own switch and its own eject button, last on the page: everything
    /// above is the extension describing itself; this is what the person can do to it.
    private var management: some View {
        SettingsGroup("In utt") {
            SettingRow(
                "Enabled",
                detail: "Off keeps this page and the extension's settings, but utt stops handing it transcripts and audio, stops waiting for its answers, and takes it out of the menu bar."
            ) {
                Toggle("Enabled", isOn: Binding(
                    get: { installed.enabled },
                    set: { store.send(.settings(.extensionEnabledChanged(installed.id, $0))) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.accent)
            }
            // Only for an extension that sends clips. On one that does not there is
            // no queue for it to have a place in, and the row would be a control
            // that changes nothing.
            if installed.manifest.sendsAudio {
                SettingRow("Its clips are transcribed", detail: priorityNote) {
                    Picker("Its clips are transcribed", selection: Binding(
                        get: { installed.priority },
                        set: { store.send(.settings(.extensionPriorityChanged(installed.id, $0))) }
                    )) {
                        ForEach(ExtensionPriority.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            SettingRow(
                "Remove from utt",
                detail: "Moves the files utt keeps for \(installed.manifest.name) to the Trash: this page, its settings and its status. The program itself is not touched, and one that is still running may add itself back."
            ) {
                Button("Remove…") { removing = true }
                    .font(Typography.metadata)
            }
        }
    }

    var removalConfirmation: some View {
        EmptyView().alert("Remove \(installed.manifest.name) from utt?", isPresented: $removing) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                store.send(.settings(.extensionRemoveTapped(installed.id)))
                SettingsRoute.shared.open(.extensions)
            }
        } message: {
            Text("Its files go to the Trash. The program stays installed.")
        }
    }

    /// Attached to the page rather than to a row: the alert has to survive the
    /// list redrawing under it, which it does every three seconds.
    private var confirmation: some View {
        EmptyView().alert(
            confirming?.label ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } })
        ) {
            Button("Cancel", role: .cancel) { confirming = nil }
            Button(confirming?.label ?? "Continue") {
                if let action = confirming {
                    store.send(.settings(.extensionActionTapped(installed.id, key: action.key)))
                }
                confirming = nil
            }
        } message: {
            Text(confirming?.detail ?? "")
        }
    }

    private var daemonState: ExtensionDaemonState {
        store.settings.daemonStates[installed.id] ?? .unknown
    }

    /// What launchd says, not what the extension says about itself. A crashed daemon
    /// leaves a status file claiming it is up, and that is the one state the
    /// extension's own file cannot report.
    private var daemonDetail: String {
        switch daemonState {
        case .running: daemonState.summary
        case .stopped: "\(daemonState.summary). launchd has the job but nothing is running. Restart starts it."
        case .unknown: "\(daemonState.summary). launchd has no job by this name on this Mac, so Restart cannot help until the extension installs it."
        }
    }

    private func press(_ action: ExtensionAction) {
        guard !action.confirms else { return confirming = action }
        store.send(.settings(.extensionActionTapped(installed.id, key: action.key)))
    }

    /// Which stages this extension opted out of, named the way the pages that own them
    /// are named. It is on the page rather than silent because the alternative is a
    /// person editing a replacement rule and watching it not take effect.
    var skipNote: String {
        let stages = installed.manifest.skipsTextStages.map(\.pageName).sorted()
        return "\(installed.manifest.name) asked for its own clips back without \(stages.joined(separator: " or ")). "
            + "Only the audio it sends itself — what you dictate is untouched."
    }

    /// The manifest's own words about itself and where it lives, only when it gave
    /// any. Links are `https` or they were dropped at the trust boundary.
    @ViewBuilder
    var about: some View {
        let manifest = installed.manifest
        if manifest.description != nil || manifest.websiteURL != nil || manifest.repositoryURL != nil {
            SettingsGroup("About") {
                if let description = manifest.description {
                    SettingRow(manifest.name, detail: description) { EmptyView() }
                }
                if let url = manifest.websiteURL {
                    SettingRow("Website", detail: url.host() ?? "") {
                        Link("Open", destination: url).font(Typography.metadata)
                    }
                }
                if let url = manifest.repositoryURL {
                    SettingRow("Source code", detail: url.host() ?? "") {
                        Link("Open", destination: url).font(Typography.metadata)
                    }
                }
            }
        }
    }

    /// The token is a credential, and handing one to an extension is a thing the user
    /// should be able to see having happened — so the page says it plainly rather
    /// than leaving it to whoever reads the values file.
    ///
    /// It names the file rather than reassuring. "Only your account can read it" was
    /// the wrong promise twice over: the account is not the boundary — utt is not
    /// sandboxed and Application Support carries no TCC prompt, so anything the person
    /// runs is already their account — and the mode that makes it true at all is one
    /// utt now sets itself rather than inheriting. Where the file is, they can check.
    /// Says what the choice does and, in the same breath, what it does not: the
    /// first thing anyone wonders about a queue is whether jumping it stops what is
    /// already running.
    private var priorityNote: String {
        "Where \(installed.manifest.name)'s clips go when more than one extension is "
            + "waiting. Whatever utt is transcribing right now finishes either way — "
            + "this decides what goes next, never what gets interrupted."
    }

    /// A warning rather than an aside when the extension asked for a token the API
    /// is not currently minting: it is the one claim on the list that utt is not
    /// honouring, and the row has to say so rather than read as satisfied.
    var apiTint: Color { settings.api.enabled ? Palette.textTertiary : Palette.warning }

    var apiNote: String {
        settings.api.enabled
            ? "utt put the token in this extension's own settings file, in Application Support. Any program you run can read it, the same as this one."
            : "utt's API is off, so this extension has no token. Turn it on under Connect › API if the extension needs one."
    }
}
