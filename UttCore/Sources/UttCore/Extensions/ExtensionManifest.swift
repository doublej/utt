import Foundation

/// What an extension says it is, and which settings it wants utt to show for it.
///
/// A manifest is a file in `extensions/` that *another process wrote*, so it is read
/// the way the API reads a request: nothing is trusted, and anything unusable is
/// dropped rather than repaired. `sanitized()` is the whole trust boundary —
/// `id` names a file utt will later write, so an id carrying `/` or `..` is a
/// path traversal, and an unbounded settings array is a rail nobody can scroll.
public struct ExtensionManifest: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// One line under the page title.
    public var blurb: String?
    /// A short paragraph for the About section of the page.
    public var description: String?
    /// Where the code lives. `https://` only, dropped otherwise — a link on the
    /// page is a link the person will click.
    public var repository: String?
    /// The extension's own site. Same rule as `repository`.
    public var website: String?
    /// SF Symbol. Dropped when it is not one — `Image(systemName:)` draws nothing
    /// for a name that does not exist, which reads as a broken page.
    public var systemImage: String?
    public var settings: [ExtensionSetting] = []
    /// The extension says it calls utt's own HTTP API, and wants the bearer token
    /// handed to it rather than read out of utt's settings file behind its back.
    /// Honoured only while the API is actually enabled — see `ExtensionValuesFile`.
    public var needsApi = false
    /// The extension wants every transcript utt produces, written to
    /// `<id>.transcript.json` as each one finishes. This hands a local program
    /// everything dictated on this Mac, so the extension's page says so plainly.
    public var wantsTranscripts = false
    /// The extension sends audio to be transcribed, by dropping a file in its own jobs
    /// directory. utt writes the text back beside it. This is the direct lane: no
    /// listener, no token, and nothing on the network.
    public var sendsAudio = false
    /// The extension wants the words as they are decoded, while the person is still
    /// speaking, written to `<id>.partial.json`. Provisional text from a smaller
    /// recogniser: it is revised as it grows, it is thrown away when the real
    /// transcript lands, and it only exists while the person has Live words on.
    public var wantsPartials = false
    /// The extension sees every transcript before it lands and may hand back other
    /// text — a rewrite, a translation, a template filled in. utt writes the
    /// question into `<id>.filter/` and waits briefly for the answer beside it.
    /// This puts the extension on the path between the key coming up and the text
    /// appearing, so a slow or stopped extension costs a pause and then nothing.
    public var filtersTranscripts = false
    /// Stages of utt's text pipeline this extension's own transcriptions skip.
    ///
    /// Only the clips the extension sends itself — never what the person dictates.
    /// The pipeline is tuned for a human writing prose at a cursor, and an extension
    /// asking for a transcription often wants something else: a terminal wants the
    /// replacement rules but not a lowercased line, a note-taker wants the words
    /// exactly as spoken. Naming a stage here is the extension saying so instead of
    /// undoing utt's work afterwards and getting it subtly wrong.
    ///
    /// Unknown names are dropped rather than rejected, so an extension written against
    /// a later utt still loads on this one.
    public var skipsTextStages: Set<TextStage> = []
    /// The extension's own colour, `#RGB` or `#RRGGBB`. utt lights the menu bar mark
    /// in it while transcribing that extension's audio, so a clip arriving from
    /// somewhere else is visibly not utt's own dictation.
    public var tint: String?
    /// Give the extension a menu bar item of its own, beside utt's. It carries the
    /// extension's symbol and colour, and a menu built from what the extension already
    /// declares — its status lines, its buttons, its daemon.
    public var showsInMenuBar = false
    /// Buttons on the extension's page. Pressing one writes a request the extension picks
    /// up — utt never runs anything itself.
    public var actions: [ExtensionAction] = []
    /// A launchd job utt may report on. Its state is read live, so a daemon that
    /// died still reads as stopped however cheerful its own status file is.
    public var daemon: ExtensionDaemon?

    public init(
        id: String, name: String, blurb: String? = nil,
        description: String? = nil, repository: String? = nil, website: String? = nil,
        systemImage: String? = nil, settings: [ExtensionSetting] = [],
        needsApi: Bool = false, wantsTranscripts: Bool = false, sendsAudio: Bool = false,
        wantsPartials: Bool = false, filtersTranscripts: Bool = false, skipsTextStages: Set<TextStage> = [],
        tint: String? = nil, actions: [ExtensionAction] = [], daemon: ExtensionDaemon? = nil,
        showsInMenuBar: Bool = false
    ) {
        self.id = id
        self.name = name
        self.blurb = blurb
        self.description = description
        self.repository = repository
        self.website = website
        self.systemImage = systemImage
        self.settings = settings
        self.needsApi = needsApi
        self.wantsTranscripts = wantsTranscripts
        self.sendsAudio = sendsAudio
        self.wantsPartials = wantsPartials
        self.filtersTranscripts = filtersTranscripts
        self.skipsTextStages = skipsTextStages
        self.tint = tint
        self.actions = actions
        self.daemon = daemon
        self.showsInMenuBar = showsInMenuBar
    }

    enum CodingKeys: String, CodingKey {
        case id, name, blurb, description, repository, website, systemImage, settings
        case needsApi, wantsTranscripts, sendsAudio, wantsPartials, filtersTranscripts, skipsTextStages
        case tint, actions, daemon
        case showsInMenuBar
    }

    /// Forgiving, like `UttSettings`: an extension writing only the keys it cares about
    /// must not have its whole manifest rejected. Swift's synthesized decoder
    /// ignores property defaults and demands every key, which would make `settings`
    /// and `needsApi` mandatory for no reason.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        blurb = try? container.decodeIfPresent(String.self, forKey: .blurb)
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        repository = try? container.decodeIfPresent(String.self, forKey: .repository)
        website = try? container.decodeIfPresent(String.self, forKey: .website)
        systemImage = try? container.decodeIfPresent(String.self, forKey: .systemImage)
        settings = (try? container.decodeIfPresent([ExtensionSetting].self, forKey: .settings)) as? [ExtensionSetting] ?? []
        needsApi = (try? container.decodeIfPresent(Bool.self, forKey: .needsApi)) as? Bool ?? false
        wantsTranscripts = (try? container.decodeIfPresent(Bool.self, forKey: .wantsTranscripts)) as? Bool ?? false
        sendsAudio = (try? container.decodeIfPresent(Bool.self, forKey: .sendsAudio)) as? Bool ?? false
        wantsPartials = (try? container.decodeIfPresent(Bool.self, forKey: .wantsPartials)) as? Bool ?? false
        filtersTranscripts = (try? container.decodeIfPresent(Bool.self, forKey: .filtersTranscripts)) ?? false
        // Decoded as strings, not as the enum: `Set<TextStage>` throws on the first
        // name it does not know, and `try?` around that would drop every stage the
        // extension *did* spell right along with the typo.
        let stageNames = (try? container.decode([String].self, forKey: .skipsTextStages)) ?? []
        skipsTextStages = Set(stageNames.compactMap(TextStage.init(rawValue:)))
        tint = try? container.decodeIfPresent(String.self, forKey: .tint)
        actions = (try? container.decodeIfPresent([ExtensionAction].self, forKey: .actions)) as? [ExtensionAction] ?? []
        daemon = try? container.decodeIfPresent(ExtensionDaemon.self, forKey: .daemon)
        showsInMenuBar = (try? container.decodeIfPresent(Bool.self, forKey: .showsInMenuBar)) ?? false
    }

    /// At most this many rows on an extension's page. An extension asking for more has a
    /// configuration file of its own to write, not a settings page.
    public static let maximumSettings = 24
    /// A page is not a control panel. An extension wanting more buttons than this has a
    /// window of its own to build.
    public static let maximumActions = 8

    /// The manifest utt will actually render, or nil when it cannot be trusted.
    public func sanitized() -> ExtensionManifest? {
        guard Self.isSafeIdentifier(id), let name = Self.text(name) else { return nil }
        var seen = Set<String>()
        var seenActions = Set<String>()
        let actionsSeen = actions
            .compactMap { $0.sanitized() }
            .filter { seenActions.insert($0.key).inserted }
            .prefix(Self.maximumActions)
        let settings = settings
            .compactMap { $0.sanitized() }
            // A duplicate key would give two rows one value: the second row would
            // silently overwrite the first on every edit.
            .filter { seen.insert($0.key).inserted }
            .prefix(Self.maximumSettings)
        return ExtensionManifest(
            id: id,
            name: name,
            blurb: blurb.flatMap { Self.text($0, limit: 120) },
            description: description.flatMap { Self.text($0, limit: 400) },
            repository: repository.flatMap { Self.link($0) },
            website: website.flatMap { Self.link($0) },
            systemImage: systemImage.flatMap { Self.isSafeSymbol($0) ? $0 : nil },
            settings: Array(settings),
            needsApi: needsApi,
            wantsTranscripts: wantsTranscripts,
            sendsAudio: sendsAudio,
            wantsPartials: wantsPartials,
            filtersTranscripts: filtersTranscripts,
            skipsTextStages: skipsTextStages,
            // Dropped rather than corrected: a colour utt cannot read is one the
            // extension did not mean, and guessing at it would light the menu bar in
            // something nobody chose.
            tint: tint.flatMap { Self.rgb(from: $0) == nil ? nil : $0 },
            actions: Array(actionsSeen),
            daemon: daemon.flatMap { $0.isUsable ? $0 : nil },
            showsInMenuBar: showsInMenuBar
        )
    }

    /// The tint as three 0...1 components, or nil when it is not a colour.
    ///
    /// Kept here rather than in the view layer because it is an extension-supplied
    /// string, which makes it the same kind of thing as every other field on this
    /// type: parsed strictly, refused rather than repaired.
    public var rgb: ExtensionRGB? { tint.flatMap { Self.rgb(from: $0) } }

    /// `#RGB` or `#RRGGBB`, with or without the hash. Anything else is not a colour.
    static func rgb(from hex: String) -> ExtensionRGB? {
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
        return ExtensionRGB(red: values[0], green: values[1], blue: values[2])
    }

    /// The settings this manifest asks for, with the stored choices applied.
    ///
    /// A stored value the control cannot show falls back to the manifest's own
    /// default — which is what an extension shipping a new schema over an old values
    /// file produces, and the alternative is a picker with nothing selected.
    public func resolved(stored: [String: ExtensionValue]) -> [ExtensionSetting] {
        settings.map { setting in
            guard let value = stored[setting.key], setting.accepts(value) else { return setting }
            var setting = setting
            setting.value = value
            return setting
        }
    }

    /// A setting or action key. Unlike an id it never becomes a filename, so case
    /// is free — and it has to be, because an extension naturally writes `openLog` and
    /// `lastRelay`. Holding keys to the id's lowercase rule silently dropped every
    /// camelCase one, which is an extension arriving with half its buttons missing.
    public static func isSafeKey(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 64
            && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// Lowercase, and no path separators: this becomes `extensions/<id>.values.json`,
    /// and a case-insensitive filesystem would let `Deckhand` and `deckhand` fight
    /// over the same file.
    public static func isSafeIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || "._-".contains($0)) }
            && id.first != "." // no dotfiles, and no "." or ".." at all
    }

    /// Everything utt writes or makes for an extension, by the part after `<id>.`.
    /// A fixed list rather than a prefix match: ids may contain dots, so
    /// `deck.` as a prefix would claim `deck.hand.json` for an extension called `deck`.
    /// `disabled` is the marker consent replaced. It stays on the list because
    /// removing an extension has to take the old one away too — a stale marker left
    /// behind would switch off the next install of the same id.
    public static let ownedSuffixes: Set<String> = [
        "json", "values.json", "status.json", "action.json", "transcript.json",
        "consent.json", "jobs", "filter", "disabled"
    ]

    /// Whether a name in the extensions directory belongs to this extension.
    public static func file(_ name: String, belongsTo id: String) -> Bool {
        guard name.hasPrefix("\(id).") else { return false }
        return ownedSuffixes.contains(String(name.dropFirst(id.count + 1)))
    }

    /// A link the page may show: `https://` with a host, and nothing else. `http`
    /// is not merely weaker — a page that opens a plain link is a page that sends
    /// the person somewhere a network can rewrite.
    public static func link(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty
        else { return nil }
        return trimmed
    }

    public var repositoryURL: URL? { repository.flatMap { URL(string: $0) } }
    public var websiteURL: URL? { website.flatMap { URL(string: $0) } }

    /// SF Symbol names are dot-separated ASCII words; anything else is not a symbol
    /// and would draw an empty square.
    public static func isSafeSymbol(_ symbol: String) -> Bool {
        !symbol.isEmpty && symbol.count <= 64
            && symbol.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-".contains($0)) }
    }

    /// Trimmed, single-line and bounded. A newline in a label breaks the row it sits
    /// in, and nothing stops an extension from sending one.
    public static func text(_ value: String, limit: Int = 80) -> String? {
        let flattened = value.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(limit))
    }
}
