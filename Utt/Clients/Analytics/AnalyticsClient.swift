import ComposableArchitecture
import Dependencies
import DependenciesMacros
import Foundation
import UttCore
import os

private let log = Logger(subsystem: "dev.jurrejan.utt", category: "analytics")

/// Usage events, to the Umami instance named in `UttCore/Analytics`.
///
/// The switch is read **here**, on every send, rather than at the call sites: a
/// caller that forgets to check it is the only way this could ever send something
/// from a Mac whose owner said no, and there is no version of that bug worth
/// risking. Off is the default, and off means no request is made at all.
///
/// Fire and forget, deliberately. Nothing waits for it, nothing retries it, and a
/// failure is a debug line — an event that did not arrive is worth strictly less
/// than a dictation that stalled because a web server was slow.
@DependencyClient
struct AnalyticsClient: Sendable {
    var send: @Sendable (UmamiEvent) -> Void
}

extension AnalyticsClient: DependencyKey {
    static let liveValue: AnalyticsClient = {
        @Shared(.uttSettings) var settings
        let live = $settings
        return AnalyticsClient(send: { event in
            guard live.wrappedValue.usageAnalytics else { return }
            Task { await Collector.post(event) }
        })
    }()

    /// Nothing leaves a test run, a preview or a store with no dependencies set.
    static let testValue = AnalyticsClient(send: { _ in })
    static let previewValue = AnalyticsClient(send: { _ in })
}

extension DependencyValues {
    var analytics: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}

private enum Collector {
    /// Ephemeral: no cookie jar, no cache, nothing about these requests kept on
    /// disk between launches. A shared session would carry all three.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func post(_ event: UmamiEvent) async {
        var request = URLRequest(url: Umami.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Umami.userAgent(version: version), forHTTPHeaderField: "User-Agent")
        // The tracker script sends these beside the body; some deployments read the
        // website off the header rather than the payload.
        request.setValue(Umami.websiteID, forHTTPHeaderField: "x-umami-website-id")
        request.setValue(Umami.hostname, forHTTPHeaderField: "x-umami-hostname")
        // The language, never the region or the time zone: "en" is a preference,
        // "en_NL at UTC+2" is a person.
        let language = Locale.current.language.languageCode?.identifier ?? "en"

        do {
            request.httpBody = try Umami.body(for: event, language: language)
        } catch {
            log.error("could not encode \(event.name, privacy: .public)")
            return
        }

        // Offline is the ordinary case, not an exception worth surfacing: no panel,
        // no retry, no queue on disk. The event is gone and that is the end of it.
        guard let (_, response) = try? await session.data(for: request) else {
            log.debug("\(event.name, privacy: .public) not sent")
            return
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            log.debug("\(event.name, privacy: .public) refused with \(status)")
        }
    }
}
