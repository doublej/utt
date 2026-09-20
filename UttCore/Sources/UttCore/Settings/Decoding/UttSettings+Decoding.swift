import Foundation

/// The forgiving half of `UttSettings`: the key names on disk, and a decoder that
/// reads every one of them independently. Its own file — and its own directory,
/// since `Settings/` is full — because the property list next door is what a person
/// reads to find out what utt can do, and this is machinery nobody needs to read to
/// answer that.
///
/// Splitting it changes one thing: `CodingKeys` is internal rather than private, so
/// the synthesised `Encodable` conformance next door can still see it.
extension UttSettings {
    /// Decodes key by key, each falling back to its default.
    public init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try decodeRecording(from: container)
        try decodeModelAndOutput(from: container)
        try decodeTextPipeline(from: container)
        try decodeApp(from: container)
        try seedMicrophonePriority(from: decoder)
        try seedOnboardingCompletion(from: decoder)
        normalizeDoubleTapSettings()
        normalizeDelivery()
    }

    /// The single microphone `microphonePriority` replaced. Read from its own
    /// container so it stays out of `CodingKeys` — a case with no stored property
    /// behind it would take synthesised `Encodable` conformance down with it, and
    /// the key is only ever read.
    private enum LegacyKeys: String, CodingKey {
        case selectedMicrophoneID
    }

    private mutating func seedMicrophonePriority(from decoder: Decoder) throws {
        // Key *absence*, not an empty list: "" and [] both mean "system default",
        // and an explicit [] must not be quietly refilled from the legacy key.
        guard try !decoder.container(keyedBy: CodingKeys.self).contains(.microphonePriority),
              let uid = try decoder.container(keyedBy: LegacyKeys.self)
                  .decodeIfPresent(String.self, forKey: .selectedMicrophoneID)
        else { return }
        microphonePriority = [uid]
    }

    /// A file written before the walkthrough existed belongs to someone who has
    /// been using utt for months, so its absence means "already onboarded" rather
    /// than "never onboarded". Key *absence* is what says so: an explicit `false`
    /// is a deliberate reset and has to survive the launch that reads it, which is
    /// the only thing that makes the flag resettable without deleting the file.
    private mutating func seedOnboardingCompletion(from decoder: Decoder) throws {
        guard try !decoder.container(keyedBy: CodingKeys.self)
            .contains(.hasCompletedOnboarding)
        else { return }
        hasCompletedOnboarding = true
    }

    /// The on-disk key names. Spelled out rather than synthesised so renaming a
    /// property does not silently orphan everyone's saved value.
    /// Grouped by the sections above, so a new key is added next to the ones it
    /// belongs with rather than at the end of a list forty long.
    enum CodingKeys: String, CodingKey {
        case dictationEnabled
        case hotkey, minimumKeyTime, doubleTapLockEnabled, useDoubleTapOnly, preRollEnabled
        case microphonePriority, microphoneNames, microphoneSources
        case muteWhileRecording, preventSystemSleep, keepMicrophoneWarm, showRecordingOverlay
        case transcriptionEngine, selectedModel
        case useClipboardPaste, copyToClipboard, deliveryMode, showTranscriptHUD, hudDismissAfter, liveWords
        case wordRemappings, cleanupTranscripts, lowercaseTranscripts, removePunctuation
        case saveTranscriptionHistory, maxHistoryEntries
        case soundEffectsEnabled, soundEffectsVolume
        case openOnLogin, showDockIcon, api, hasCompletedOnboarding
    }

    // Decoding is split by section only to keep each function body short.

    private mutating func decodeRecording(from container: KeyedDecodingContainer<CodingKeys>) throws {
        dictationEnabled = try container.decodeIfPresent(Bool.self, forKey: .dictationEnabled) ?? dictationEnabled
        hotkey = try container.decodeIfPresent(HotKey.self, forKey: .hotkey) ?? hotkey
        minimumKeyTime = try container.decodeIfPresent(Double.self, forKey: .minimumKeyTime) ?? minimumKeyTime
        doubleTapLockEnabled = try container.decodeIfPresent(Bool.self, forKey: .doubleTapLockEnabled) ?? doubleTapLockEnabled
        useDoubleTapOnly = try container.decodeIfPresent(Bool.self, forKey: .useDoubleTapOnly) ?? useDoubleTapOnly
        preRollEnabled = try container.decodeIfPresent(Bool.self, forKey: .preRollEnabled) ?? preRollEnabled
        microphonePriority = try container.decodeIfPresent([String].self, forKey: .microphonePriority) ?? microphonePriority
        microphoneNames = try container.decodeIfPresent([String: String].self, forKey: .microphoneNames) ?? microphoneNames
        microphoneSources = try container.decodeIfPresent([String: String].self, forKey: .microphoneSources) ?? microphoneSources
        muteWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .muteWhileRecording) ?? muteWhileRecording
        preventSystemSleep = try container.decodeIfPresent(Bool.self, forKey: .preventSystemSleep) ?? preventSystemSleep
        keepMicrophoneWarm = try container.decodeIfPresent(Bool.self, forKey: .keepMicrophoneWarm) ?? keepMicrophoneWarm
        showRecordingOverlay = try container.decodeIfPresent(Bool.self, forKey: .showRecordingOverlay) ?? showRecordingOverlay
    }

    private mutating func decodeModelAndOutput(from container: KeyedDecodingContainer<CodingKeys>) throws {
        transcriptionEngine = try container.decodeIfPresent(TranscriptionEngine.self, forKey: .transcriptionEngine) ?? transcriptionEngine
        selectedModel = try container.decodeIfPresent(String.self, forKey: .selectedModel) ?? selectedModel
        useClipboardPaste = try container.decodeIfPresent(Bool.self, forKey: .useClipboardPaste) ?? useClipboardPaste
        copyToClipboard = try container.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? copyToClipboard
        deliveryMode = try container.decodeIfPresent(DeliveryMode.self, forKey: .deliveryMode) ?? deliveryMode
        showTranscriptHUD = try container.decodeIfPresent(Bool.self, forKey: .showTranscriptHUD) ?? showTranscriptHUD
        liveWords = try container.decodeIfPresent(Bool.self, forKey: .liveWords) ?? liveWords
        hudDismissAfter = try container.decodeIfPresent(Double.self, forKey: .hudDismissAfter) ?? hudDismissAfter
    }

    private mutating func decodeTextPipeline(from container: KeyedDecodingContainer<CodingKeys>) throws {
        wordRemappings = try container.decodeIfPresent([WordRemapping].self, forKey: .wordRemappings) ?? wordRemappings
        cleanupTranscripts = try container.decodeIfPresent(Bool.self, forKey: .cleanupTranscripts) ?? cleanupTranscripts
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
        api = try container.decodeIfPresent(ApiSettings.self, forKey: .api) ?? api
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? hasCompletedOnboarding
    }

    /// `useDoubleTapOnly` without the lock would mean "start on double-tap,
    /// never stop". Enforced on decode; the settings UI enforces it on edit.
    private mutating func normalizeDoubleTapSettings() {
        if !doubleTapLockEnabled {
            useDoubleTapOnly = false
        }
    }

    /// Reviewing a transcript is gating a paste, so it means nothing when nothing
    /// is ever pasted — and a review panel whose ⏎ does not deliver is a trap.
    /// Enforced on decode; the settings UI disables the picker for the same reason.
    private mutating func normalizeDelivery() {
        if !useClipboardPaste {
            deliveryMode = .immediate
        }
    }
}
