import Foundation

/// Everything the user can configure, persisted as JSON at `URL.uttSettingsFile`.
///
/// Decoding is deliberately forgiving: every key falls back to its default, so
/// `{}`, a file from an older build, or a file with one hand-edited key all
/// decode to something usable instead of throwing and losing the rest.
/// New keys therefore need no migration — add the property with a default.
public struct UttSettings: Codable, Equatable, Sendable {
    /// ctrl+globe — what uttertype shipped with, and what these fingers know.
    /// `key == nil` means modifier-only: press-and-hold, no character key.
    public static let defaultHotkey = HotKey(key: nil, modifiers: [.control, .fn])

    /// Filler sounds worth deleting, as regex fragments. Shipped but disabled:
    /// silently deleting words from a transcript is alarming when unasked for.
    public static let defaultWordRemovals: [WordRemoval] = [
        .init(pattern: "uh+"),
        .init(pattern: "um+"),
        .init(pattern: "er+"),
        .init(pattern: "hm+")
    ]

    // MARK: - Recording

    /// Push-to-talk combination.
    public var hotkey: HotKey = UttSettings.defaultHotkey

    /// Shortest hold, in seconds, that counts as a deliberate press. Shorter
    /// presses are discarded as a slip. Modifier-only hotkeys additionally
    /// obey `UttCoreConstants.modifierOnlyMinimumDuration`, whichever is longer.
    public var minimumKeyTime: Double = UttCoreConstants.defaultMinimumKeyTime

    /// Double-tap latches recording on until the next tap, instead of requiring
    /// the hotkey to be held for the whole sentence.
    public var doubleTapLockEnabled: Bool = true

    /// Only a double-tap starts recording; a plain hold does nothing. For people
    /// whose hotkey collides with something they hold for other reasons.
    /// Meaningless without `doubleTapLockEnabled`, and normalised off with it.
    public var useDoubleTapOnly: Bool = false

    /// Keep a rolling capture buffer running so the audio from just before the
    /// keypress is included — the first syllable is otherwise routinely clipped.
    public var preRollEnabled: Bool = true

    /// Input device unique ID. `nil` follows the system default input, which is
    /// what most people want when they plug in a headset mid-session.
    public var selectedMicrophoneID: String?

    /// Mute system output while recording so podcast audio doesn't bleed into
    /// the mic. Off: muting other people's audio is a big thing to do quietly.
    public var muteWhileRecording: Bool = false

    /// Hold a power assertion while recording so the Mac cannot sleep mid-sentence.
    public var preventSystemSleep: Bool = true

    /// Keep the microphone pipeline open through idle/sleep/lock instead of
    /// suspending on IdleObserver events. Off by default — leaving the mic open
    /// keeps the system indicator lit indefinitely.
    public var keepMicrophoneWarm: Bool = false

    // MARK: - Transcription

    /// Which engine runs. Parakeet is faster and better on English; Whisper is
    /// the fallback for what Parakeet cannot load or cannot hear.
    public var transcriptionEngine: TranscriptionEngine = .parakeet

    /// Transcription model, by on-disk bundle name. Multilingual by default —
    /// the English-only bundle is a deliberate downgrade, not a starting point.
    /// Interpreted by whichever engine `transcriptionEngine` names.
    public var selectedModel: String = ParakeetModel.multilingualV3.identifier

    // MARK: - Output

    /// Paste through the clipboard (one keystroke, restores the previous
    /// contents) instead of synthesising the transcript keystroke by keystroke.
    /// Clipboard is faster and survives long transcripts; synthesised typing is
    /// the fallback for apps that refuse programmatic pastes.
    public var useClipboardPaste: Bool = true

    /// Leave the transcript on the clipboard afterwards rather than restoring
    /// what was there before.
    public var copyToClipboard: Bool = false

    // MARK: - Text pipeline

    /// Master switch for `wordRemovals`. Off by default — see `defaultWordRemovals`.
    public var wordRemovalsEnabled: Bool = false

    /// Filler patterns deleted from the transcript when `wordRemovalsEnabled`.
    public var wordRemovals: [WordRemoval] = UttSettings.defaultWordRemovals

    /// Literal find-and-replace rules, applied before the formatting toggles.
    /// Empty by default: these are personal vocabulary, nobody else's guess.
    public var wordRemappings: [WordRemapping] = []

    /// Lowercase the whole transcript.
    public var lowercaseTranscripts: Bool = false

    /// Strip every punctuation character from the transcript.
    public var removePunctuation: Bool = false

    // MARK: - History

    /// Keep transcripts on disk so they can be re-pasted or recovered.
    public var saveTranscriptionHistory: Bool = true

    /// Cap on retained transcripts; `nil` keeps everything. Transcripts are text
    /// — the audio is what costs disk — so unlimited is a defensible default.
    public var maxHistoryEntries: Int?

    // MARK: - App

    /// Start/stop chimes.
    public var soundEffectsEnabled: Bool = true

    /// Multiplier on `UttCoreConstants.baseSoundEffectsVolume`, 0...1.
    public var soundEffectsVolume: Double = UttCoreConstants.baseSoundEffectsVolume

