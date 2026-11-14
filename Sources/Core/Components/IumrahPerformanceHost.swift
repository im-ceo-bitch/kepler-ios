import SwiftUI
import Combine
import UIKit
import Darwin

private struct IumrahPerformanceProfileKey: EnvironmentKey {
    static let defaultValue: IumrahPerformanceProfile = .balanced
}
private struct IumrahActiveTabKey: EnvironmentKey {
    static let defaultValue = true
}
extension EnvironmentValues {
    var iumrahPerformanceProfile: IumrahPerformanceProfile {
        get { self[IumrahPerformanceProfileKey.self] }
        set { self[IumrahPerformanceProfileKey.self] = newValue }
    }
    var iumrahTabIsActive: Bool {
        get { self[IumrahActiveTabKey.self] }
        set { self[IumrahActiveTabKey.self] = newValue }
    }
}

struct IumrahPerformanceHost: ViewModifier {
    private static let initialProfile = currentProfile()
    @State private var profile = Self.initialProfile
    private static func currentProfile() -> IumrahPerformanceProfile {
        let info = ProcessInfo.processInfo
        var system = utsname()
        uname(&system)
        let machine = Mirror(reflecting: system.machine).children.compactMap { child -> UInt8? in
            guard let value = child.value as? Int8, value != 0 else { return nil }
            return UInt8(bitPattern: value)
        }
        let name = info.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? String(decoding: machine, as: UTF8.self)
        return .resolve(machine: name, memoryBytes: info.physicalMemory,
                        lowPower: info.isLowPowerModeEnabled,
                        thermalLimited: info.thermalState == .serious || info.thermalState == .critical)
    }
    func body(content: Content) -> some View {
        content.environment(\.iumrahPerformanceProfile, profile)
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in update() }
            .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification).receive(on: RunLoop.main)) { _ in update() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification).receive(on: RunLoop.main)) { _ in
                Task { await HotelImageCache.shared.purgeMemory() }
            }
            .onAppear { update() }
            .task(id: profile) {
                guard !Task.isCancelled else { return }
                await HotelImageCache.shared.setMemoryLimit(profile.imageMemoryLimit)
            }
    }
    private func update() {
        let next = Self.currentProfile()
        if next != profile { profile = next }
    }
}

/// Isolates decorative ticks from the parent; no ticking in background or on
/// retained inactive tabs. Does not cap native scrolling, video or audio.
struct IumrahDecorativeTimeline<Content: View>: View {
    var maxFPS: Double = 30
    var paused = false
    var staticWhenConstrained = false
    private let content: (Date) -> Content

    init(maxFPS: Double = 30, paused: Bool = false, staticWhenConstrained: Bool = false, @ViewBuilder content: @escaping (Date) -> Content) {
        self.maxFPS = maxFPS
        self.paused = paused
        self.staticWhenConstrained = staticWhenConstrained
        self.content = content
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.iumrahPerformanceProfile) private var profile
    @Environment(\.iumrahTabIsActive) private var activeTab
    @State private var visible = false

    var body: some View {
        let stopped = paused || reduceMotion || !visible || !activeTab || scenePhase != .active || (staticWhenConstrained && profile.staticBackgrounds)
        TimelineView(.animation(minimumInterval: 1 / max(1, min(maxFPS, profile.decorativeFPS)), paused: stopped)) { context in
            content(stopped ? Date(timeIntervalSinceReferenceDate: 0) : context.date)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }
}
