import ComposableArchitecture
import SwiftUI

struct AppRootView: View {
    @Bindable var store: StoreOf<AppFeature>
    @State private var collapsed = false
    @State private var showingGuide = false
    @State private var showingOnboarding = false
    @Shared(.uttSettings) private var settings
    /// Shared rather than local: the transcript panel's "Add rule" opens this
    /// window on the Text tab from outside the window entirely.
    @Bindable private var route = SettingsRoute.shared

    private var showingSettings: Bool { route.isOpen }

    /// The three shapes the window takes. Kept here rather than in feature state:
    /// nothing outside this view reacts to them, and a reducer that owns window
    /// geometry is a reducer that cannot be tested without a screen.
    private var size: CGSize {
        if collapsed { return CGSize(width: 360, height: 48) }
        if showingSettings { return CGSize(width: 760, height: 820) }
        return CGSize(width: 720, height: 540)
    }

    var body: some View {
        Group {
            if collapsed {
                CollapsedBar(store: store, showingSettings: $route.isOpen, collapsed: $collapsed)
            } else {
                expanded
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(Backdrop(collapsed: collapsed))
        .animation(.smooth(duration: 0.25), value: collapsed)
        .animation(.smooth(duration: 0.25), value: showingSettings)
        .background(WindowConfigurator(collapsed: collapsed))
        // Two sheets, two jobs. Repairing one permission six months in should not
        // replay a welcome screen, so the banner and "Walk me through it" keep the
        // guide and only a first launch gets the flow.
        .sheet(isPresented: $showingGuide) { PermissionGuide(store: store) }
        .sheet(isPresented: $showingOnboarding) { OnboardingFlow(store: store) }
        // A first launch is the one moment where nothing is granted and the user is
        // watching, so the walkthrough opens itself rather than waiting to be found.
        // The flag is the whole condition: a settings file exists from the first
        // store write onwards, so anything derived from the file cannot tell a first
        // launch from a deliberate replay.
        .task { if !settings.hasCompletedOnboarding { showingOnboarding = true } }
        // Settings can be opened from the transcript panel while the window is
        // the pill — which has nowhere to show them. Expand first.
        .onChange(of: showingSettings) { _, isOpen in
            if isOpen { collapsed = false }
        }
    }

    private var expanded: some View {
        VStack(spacing: Spacing.extraSmall) {
            HeaderBar(store: store, showingSettings: $route.isOpen, collapsed: $collapsed)
            if let banner {
                BannerRow(text: banner, action: bannerAction)
            }
            RecorderModule(store: store)
            if showingSettings {
                SettingsPanel(store: store, showingGuide: $showingGuide, showingOnboarding: $showingOnboarding)
            } else {
                HistoryList(store: store)
            }
        }
        .padding(Spacing.medium)
    }

    /// One line, for the one problem most worth fixing right now. Three stacked
    /// warnings would push the actual app off the screen.
    private var banner: String? {
        if store.needsRelaunch { return "A permission was granted — restart utt to pick it up." }
        if let first = store.missingPermissions.first {
            return "\(first.title) is off. Turn it on \(first.rationale)."
        }
        if case let .failed(message) = store.model { return message }
        if case let .failed(message) = store.transcription.status { return message }
        return nil
    }

    /// Only the permission banners get a button. A model that failed to load has no
    /// one-click answer, and the old unconditional `missingPermissions[0]` was a
    /// crash waiting for the first model failure with every permission granted.
    private var bannerAction: (() -> Void)? {
        guard store.needsRelaunch || !store.missingPermissions.isEmpty else { return nil }
        return { showingGuide = true }
    }
}

private struct BannerRow: View {
    let text: String
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.extraSmall) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
            Text(text)
                .font(Typography.metadata)
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            if let action {
                Button("Fix", action: action)
                    .font(Typography.metadata)
            }
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                .fill(Palette.warning.opacity(0.12))
        )
    }
}

private struct Backdrop: ViewModifier {
    let collapsed: Bool

    func body(content: Content) -> some View {
        if collapsed {
            // The pill draws its own capsule, so the window behind it must be
            // clear — a material here would show as a rectangle around the curve.
            content
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
            content.containerBackground(.regularMaterial, for: .window)
        }
    }
}
