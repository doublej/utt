import ComposableArchitecture
import SwiftUI
import UttCore

/// Where the transcript goes, and whether it gets to stop on the way.
struct DeliveryCard: View {
    @Shared(.uttSettings) private var settings

    private var canReview: Bool { settings.useClipboardPaste }
    private var reviewing: Bool { settings.deliveryMode == .review }

    var body: some View {
        Card("Delivery") {
            Toggle("Paste at the cursor", isOn: pasting)
                .help("Off: the transcript is only copied, never pasted")

            Picker("Delivery", selection: mode) {
                ForEach(DeliveryMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(!canReview)
            .help(canReview ? explanation : "Nothing to review — pasting is off")

            Text(explanation)
                .font(Typography.hint)
                .foregroundStyle(Palette.textTertiary)

            Toggle("Show the transcript panel", isOn: bind(\.showTranscriptHUD))
                .disabled(reviewing)
                .help(reviewing ? "Review needs the panel — it is where ⏎ and ⎋ live" : "")

            dismissDelay

            Toggle("Leave the transcript on the clipboard", isOn: bind(\.copyToClipboard))
                .help("On: utt does not restore what you had copied before")
        }
    }

    private var explanation: String {
        reviewing
            ? "Review first: the transcript waits in a panel; ⏎ pastes it, ⎋ throws it away."
            : "Paste immediately: the transcript goes in at the cursor, and the panel shows what went."
    }

    @ViewBuilder
    private var dismissDelay: some View {
        // Review's panel is dismissed by answering it, not by waiting.
        if settings.showTranscriptHUD, !reviewing {
            Stepper(value: bind(\.hudDismissAfter), in: 0...30, step: 1) {
                Text(
                    settings.hudDismissAfter > 0
                        ? "Hide the panel after \(Int(settings.hudDismissAfter))s"
                        : "Keep the panel until dismissed"
                )
                .font(Typography.metadata)
            }
        }
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

    private func bind<Value>(
        _ keyPath: WritableKeyPath<UttSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { newValue in $settings.withLock { $0[keyPath: keyPath] = newValue } }
        )
    }
}
