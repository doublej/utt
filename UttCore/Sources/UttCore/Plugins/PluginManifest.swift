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
    /// The plugin sends audio to be transcribed, by dropping a file in its own jobs
    /// directory. utt writes the text back beside it. This is the direct lane: no
    /// listener, no token, and nothing on the network.
    public var sendsAudio = false
    /// The plugin's own colour, `#RGB` or `#RRGGBB`. utt lights the menu bar mark
    /// in it while transcribing that plugin's audio, so a clip arriving from
    /// somewhere else is visibly not utt's own dictation.
    public var tint: String?

    public init(
        id: String, name: String, blurb: String? = nil,
        systemImage: String? = nil, settings: [PluginSetting] = [],
        needsApi: Bool = false, wantsTranscripts: Bool = false, sendsAudio: Bool = false,
        tint: String? = nil
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.systemImage = systemImage
        self.settings = settings
        self.needsApi = needsApi
        self.wantsTranscripts = wantsTranscripts
        self.sendsAudio = sendsAudio
        self.tint = tint
    }

    enum CodingKeys: String, CodingKey {
        case id, name, blurb, systemImage, settings
        case needsApi, wantsTranscripts, sendsAudio, tint
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
        sendsAudio = (try? container.decodeIfPresent(Bool.self, forKey: .sendsAudio)) as? Bool ?? false
        tint = try? container.decodeIfPresent(String.self, forKey: .tint)
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
            wantsTranscripts: wantsTranscripts,
            sendsAudio: sendsAudio,
            // Dropped rather than corrected: a colour utt cannot read is one the
            // plugin did not mean, and guessing at it would light the menu bar in
            // something nobody chose.
            tint: tint.flatMap { Self.rgb(from: $0) == nil ? nil : $0 }
        )
    }

    /// The tint as three 0...1 components, or nil when it is not a colour.
    ///
    /// Kept here rather than in the view layer because it is a plugin-supplied
    /// string, which makes it the same kind of thing as every other field on this
    /// type: parsed strictly, refused rather than repaired.
    public var rgb: PluginRGB? { tint.flatMap { Self.rgb(from: $0) } }

    /// `#RGB` or `#RRGGBB`, with or without the hash. Anything else is not a colour.
    static func rgb(from hex: String) -> PluginRGB? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let pairs: [String]
        switch digits.count {
        // #RGB is shorthand for #RRGGBB — "f0a" is "ff00aa", not "0f0a00".
        case 3: pairs = digits.map { "\($0)\($0)" }
        case 6: pairs = stride(from: 0, to: 6, by: 2).map {
            String(digits[digits.index(digits.startIndex, offsetBy: $0)...].prefix(2))
        }
        default: return nil
        }
        let values = pairs.compactMap { UInt8($0, radix: 16).map { Double($0) / 255 } }
        guard values.count == 3 else { return nil }
        return PluginRGB(red: values[0], green: values[1], blue: values[2])
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
