import SwiftUI
import UIKit
import CoreHaptics

struct IumrahLaunchLink: Equatable {
    let id = UUID()
    let url: URL
}

/// Only one cinematic launch per process, including on iPad/Mac windows.
@MainActor
private enum IumrahLaunchGate {
    static var claimed = false
    static func claim() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// Cold-launch animation. No network, dependency loading, or app-store work in
/// the animation itself. Mount RootView near the hand-off, not behind the globe.
struct IumrahLaunchExperience<Content: View>: View {
    private let contentBuilder: (IumrahLaunchLink?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("iumrah.hasCompletedOnboarding.cinematic.v4") private var onboarded = false
    @ObservedObject private var quickActions = IumrahQuickActionCenter.shared
    @State private var contentMounted = false
    @State private var splashVisible = true
    @State private var hasStarted = false
    @State private var startDate: Date?
    @State private var launchLink: IumrahLaunchLink?

    init(@ViewBuilder content: @escaping (IumrahLaunchLink?) -> Content) {
        self.contentBuilder = content
    }

    var body: some View {
        GeometryReader { viewport in
            ZStack {
                if contentMounted {
                    contentBuilder(launchLink)
                        .allowsHitTesting(!splashVisible)
                        .accessibilityHidden(splashVisible)
                } else {
                    Color("LaunchBackground").ignoresSafeArea()
                }
                if splashVisible {
                    IumrahSignatureLaunchLayer(startDate: startDate, reduceMotion: reduceMotion,
                                               handoffToHeader: onboarded,
                                               topInset: viewport.safeAreaInsets.top)
                        .ignoresSafeArea()
                        .zIndex(1000)
                        .transition(.identity)
                        .accessibilityHidden(true)
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await runLaunchSequenceIfNeeded()
        }
        // Cold deep links must not be lost while RootView is not mounted.
        // Route in the root exactly once via the unique link ID.
        .onOpenURL { url in receive(url) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { receive(url) }
        }
        .onChange(of: quickActions.pendingRequest, initial: true) { _, request in
            if request != nil, splashVisible { finish() }
        }
        .onChange(of: scenePhase) { _, phase in
            if hasStarted, phase != .active, splashVisible { finish() }
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

    @MainActor private func runLaunchSequenceIfNeeded() async {
        guard !hasStarted else { return }
        guard IumrahLaunchGate.claim(), quickActions.pendingRequest == nil, launchLink == nil else {
            finish(); return
        }
        hasStarted = true
        let trace = IumrahPerformanceTrace.begin("Cold launch handoff")
        defer { IumrahPerformanceTrace.end("Cold launch handoff", trace) }
        let clock = ContinuousClock()
        let start = clock.now
        startDate = Date()
        let haptics = IumrahLaunchHaptics()
        defer { haptics.stop(); finish() }

        if reduceMotion {
            contentMounted = true
            try? await clock.sleep(until: start.advanced(by: .milliseconds(180)))
            return
        }
        haptics.prepare()
        func wait(_ seconds: Double) async -> Bool {
            do { try await clock.sleep(until: start.advanced(by: .milliseconds(Int64(seconds * 1000)))) }
            catch { return false }
            return !Task.isCancelled && splashVisible && scenePhase == .active
        }
        guard await wait(IumrahLaunchGeometry.firstPulse) else { return }
        // A late first frame must never cause two taps back-to-back.
        if start.duration(to: clock.now) < .milliseconds(250) { haptics.pulse(intensity: 0.30, sharpness: 0.20) }
        guard await wait(IumrahLaunchGeometry.secondPulse) else { return }
        if start.duration(to: clock.now) < .milliseconds(1050) { haptics.pulse(intensity: 0.48, sharpness: 0.26) }
        guard await wait(IumrahLaunchGeometry.mountContent) else { return }
        contentMounted = true
        await Task.yield()
        _ = await wait(IumrahLaunchGeometry.duration)
    }
}

/// One transient per beat; a ready Core Haptics engine is preferred, with a
/// prepared UIKit soft impact fallback. Never play sound or block launch.
@MainActor
private final class IumrahLaunchHaptics {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var ready = false
    private var stopped = false
    private var fallback: UIImpactFeedbackGenerator?

    func prepare() {
        #if !targetEnvironment(macCatalyst)
        fallback = UIImpactFeedbackGenerator(style: .soft)
        fallback?.prepare()
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine = try? CHHapticEngine() else { return }
        self.engine = engine
        engine.playsHapticsOnly = true
        engine.start(completionHandler: { [weak self] error in
            let succeeded = error == nil
            Task { @MainActor in
                guard let self, !self.stopped else { return }
                self.ready = succeeded
            }
        })
        #endif
    }

    func pulse(intensity: Float, sharpness: Float) {
        #if !targetEnvironment(macCatalyst)
        guard !stopped else { return }
        if ready, let engine {
            do {
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ], relativeTime: 0)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                self.player = player
                return
            } catch { ready = false }
        }
        fallback?.impactOccurred(intensity: CGFloat(intensity))
        fallback?.prepare()
        #endif
    }

    func stop() {
        stopped = true
        ready = false
        engine?.stop(completionHandler: nil)
        player = nil
        engine = nil
        fallback = nil
    }
}
