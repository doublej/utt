import ComposableArchitecture
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "extensions.consent")

/// Who said yes. Installing an extension is dropping a file in a folder — no
/// installer, no registry, no signing — and that is worth keeping. What it cannot
/// stay is *silent*: a manifest that appears can ask for the audio, every
/// transcript, and the API token, and until this it got all three the moment it
/// landed.
///
/// So the file still arrives on its own, and one step is added where the person
/// says yes. Nothing else about installing changes.
extension ExtensionStore {
    /// What the person has said about this extension. No record means they have
    /// not been asked yet.
    static func consent(_ id: String) -> ExtensionConsent {
        guard let url = consentFile(id),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ExtensionConsentFile.self, from: data)
        else { return .pending }
        return file.decision
    }

    /// Records the person's answer. The only thing that ever writes one.
    static func decide(_ id: String, _ decision: ExtensionConsent) {
        guard let url = consentFile(id) else { return }
        guard decision != .pending else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let file = ExtensionConsentFile(
            decision: decision,
            decidedAt: ISO8601DateFormatter().string(from: Date())
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).writePrivately(to: url)
        } catch {
            log.error("could not record consent for \(id, privacy: .public): \(error.localizedDescription)")
        }
    }

    /// Everything already installed, counted as ruled on — once, on the first launch
    /// that has consent in it.
    ///
    /// Consent arrived after these extensions did. The person has been living with
    /// them, and one that quietly stopped working after an update is a worse problem
    /// than the one being fixed here: nothing would say why, and the extension has no
    /// way to tell them. So a manifest that was here before utt started asking keeps
    /// working, and only what appears afterwards is pending.
    ///
    /// The old `<id>.disabled` marker carries over as its own answer: switching
    /// something off *is* ruling on it, and the person should not have to do it twice.
    ///
    /// The gate is a file rather than a settings key on purpose. "Reset to defaults"
    /// rewrites the settings file wholesale, and a flag living there would grandfather
    /// every pending extension a second time — which is the consent step failing open.
    static func grandfather(_ directory: URL, manifests: [String]) {
        let alreadyRan = grandfathered.withValue { ran -> Bool in
            let was = ran
            ran = true
            return was
        }
        guard !alreadyRan else { return }
        let marker = directory.appendingPathComponent(".consent-grandfathered")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        for name in manifests {
            let id = String(name.dropLast(".json".count))
            guard ExtensionManifest.isSafeIdentifier(id), consent(id) == .pending else { continue }
            let wasDisabled = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("\(id).disabled").path
            )
            decide(id, wasDisabled ? .disabled : .approved)
            log.notice("\(id, privacy: .public): carried over as \(wasDisabled ? "disabled" : "approved", privacy: .public)")
        }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    /// Read once per launch. `installed()` runs three times a second, and this is a
    /// question with one answer for the life of the process.
    private static let grandfathered = LockIsolated(false)

    private static func consentFile(_ id: String) -> URL? {
        guard ExtensionManifest.isSafeIdentifier(id) else { return nil }
        return try? URL.uttExtensionsDirectory.appendingPathComponent("\(id).consent.json")
    }
}
