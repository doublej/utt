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

    // MARK: - Recording

    /// Dictation itself. Off runs utt unarmed: the hotkey starts nothing, nothing
    /// suppresses it, and the microphone is never opened — while the API,
    /// extension jobs and the paste-last shortcut go on working. utt is a backend
    /// for other tools as much as something to talk to, and the microphone is the
    /// one part of it that should not be open when nobody is dictating.
    public var dictationEnabled: Bool = true

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

    /// Input device unique IDs, best first. Capture takes the first one that is
    /// actually plugged in, so "AirPods, else the Yeti, else whatever" is one
    /// list rather than a choice the user has to redo every time. Empty follows
    /// the system default input, which is also the fallback when none of the
    /// listed devices is present.
    public var microphonePriority: [String] = []

    /// Names for the UIDs in `microphonePriority`, so a device that is not plugged
    /// in can still be read as "RØDE NT-USB" rather than a bare CoreAudio UID. Only
    /// the machine the device is attached to can supply the name, which is exactly
    /// the machine that cannot supply it when it matters — hence remembering it.
    /// Kept in step with the list by `SettingsFeature`; a missing entry is only a
    /// worse label, never a worse device choice.
    public var microphoneNames: [String: String] = [:]

    /// How each remembered microphone was last attached — USB, Continuity over
    /// Wi-Fi, the headphone jack. Same bargain as the names above: only the machine
    /// the device is plugged into can say, and that is never the moment you want to
    /// know. A `DeviceSource` raw value, or absent for a device seen before this
    /// was recorded.
    public var microphoneSources: [String: String] = [:]

    /// Mute system output while recording so podcast audio doesn't bleed into
    /// the mic. Off: muting other people's audio is a big thing to do quietly.
    public var muteWhileRecording: Bool = false

    /// Hold a power assertion while recording so the Mac cannot sleep mid-sentence.
    public var preventSystemSleep: Bool = true

    /// Keep the microphone pipeline open through idle/sleep/lock instead of
    /// suspending on IdleObserver events. Off by default — leaving the mic open
    /// keeps the system indicator lit indefinitely.
    public var keepMicrophoneWarm: Bool = false

    /// Draw the dot-matrix indicator in the middle of the screen while recording.
    /// On by default: it is the only feedback there is when the window is closed.
    /// Off leaves the panel in place drawing nothing, which is what it already does
    /// between recordings — the alternative, tearing the window down, would cost a
    /// relaunch to get it back.
    public var showRecordingOverlay: Bool = true

    // MARK: - Transcription

    /// Which engine runs. Parakeet is faster and better on English; Whisper is
    /// the fallback for what Parakeet cannot load or cannot hear.
    public var transcriptionEngine: TranscriptionEngine = .parakeet

    /// Which model that engine runs, by the engine's own identifier. Read through
    /// `ModelCatalog.resolve(id:engine:)`, never directly: the stored id can name a
    /// model from an older build or from the *other* engine, and the resolver falls
    /// back to that engine's recommended model instead of failing to transcribe.
    public var selectedModel: String = ModelCatalog.preferred(for: .parakeet).id

    // MARK: - Output

    /// Paste through the clipboard (one keystroke, restores the previous
    /// contents) instead of synthesising the transcript keystroke by keystroke.
    /// Clipboard is faster and survives long transcripts; synthesised typing is
    /// the fallback for apps that refuse programmatic pastes.
    public var useClipboardPaste: Bool = true

    /// Leave the transcript on the clipboard afterwards rather than restoring
    /// what was there before.
    public var copyToClipboard: Bool = false

    /// Paste straight away, or hold the transcript until the user confirms.
    /// `.immediate` is the default: review is a deliberate slow-down, and an app
    /// that asks before every paste is an app that gets uninstalled by lunchtime.
    public var deliveryMode: DeliveryMode = .immediate

    /// Show the floating transcript panel. Forced on in `.review` mode — a review
    /// with no panel is a transcript that silently never arrives.
    public var showTranscriptHUD: Bool = true

    /// Seconds the post-delivery card stays on screen. `0` keeps it up until it is
    /// dismissed by hand.
    public var hudDismissAfter: Double = 6

    /// Words on the panel while the key is still held, from a second, smaller
    /// recogniser. Off: English only, its own download, and always provisional.
    public var liveWords: Bool = false

    // MARK: - Text pipeline

    /// Literal find-and-replace rules, applied in order before the formatting
    /// toggles. A rule with an empty replacement deletes its match. Empty by
    /// default: rules are personal vocabulary, nobody else's guess, and
    /// `RulePresets` seeds them on request.
    public var wordRemappings: [WordRemapping] = []

    /// Run the transcript past the on-device language model to take out filler
    /// words, false starts and mid-sentence self-corrections. Off by default: it
    /// costs about a second a paragraph, and the model's own content check fires
    /// on ordinary sentences, so it cannot be promised.
    public var cleanupTranscripts: Bool = false

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

    /// The local transcription API — off, and loopback-only when switched on.
    /// See `ApiSettings`; nested so the whole feature is one object in the file.
    public var api = ApiSettings()

    /// The first-run walkthrough has been seen through, or deliberately skipped.
    /// The *only* thing that decides whether it opens again, which is what makes
    /// setting it back to `false` — by hand in this file, or with the button in
    /// General — replay the flow without deleting everything else in here.
    public var hasCompletedOnboarding: Bool = false

    /// All defaults. Mutate the properties you want to change — every one is
    /// `public var`, which is why there is no 20-parameter memberwise init.
    public init() {}
}