    /// Launch at login. Off — an app installs itself into your startup only
    /// when asked.
    public var openOnLogin: Bool = false

    /// Show the Dock icon. On, because a hidden app with a global hotkey and a
    /// microphone should be findable.
    public var showDockIcon: Bool = true

    /// All defaults. Mutate the properties you want to change — every one is
    /// `public var`, which is why there is no 20-parameter memberwise init.
    public init() {}

    /// Decodes key by key, each falling back to its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decodeRecording(from: container)
        try decodeModelAndOutput(from: container)
        try decodeTextPipeline(from: container)
        try decodeApp(from: container)
        normalizeDoubleTapSettings()
    }

    /// The on-disk key names. Spelled out rather than synthesised so renaming a
    /// property does not silently orphan everyone's saved value.
    private enum CodingKeys: String, CodingKey {
        case hotkey
        case minimumKeyTime
        case doubleTapLockEnabled
        case useDoubleTapOnly
        case preRollEnabled
        case selectedMicrophoneID
        case muteWhileRecording
        case preventSystemSleep
        case keepMicrophoneWarm
        case transcriptionEngine
        case selectedModel
        case useClipboardPaste
        case copyToClipboard
        case wordRemovalsEnabled
        case wordRemovals
        case wordRemappings
        case lowercaseTranscripts
        case removePunctuation
        case saveTranscriptionHistory
        case maxHistoryEntries
        case soundEffectsEnabled
        case soundEffectsVolume
        case openOnLogin
        case showDockIcon
    }

    // Decoding is split by section only to keep each function body short.

    private mutating func decodeRecording(from container: KeyedDecodingContainer<CodingKeys>) throws {
        hotkey = try container.decodeIfPresent(HotKey.self, forKey: .hotkey) ?? hotkey
        minimumKeyTime = try container.decodeIfPresent(Double.self, forKey: .minimumKeyTime) ?? minimumKeyTime
        doubleTapLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .doubleTapLockEnabled) ?? doubleTapLockEnabled
        useDoubleTapOnly = try container.decodeIfPresent(Bool.self, forKey: .useDoubleTapOnly) ?? useDoubleTapOnly
        preRollEnabled = try container.decodeIfPresent(Bool.self, forKey: .preRollEnabled) ?? preRollEnabled
        selectedMicrophoneID = try container.decodeIfPresent(String.self, forKey: .selectedMicrophoneID) ?? selectedMicrophoneID
        muteWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .muteWhileRecording) ?? muteWhileRecording
        preventSystemSleep = try container.decodeIfPresent(Bool.self, forKey: .preventSystemSleep) ?? preventSystemSleep
        keepMicrophoneWarm = try container.decodeIfPresent(Bool.self, forKey: .keepMicrophoneWarm) ?? keepMicrophoneWarm
    }

    private mutating func decodeModelAndOutput(from container: KeyedDecodingContainer<CodingKeys>) throws {
        transcriptionEngine = try container.decodeIfPresent(TranscriptionEngine.self, forKey: .transcriptionEngine) ?? transcriptionEngine
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? selectedModel
        useClipboardPaste = try container.decodeIfPresent(Bool.self, forKey: .useClipboardPaste) ?? useClipboardPaste
        copyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? copyToClipboard
    }

    private mutating func decodeTextPipeline(from container: KeyedDecodingContainer<CodingKeys>) throws {
        wordRemovalsEnabled = try container.decodeIfPresent(Bool.self, forKey: .wordRemovalsEnabled) ?? wordRemovalsEnabled
        wordRemovals = try container.decodeIfPresent([WordRemoval].self, forKey: .wordRemovals) ?? wordRemovals
        wordRemappings = try container.decodeIfPresent([WordRemapping].self, forKey: .wordRemappings) ?? wordRemappings
        lowercaseTranscripts = try container.decodeIfPresent(Bool.self, forKey: .lowercaseTranscripts) ?? lowercaseTranscripts
        removePunctuation = try container.decodeIfPresent(Bool.self, forKey: .removePunctuation) ?? removePunctuation
    }

    private mutating func decodeApp(from container: KeyedDecodingContainer<CodingKeys>) throws {
        saveTranscriptionHistory = try container.decodeIfPresent(Bool.self, forKey: .saveTranscriptionHistory) ?? saveTranscriptionHistory
        maxHistoryEntries = try container.decodeIfPresent(Int.self, forKey: .maxHistoryEntries) ?? maxHistoryEntries
        soundEffectsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled) ?? soundEffectsEnabled
        soundEffectsVolume = try container.decodeIfPresent(Double.self, forKey: .soundEffectsVolume) ?? soundEffectsVolume
        openOnLogin = try container.decodeIfPresent(Bool.self, forKey: .openOnLogin) ?? openOnLogin
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? showDockIcon
    }

    /// `useDoubleTapOnly` without the lock would mean "start on double-tap,
    /// never stop". Enforced on decode; the settings UI enforces it on edit.
    private mutating func normalizeDoubleTapSettings() {
        if !doubleTapLockEnabled {
            useDoubleTapOnly = false
        }
    }
}
