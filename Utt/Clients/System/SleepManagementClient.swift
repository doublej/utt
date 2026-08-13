import Dependencies
import DependenciesMacros
import Foundation
import IOKit.pwr_mgt
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "sleep")

/// Holds a power assertion for the length of a recording.
///
/// `kIOPMAssertionTypePreventUserIdleSystemSleep` only blocks *idle* sleep — closing
/// the lid still sleeps the Mac, which is correct: nobody wants a dictation app that
/// refuses to let the machine sleep.
@DependencyClient
struct SleepManagementClient: Sendable {
    var preventSleep: @Sendable (_ reason: String) async -> Void
    var allowSleep: @Sendable () async -> Void
}

extension SleepManagementClient: DependencyKey {
    static let liveValue: SleepManagementClient = {
        let holder = AssertionHolder()
        return SleepManagementClient(
            preventSleep: { reason in await holder.hold(reason: reason) },
            allowSleep: { await holder.release() }
        )
    }()
}

extension DependencyValues {
    var sleepManagement: SleepManagementClient {
        get { self[SleepManagementClient.self] }
        set { self[SleepManagementClient.self] = newValue }
    }
}

private actor AssertionHolder {
    private var assertionID: IOPMAssertionID?

    func hold(reason: String) {
        // Re-holding without releasing would leak the previous assertion, and a leaked
        // one keeps the Mac awake until the process dies.
        guard assertionID == nil else { return }
        var identifier = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &identifier
        )
        guard status == kIOReturnSuccess else {
            log.error("could not create power assertion (\(status))")
            return
        }
        assertionID = identifier
    }

    func release() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}
