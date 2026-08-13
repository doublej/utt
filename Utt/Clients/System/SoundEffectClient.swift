import AppKit
import Dependencies
import DependenciesMacros
import Foundation

/// Start/stop/cancel chimes.
///
/// Uses the system sounds rather than shipping audio assets: they already match the
/// user's alert volume and appearance, and a dictation app announcing itself with a
/// custom jingle is exactly the kind of thing people turn off.
enum SoundEffect: String, CaseIterable, Sendable {
    case start
    case stop
    case cancel

    var systemSoundName: String {
        switch self {
        case .start: "Tink"
        case .stop: "Pop"
        case .cancel: "Funk"
        }
    }
}

@DependencyClient
struct SoundEffectClient: Sendable {
    var play: @Sendable (_ effect: SoundEffect, _ volume: Float) -> Void
}

extension SoundEffectClient: DependencyKey {
    static let liveValue = SoundEffectClient(
        play: { effect, volume in
            // NSSound is main-thread-only in practice, and a chime is not worth
            // blocking the reducer's caller on.
            Task { @MainActor in
                guard let sound = NSSound(named: effect.systemSoundName) else { return }
                sound.volume = max(0, min(1, volume))
                sound.play()
            }
        }
    )
}

extension DependencyValues {
    var soundEffects: SoundEffectClient {
        get { self[SoundEffectClient.self] }
        set { self[SoundEffectClient.self] = newValue }
    }
}
