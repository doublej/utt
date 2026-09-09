import Foundation

/// A colour as three components, 0...1. Its own type rather than a tuple so it can
/// travel through observable state and be compared.
public struct PluginRGB: Equatable, Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// One control on a plugin's page.
public struct PluginSetting: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Hashable, Sendable {
        case bool, string, number, choice
    }

    public var id: String { key }
    public let key: String
    public let kind: Kind
    public let label: String
    /// The explanation under the control — utt puts it on the page, not in a tooltip.
    public var detail: String?
    /// `choice` only.
    public var options: [String] = []
    /// What the control shows until someone changes it.
    public var value: PluginValue

    public init(
        key: String, kind: Kind, label: String,
        detail: String? = nil, options: [String] = [], value: PluginValue
    ) {
        self.key = key
        self.kind = kind
        self.label = label
        self.detail = detail
        self.options = options
        self.value = value
    }

    enum CodingKeys: String, CodingKey { case key, kind, label, detail, options, value }

    /// Forgiving for the same reason as the manifest's: a `bool` setting has no
    /// `options` to give, and demanding the key would reject every plugin that
    /// omits it — which is every plugin.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        kind = try container.decode(Kind.self, forKey: .kind)
        label = try container.decode(String.self, forKey: .label)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
        options = (try? container.decodeIfPresent([String].self, forKey: .options)) ?? []
        // No default is the plugin declining to choose one; the kind decides what
        // an absent value means, and `sanitized()` fills it in.
        value = (try? container.decodeIfPresent(PluginValue.self, forKey: .value)) ?? .bool(false)
    }

    public static let maximumOptions = 16

    /// Nil when the row could not be rendered honestly — an unusable key or label,
    /// a default that disagrees with the kind, or a choice with nothing to choose.
    public func sanitized() -> PluginSetting? {
        guard PluginManifest.isSafeKey(key), let label = PluginManifest.text(label)
        else { return nil }
        let options = options
            .compactMap { PluginManifest.text($0, limit: 40) }
            .prefix(Self.maximumOptions)
        guard kind != .choice || !options.isEmpty else { return nil }
        // A `choice` defaulting to something outside its own options would show an
        // empty picker; falling back to the first option is the only honest answer.
        let value = resolvedValue(options: Array(options))
        return PluginSetting(
            key: key,
            kind: kind,
            label: label,
            detail: detail.flatMap { PluginManifest.text($0, limit: 160) },
            options: Array(options),
            value: value
        )
    }

    /// Whether a value the plugin — or utt's own stored file — offers can be shown
    /// in this control at all.
    public func accepts(_ candidate: PluginValue) -> Bool {
        switch (kind, candidate) {
        case (.bool, .bool), (.string, .string), (.number, .number): true
        case let (.choice, .string(text)): options.contains(text)
        default: false
        }
    }

    private func resolvedValue(options: [String]) -> PluginValue {
        switch (kind, value) {
        case (.bool, .bool), (.string, .string), (.number, .number): value
        case let (.choice, .string(text)) where options.contains(text): value
        case (.bool, _): .bool(false)
        case (.string, _): .string("")
        case (.number, _): .number(0)
        case (.choice, _): .string(options[0])
        }
    }
}

/// A settings value, carried as the JSON scalar it is — `true`, `"text"`, `3` —
/// so a plugin reads its own values file without knowing anything about utt.
public enum PluginValue: Codable, Hashable, Sendable {
    case bool(Bool)
    case string(String)
    case number(Double)

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Bool before Double: JSON `true` decodes as a number in some encoders, and
        // a boolean setting arriving as 1 would render a text field.
        if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a bool, number or string")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(flag): try container.encode(flag)
        case let .string(text): try container.encode(text)
        case let .number(number): try container.encode(number)
        }
    }
}
