import Foundation

/// Where an input device comes from.
///
/// Read off two CoreAudio properties: the transport type, plus — on the built-in
/// device only — the data source that separates the internal microphone from the
/// headphone jack. It exists to be *shown*. A list holding "MacBook Pro
/// Microphone", "BlackHole 2ch" and "Pocketline Swing Microphone" tells you
/// nothing about which one is the phone lying on the desk, and the phone is the
/// one that stops working.
public enum DeviceSource: String, Codable, Equatable, Sendable, CaseIterable {
    case builtIn
    case headphoneJack
    case usb
    case bluetooth
    /// An iPhone or iPad acting as a microphone over Continuity, wired or wireless.
    case continuity
    /// Loopback and capture drivers — BlackHole, Virtual Desktop, Loopback.
    case virtual
    case aggregate
    case display
    case network
    case other

    /// The chip shown next to the device name. `nil` where there is nothing useful
    /// to say: a label reading "Unknown" is worse than no label at all.
    public var label: String? {
        switch self {
        case .builtIn: "Built-in"
        case .headphoneJack: "Headphone jack"
        case .usb: "USB"
        case .bluetooth: "Bluetooth"
        case .continuity: "Continuity"
        case .virtual: "Virtual"
        case .aggregate: "Aggregate"
        case .display: "Display"
        case .network: "Network"
        case .other: nil
        }
    }

    /// Whether reopening the input is worth offering for this source.
    ///
    /// Only Continuity. A phone drops the audio link on its own — the device stays
    /// listed and selected and simply delivers nothing — and rebuilding the capture
    /// chain is what brings it back. A USB microphone that has stopped has been
    /// unplugged, and no amount of reopening will help.
    public var canReconnect: Bool { self == .continuity }

    /// From the HAL's four-character codes, as `kAudioDevicePropertyTransportType`
    /// and `kAudioDevicePropertyDataSource` report them.
    ///
    /// Codes are trimmed before matching: several of them are padded to four
    /// characters with a trailing space (`"usb "`), and a schema that only matched
    /// the padded form would fail silently the first time a caller trimmed.
    /// `dataSource` means nothing except on the built-in device.
    public static func from(transport: String, dataSource: String? = nil) -> DeviceSource {
        switch transport.trimmingCharacters(in: .whitespaces) {
        case "bltn": dataSource?.trimmingCharacters(in: .whitespaces) == "emic" ? .headphoneJack : .builtIn
        case "usb": .usb
        case "blue", "blea": .bluetooth
        case "ccwd", "ccwl": .continuity
        case "virt": .virtual
        case "grup": .aggregate
        case "hdmi", "dprt": .display
        case "airp", "eavb": .network
        default: .other
        }
    }
}
