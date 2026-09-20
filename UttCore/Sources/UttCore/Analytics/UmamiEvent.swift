import Foundation

/// One usage event, and the body Umami wants it in.
///
/// utt says on its own About page that nothing leaves the machine, so this is off
/// unless someone switches it on, and what it may carry is fixed here rather than
/// at the call sites: a name, a path, and values that are counts or choices. There
/// is no field a transcript, a file name, an app name or a device id could travel
/// in — `UmamiValue` has no case that takes free text from the outside world.
public struct UmamiEvent: Equatable, Sendable {
    /// The event name, as it appears in Umami's events list.
    public let name: String
    /// A path, so the dashboard's pages view reads like a list of what utt did.
    public let path: String
    /// The event's own properties. Counts stay numbers so they can be averaged.
    public let data: [String: UmamiValue]

    public init(name: String, path: String, data: [String: UmamiValue] = [:]) {
        self.name = name
        self.path = path
        self.data = data
    }
}

/// What an event property may be. Deliberately small: a number, a flag, or one of
/// utt's own identifiers — never a string that came from the user or from another
/// program.
public enum UmamiValue: Equatable, Sendable, Encodable {
    case count(Int)
    case flag(Bool)
    /// An identifier utt chose itself: an engine, a model id, a version.
    case identifier(String)

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .count(value): try container.encode(value)
        case let .flag(value): try container.encode(value)
        case let .identifier(value): try container.encode(value)
        }
    }
}

/// Where the events go, and how they are addressed.
public enum Umami {
    public static let endpoint = URL(string: "https://umami-inky-two.vercel.app/api/send")!

    /// The "utt (macOS)" website on that instance. Its own, rather than the one the
    /// utt web page reports to: a launch and a page visit are not the same event,
    /// and a dashboard that mixes them can answer neither question.
    public static let websiteID = "6536a8c6-212f-4366-a059-901df5de33b4"

    /// The website's domain. Umami matches the payload's hostname against it.
    public static let hostname = "utt.app"

    /// Umami reads the operating system and the browser off the user agent, and
    /// refuses what it reads as a bot — which a bare `utt/2.1.0` is. So the string
    /// is Safari's, with utt's own version on the end: the dashboard says macOS,
    /// and the release is still legible in the raw agent.
    public static func userAgent(version: String) -> String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15 utt/\(version)"
    }

    /// The JSON Umami's `/api/send` expects. Sorted keys, so a test can read it.
    public static func body(for event: UmamiEvent, language: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Envelope(payload: Payload(event: event, language: language)))
    }

    private struct Envelope: Encodable {
        let type = "event"
        let payload: Payload
    }

    /// The field names are Umami's. `screen` and `referrer` are empty rather than
    /// absent — a window size says which Mac this is, and there is no page to have
    /// come from.
    private struct Payload: Encodable {
        let website = Umami.websiteID
        let hostname = Umami.hostname
        let screen = ""
        let referrer = ""
        let title: String
        let url: String
        let name: String
        let language: String
        let data: [String: UmamiValue]

        init(event: UmamiEvent, language: String) {
            self.title = event.name
            self.url = event.path
            self.name = event.name
            self.language = language
            self.data = event.data
        }
    }
}

public extension UmamiEvent {
    /// utt started. The version is the question this one exists to answer: how much
    /// of the installed base an update has actually reached.
    static func launch(version: String, engine: String, model: String) -> UmamiEvent {
        UmamiEvent(
            name: "launch",
            path: "/launch",
            data: ["version": .identifier(version), "engine": .identifier(engine), "model": .identifier(model)]
        )
    }

    /// Somebody dictated something. The seconds are the clip's length, rounded —
    /// never the words in it, and never where they landed.
    static func dictation(
        engine: String, model: String, seconds: Int, cleanup: Bool, delivered: Bool
    ) -> UmamiEvent {
        UmamiEvent(
            name: "dictation",
            path: "/dictation",
            data: [
                "engine": .identifier(engine),
                "model": .identifier(model),
                "seconds": .count(seconds),
                "cleanup": .flag(cleanup),
                "delivered": .flag(delivered)
            ]
        )
    }

    /// A transcription utt did for something else — an API caller or an extension.
    /// Which of the two, and nothing about who was asking.
    static func backend(source: Source, engine: String, model: String) -> UmamiEvent {
        UmamiEvent(
            name: "backend",
            path: "/backend/\(source.rawValue)",
            data: ["source": .identifier(source.rawValue), "engine": .identifier(engine), "model": .identifier(model)]
        )
    }

    /// The two roads into utt that are not a person at this Mac.
    enum Source: String, Sendable {
        case api
        case extensionJob = "extension"
    }
}
