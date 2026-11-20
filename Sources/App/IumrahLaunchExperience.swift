import SwiftUI

struct IumrahLaunchLink: Equatable {
    let id = UUID()
    let url: URL
}

/// Present the system's static launch image, then hand off immediately to
/// RootView. The gate prevents repeated haptics and splash re-entry in scenes.
@MainActor
private enum IumrahLaunchGate {
    static var claimed = false
    static func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

struct IumrahLaunchExperience<Content: View>: View {
    private let contentBuilder: (IumrahLaunchLink?) -> Content
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var quickActions = IumrahQuickActionCenter.shared
    @State private var contentMounted = false
    @State private var splashVisible = true
    @State private var hasStarted = false
    @State private var launchLink: IumrahLaunchLink?

    init(@ViewBuilder content: @escaping (IumrahLaunchLink?) -> Content) {
        contentBuilder = content
    }

    var body: some View {
        ZStack {
            if contentMounted {
                contentBuilder(launchLink)
                    .allowsHitTesting(!splashVisible)
                    .accessibilityHidden(splashVisible)
            } else {
                Color("LaunchBackground").ignoresSafeArea()
            }
            if splashVisible {
                IumrahSignatureLaunchLayer()
                    .ignoresSafeArea()
                    .zIndex(1000)
                    .accessibilityHidden(true)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await finishColdLaunchIfNeeded()
        }
        .onOpenURL { url in receive(url) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { receive(url) }
        }
        .onChange(of: quickActions.pendingRequest, initial: true) { _, request in
            if request != nil && splashVisible { finish() }
        }
        .onChange(of: scenePhase) { _, phase in
            if hasStarted && phase != .active && splashVisible { finish() }
        }
    }

    @MainActor private func receive(_ url: URL) {
        launchLink = IumrahLaunchLink(url: url)
        if splashVisible { finish() }
    }

    @MainActor private func finish() {
        _ = IumrahLaunchGate.claim()
        hasStarted = true
        contentMounted = true
        splashVisible = false
    }

    @MainActor private func finishColdLaunchIfNeeded() async {
        guard !hasStarted else { return }
        guard IumrahLaunchGate.claim(), quickActions.pendingRequest == nil, launchLink == nil else {
            finish()
            return
        }
        hasStarted = true
        contentMounted = true
        // One render opportunity; no artificial sleep, animated stages or timers.
        await Task.yield()
        guard !Task.isCancelled, scenePhase == .active, splashVisible else {
            finish()
            return
        }
        IumrahHaptics.soft()
        finish()
    }
}
