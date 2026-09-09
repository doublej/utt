import ComposableArchitecture
import SwiftUI
import UttCore

/// Where the transcript goes, and whether it gets to stop on the way.
struct DeliveryPage: View {
    @Shared(.uttSettings) private var settings

    private var canReview: Bool { settings.useClipboardPaste }
    private var reviewing: Bool { settings.deliveryMode == .review }

    var body: some View {
        SettingsGroup("Paste") {
            SettingToggle(
                "Paste at the cursor",
                detail: "Off: the transcript is only copied, never pasted.",
                isOn: pasting
            )
            SettingRow("Timing", detail: canReview ? explanation : "Nothing to review while pasting is off.") {
                Picker("Timing", selection: mode) {
                    ForEach(DeliveryMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
                .disabled(!canReview)
            }
        }

        SettingsGroup("Transcript panel") {
            SettingToggle(
                "Show the transcript panel",
                detail: reviewing
                    ? "Review needs the panel. It is where ⏎ and ⎋ live."
                    : "A small card with what just went in.",
                isOn: $settings.binding(\.showTranscriptHUD)
            )
            .disabled(reviewing)
            // Review's panel is dismissed by answering it, not by waiting.
            if settings.showTranscriptHUD, !reviewing {
                SettingRow(
                    settings.hudDismissAfter > 0
                        ? "Hide the panel after \(Int(settings.hudDismissAfter))s"
                        : "Keep the panel until dismissed"
                ) {
                    Stepper("Hide after", value: $settings.binding(\.hudDismissAfter), in: 0...30, step: 1)
                        .labelsHidden()
                }
            }
        }

        SettingsGroup("Clipboard") {
            SettingToggle(
                "Leave the transcript on the clipboard",
                detail: "On: the transcript stays on your clipboard instead of what was there before.",
                isOn: $settings.binding(\.copyToClipboard)
            )
        }
    }

    private var explanation: String {
        reviewing
            ? "Review first: the transcript waits in a panel; ⏎ pastes it, ⎋ throws it away."
            : "Paste immediately: the transcript goes in at the cursor, and the panel shows what went."
    }

    /// Switching pasting off takes review with it — the same contradiction
    /// `UttSettings.normalizeDelivery` resolves on decode, resolved here on edit
    /// because these toggles write to the shared settings directly.
    private var pasting: Binding<Bool> {
        Binding(
            get: { settings.useClipboardPaste },
            set: { newValue in
                $settings.withLock {
                    $0.useClipboardPaste = newValue
                    if !newValue { $0.deliveryMode = .immediate }
                }
            }
        )
    }

    /// Turning review on turns the panel on with it: review is the panel, and the
    /// two settings in the other order would hold a transcript nothing can show.
    private var mode: Binding<DeliveryMode> {
        Binding(
            get: { settings.deliveryMode },
            set: { newValue in
                $settings.withLock {
                    $0.deliveryMode = newValue
                    if newValue == .review { $0.showTranscriptHUD = true }
                }
            }
        )
    }
}
