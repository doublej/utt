//
//  SettingsFeature+Extensions.swift
//  utt
//
//  The reducer's extension half: the poll that notices manifests appearing and
//  changing, and the one path that writes an extension's values file. Its own
//  file because the reducer is at the size limit, and this is the part of it that
//  is about somebody else's program.
//

import ComposableArchitecture
import Foundation
import UttCore

extension SettingsFeature {
    /// Extensions are files another process writes, so they appear and change without
    /// telling utt. The same 3 s cadence as the devices — an extension installed while
    /// the window is open shows up within one poll, and nothing needs FSEvents for
    /// a directory this small.
    ///
    /// Each poll also reconciles every values file: an extension that has just been
    /// installed gets one written from its own defaults, and one that declared
    /// `needsApi` picks up a token that was minted after it was installed.
    func watchExtensions() -> Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                let installed = extensions.installed()
                for item in installed {
                    ExtensionStore.reconcile(item, api: apiAccess)
                }
                // An extension that is working rewrites its status file as it goes, and
                // utt's menu is built from that. SwiftUI rebuilds a `MenuBarExtra`
                // whenever the state behind it changes, and a rebuild under an open
                // menu closes the menu — so a poll that lands while one is open is
                // dropped and the next one three seconds later carries it. Files are
                // still reconciled: that is a write nobody is reading.
                if !menuTracking.isOpen() {
                    await send(.extensionsLoaded(installed))
                    for item in installed {
                        guard let label = item.manifest.daemon?.label else { continue }
                        await send(.extensionDaemonStateLoaded(item.id, extensionDaemon.state(label)))
                    }
                }
                try await clock.sleep(for: .seconds(3))
            }
        }
        .cancellable(id: CancelID.extensionWatch, cancelInFlight: true)
    }

    /// What an extension that asked for API access is given — nil while the API is off
    /// or has no token, so an extension never holds a credential for a listener that
    /// is not running.
    var apiAccess: ExtensionApiAccess? {
        guard settings.api.enabled, !settings.api.token.isEmpty else { return nil }
        return ExtensionApiAccess(token: settings.api.token, port: settings.api.port)
    }

    /// Writes the extension's values file immediately rather than at the next poll:
    /// something is watching that file, and a three-second lag between flicking a
    /// switch and the extension obeying it reads as a broken switch.
    func change(
        extension id: String, key: String, to value: ExtensionValue, in state: inout State
    ) -> Effect<Action> {
        guard let index = state.extensions.firstIndex(where: { $0.id == id }),
              // The page shows no controls while nobody has ruled on it, and the
              // values file is not written for one either. Both hold here rather
              // than only in the view: this is the write path.
              state.extensions[index].consent != .pending,
              let setting = state.extensions[index].settings.first(where: { $0.key == key }),
              setting.accepts(value),
              // SwiftUI calls a binding's setter as the view settles, not only when
              // a person moves the control. Writing on those would advance the
              // revision every time the page is looked at, and an extension watching
              // that number would act on a change nobody made.
              setting.value != value
        else { return .none }

        var values = state.extensions[index].settings
            .reduce(into: [String: ExtensionValue]()) { $0[$1.key] = $1.value }
        values[key] = value
        state.extensions[index] = InstalledExtension(
            manifest: state.extensions[index].manifest,
            values: values,
            status: state.extensions[index].status,
            consent: state.extensions[index].consent,
            priority: state.extensions[index].priority
        )
        let api = state.extensions[index].manifest.needsApi ? apiAccess : nil
        return .run { [values] _ in extensions.write(id, values, api) }
    }
}
