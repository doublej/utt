import ComposableArchitecture
import Foundation
import UttCore

/// Who said yes. Installing an extension is dropping a file in a folder — no
/// installer, no registry, no signing — and that is worth keeping. What it cannot
/// stay is *silent*: a manifest that appears can ask for the audio, every
/// transcript, and the API token, and until this it got all three the moment it
/// landed.
///
/// So the file still arrives on its own, and one step is added where the person
/// says yes. Nothing else about installing changes.
extension ExtensionStore {
    /// Everything the person decided about this extension, or nil when they have
    /// not been asked yet. One read: `load()` wants both fields and runs three
    /// times a second.
    static func record(_ id: String) -> ExtensionConsentFile? {
        guard let url = consentFile(id),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(ExtensionConsentFile.self, from: data)
    }

    /// What the person has said about this extension. No record means they have
    /// not been asked yet.
    static func consent(_ id: String) -> ExtensionConsent {
        record(id)?.decision ?? .pending
    }

    /// Records the person's answer. The only thing that ever writes one.
    static func decide(_ id: String, _ decision: ExtensionConsent) {
        guard decision != .pending else {
            if let url = consentFile(id) { try? FileManager.default.removeItem(at: url) }
            return
        }
        write(id, ExtensionConsentFile(
            decision: decision,
            decidedAt: ISO8601DateFormatter().string(from: Date()),
            // Where they last put it in the queue, kept: approving something, or
            // switching it off and on again, is not them changing their mind about
            // where its clips go.
            priority: record(id)?.priority ?? .normal
        ))
    }

    /// Moves the extension in the queue, leaving the decision it sits beside alone.
    /// Only meaningful for one that sends audio; harmless on any other.
    static func prioritise(_ id: String, _ priority: ExtensionPriority) {
        // Nothing to move until they have ruled on it: a pending extension has no
        // clips being picked up, and writing a record here would read as consent.
        guard var file = record(id), file.decision != .pending else { return }
        file.priority = priority
        write(id, file)
    }

    private static func write(_ id: String, _ file: ExtensionConsentFile) {
        guard let url = consentFile(id) else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(file).writePrivately(to: url)
        } catch {
            ExtensionLog.problem(id, "could not record what you decided — \(error.localizedDescription)")
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
            ExtensionLog.note(id, "carried over as \(wasDisabled ? "disabled" : "approved") — it was installed before utt started asking")
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
