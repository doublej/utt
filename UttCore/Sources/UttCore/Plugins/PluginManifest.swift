import Foundation

/// What a plugin says it is, and which settings it wants utt to show for it.
///
/// A manifest is a file in `plugins/` that *another process wrote*, so it is read
/// the way the API reads a request: nothing is trusted, and anything unusable is
/// dropped rather than repaired. `sanitized()` is the whole trust boundary —
/// `id` names a file utt will later write, so an id carrying `/` or `..` is a
/// path traversal, and an unbounded settings array is a rail nobody can scroll.
public struct PluginManifest: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// One line under the page title.
    public var blurb: String?
    /// SF Symbol. Dropped when it is not one — `Image(systemName:)` draws nothing
    /// for a name that does not exist, which reads as a broken page.
    public var systemImage: String?
    public var settings: [PluginSetting] = []
    /// The plugin says it calls utt's own HTTP API, and wants the bearer token
    /// handed to it rather than read out of utt's settings file behind its back.
    /// Honoured only while the API is actually enabled — see `PluginValuesFile`.
    public var needsApi = false
    /// The plugin wants every transcript utt produces, written to
    /// `<id>.transcript.json` as each one finishes. This hands a local program
    /// everything dictated on this Mac, so the plugin's page says so plainly.
    public var wantsTranscripts = false

    public init(
        id: String, name: String, blurb: String? = nil,
        systemImage: String? = nil, settings: [PluginSetting] = [],
        needsApi: Bool = false, wantsTranscripts: Bool = false
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.systemImage = systemImage
        self.settings = settings
        self.needsApi = needsApi
        self.wantsTranscripts = wantsTranscripts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, blurb, systemImage, settings, needsApi, wantsTranscripts
    }

    /// Forgiving, like `UttSettings`: a plugin writing only the keys it cares about
    /// must not have its whole manifest rejected. Swift's synthesized decoder
    /// ignores property defaults and demands every key, which would make `settings`
    /// and `needsApi` mandatory for no reason.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        blurb = try? container.decodeIfPresent(String.self, forKey: .blurb)
        systemImage = try? container.decodeIfPresent(String.self, forKey: .systemImage)
        settings = (try? container.decodeIfPresent([PluginSetting].self, forKey: .settings)) as? [PluginSetting] ?? []
        needsApi = (try? container.decodeIfPresent(Bool.self, forKey: .needsApi)) as? Bool ?? false
        wantsTranscripts = (try? container.decodeIfPresent(Bool.self, forKey: .wantsTranscripts)) as? Bool ?? false
    }

    /// At most this many rows on a plugin's page. A plugin asking for more has a
    /// configuration file of its own to write, not a settings page.
    public static let maximumSettings = 24

    /// The manifest utt will actually render, or nil when it cannot be trusted.
    public func sanitized() -> PluginManifest? {
        guard Self.isSafeIdentifier(id), let name = Self.text(name) else { return nil }
        var seen = Set<String>()
        let settings = settings
            .compactMap { $0.sanitized() }
            // A duplicate key would give two rows one value: the second row would
            // silently overwrite the first on every edit.
            .filter { seen.insert($0.key).inserted }
            .prefix(Self.maximumSettings)
        return PluginManifest(
            id: id,
            name: name,
            blurb: blurb.flatMap { Self.text($0, limit: 120) },
            systemImage: systemImage.flatMap { Self.isSafeSymbol($0) ? $0 : nil },
            settings: Array(settings),
            needsApi: needsApi,
            wantsTranscripts: wantsTranscripts
        )
    }

    /// The settings this manifest asks for, with the stored choices applied.
    ///
    /// A stored value the control cannot show falls back to the manifest's own
    /// default — which is what a plugin shipping a new schema over an old values
    /// file produces, and the alternative is a picker with nothing selected.
    public func resolved(stored: [String: PluginValue]) -> [PluginSetting] {
        settings.map { setting in
            guard let value = stored[setting.key], setting.accepts(value) else { return setting }
            var setting = setting
            setting.value = value
            return setting
        }
    }

    /// Lowercase, and no path separators: this becomes `plugins/<id>.values.json`.
    public static func isSafeIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "._-".contains($0)) }
            && id.first != "." // no dotfiles, and no "." or ".." at all
    }

    /// SF Symbol names are dot-separated ASCII words; anything else is not a symbol
    /// and would draw an empty square.
    public static func isSafeSymbol(_ symbol: String) -> Bool {
        !symbol.isEmpty && symbol.count <= 64
            && symbol.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }
    }

    /// Trimmed, single-line and bounded. A newline in a label breaks the row it sits
    /// in, and nothing stops a plugin from sending one.
    public static func text(_ value: String, limit: Int = 80) -> String? {
        let flattened = value.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
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
        options = (try? container.decodeIfPresent([String].self, forKey: .options)) as? [String] ?? []
        // No default is the plugin declining to choose one; the kind decides what
        // an absent value means, and `sanitized()` fills it in.
        value = (try? container.decodeIfPresent(PluginValue.self, forKey: .value)) as? PluginValue ?? .bool(false)
    }

    public static let maximumOptions = 16

    /// Nil when the row could not be rendered honestly — an unusable key or label,
    /// a default that disagrees with the kind, or a choice with nothing to choose.
    public func sanitized() -> PluginSetting? {
        guard PluginManifest.isSafeIdentifier(key), let label = PluginManifest.text(label)
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
