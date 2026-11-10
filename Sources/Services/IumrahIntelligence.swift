import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// First-party, pseudonymous product analytics for the unified iumrah-backend.
/// Callers must pass STATIC screen/element codes, never user-entered text or IDs.
/// No advertising ID, account ID, IP, search query, booking ID or passport data.
actor IumrahIntelligence {
    static let shared = IumrahIntelligence()

    static let enabledKey = "iumrah.intelligence.enabled"
    private static let visitorKey = "iumrah.intelligence.visitor.v1"
    private static let pendingKey = "iumrah.intelligence.pending.v1"
    private static let endpoint = URL(string: "https://iumrah-backend.helloiumrah.workers.dev/api/catalog/hotels/intelligence/events")!
    private static let maxPending = 150

    private struct Event: Codable {
        let id: String
        let name: String
        let screen: String
        let elementId: String
        let occurredAt: String
        let durationMs: Int?
    }

    private struct PendingEvent: Codable {
        let sessionId: String
        let event: Event
    }

    private struct Batch: Encodable {
        let visitorId: String
        let sessionId: String
        let platform: String
        let appVersion: String
        let events: [Event]
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private var visitorId: String?
    private var sessionId = UUID().uuidString.lowercased()
    private var pending: [PendingEvent]
    private var currentScreen: String?
    private var screenEnteredAt: Date?
    private var detailScreenTimes: [String: Date] = [:]
    private var started = false
    private var inBackground = false
    private var flushing = false
    private var flushScheduled = false
    private var flushMoreAfterSuccess = false

    private var enabled: Bool {
        defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey)
    }

    private init() {
        defaults = .standard
        visitorId = defaults.string(forKey: Self.visitorKey)
        if let data = defaults.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([PendingEvent].self, from: data) {
            pending = Array(saved.suffix(Self.maxPending))
        } else {
            pending = []
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        session = URLSession(configuration: configuration)
    }

    func start(initialScreen: String) {
        guard enabled, !started else { return }
        started = true
        let firstInstallationTelemetry = visitorId == nil
        if visitorId == nil {
            let generated = UUID().uuidString.lowercased()
            visitorId = generated
            defaults.set(generated, forKey: Self.visitorKey)
        }
        // This key already exists for people who used an earlier iumrah build.
        // Such upgrades must not be incorrectly counted as new installations.
        if firstInstallationTelemetry &&
            !defaults.bool(forKey: "iumrah.hasCompletedOnboarding.cinematic.v4") {
            add("app_first_open")
        }
        add("app_open")
        openScreen(initialScreen)
        scheduleFlush()
    }

    func record(_ name: String, screen: String? = nil, element: String = "") {
        guard started, enabled, !inBackground else { return }
        add(name, screen: screen ?? currentScreen ?? "", element: element)
    }

    func screenChanged(to name: String) {
        guard started, enabled, !inBackground else { return }
        if currentScreen == name { return }
        closeScreen()
        openScreen(name)
    }

    /// Explicit deep-page tracking complements the persistent five-tab journey.
    func detailAppeared(_ raw: String) {
        guard started, enabled, !inBackground else { return }
        let screen = Self.code(raw)
        guard detailScreenTimes[screen] == nil else { return }
        detailScreenTimes[screen] = Date()
        add("screen_view", screen: screen)
    }

    func detailDisappeared(_ raw: String) {
        guard started, enabled else { return }
        let screen = Self.code(raw)
        guard let since = detailScreenTimes.removeValue(forKey: screen) else { return }
        let duration = min(3_600_000, max(0, Int(Date().timeIntervalSince(since) * 1000)))
        add("screen_exit", screen: screen, durationMs: duration)
    }

    func enterBackground() {
        guard started, enabled, !inBackground else { return }
        closeScreen()
        for screen in Array(detailScreenTimes.keys) { detailDisappeared(screen) }
        add("app_background")
        inBackground = true
        Task { await flush() }
    }

    func resume(initialScreen: String) {
        guard enabled else { return }
        if !started { start(initialScreen: initialScreen); return }
        guard inBackground else { return }
        inBackground = false
        sessionId = UUID().uuidString.lowercased()
        add("app_open")
        openScreen(initialScreen)
        scheduleFlush()
    }

    func setEnabled(_ value: Bool, currentScreen: String = "account") {
        defaults.set(value, forKey: Self.enabledKey)
        if !value {
            pending = []
            defaults.removeObject(forKey: Self.pendingKey)
            defaults.removeObject(forKey: Self.visitorKey)
            visitorId = nil
            self.currentScreen = nil
            screenEnteredAt = nil
            detailScreenTimes.removeAll()
            started = false
            inBackground = false
        } else if !started {
            start(initialScreen: currentScreen)
        }
    }

    private func openScreen(_ raw: String) {
        let screen = Self.code(raw)
        currentScreen = screen
        screenEnteredAt = Date()
        add("screen_view", screen: screen)
    }

    private func closeScreen() {
        guard let screen = currentScreen, let entered = screenEnteredAt else { return }
        let duration = min(3_600_000, max(0, Int(Date().timeIntervalSince(entered) * 1000)))
        add("screen_exit", screen: screen, durationMs: duration)
        currentScreen = nil
        screenEnteredAt = nil
    }

    private static func code(_ raw: String) -> String {
        let value = raw.replacingOccurrences(of: "[^a-zA-Z0-9_.-]", with: "_", options: .regularExpression)
        return String(value.prefix(64))
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func add(_ name: String, screen: String = "", element: String = "", durationMs: Int? = nil) {
        guard enabled else { return }
        // No arbitrary metadata: the backend independently validates all names.
        let event = Event(
            id: UUID().uuidString.lowercased(), name: Self.code(name),
            screen: Self.code(screen), elementId: Self.code(element),
            occurredAt: Self.timeString(Date()), durationMs: durationMs
        )
        pending.append(PendingEvent(sessionId: sessionId, event: event))
        // Events older than the server's seven-day validation window cannot be replayed.
        let cutoff = Date().addingTimeInterval(-6 * 86400)
        pending = Array(pending.filter {
            guard let date = ISO8601DateFormatter.iumrahParse($0.event.occurredAt) else { return false }
            return date >= cutoff
        }.suffix(Self.maxPending))
        persistPending()
        scheduleFlush()
    }

    private func persistPending() {
        if pending.isEmpty { defaults.removeObject(forKey: Self.pendingKey) }
        else if let encoded = try? JSONEncoder().encode(pending) {
            defaults.set(encoded, forKey: Self.pendingKey)
        }
    }

    private func scheduleFlush() {
        guard enabled, !flushScheduled, !pending.isEmpty else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            await flush()
            flushScheduled = false
            if flushMoreAfterSuccess {
                flushMoreAfterSuccess = false
                scheduleFlush()
            }
        }
    }

    func flush() async {
        guard enabled, !flushing, let visitorId, let first = pending.first else { return }
        flushing = true
        defer { flushing = false }
        // An ingest batch can contain only ONE sessionId; do not combine launches.
        let selected = Array(pending.prefix(while: { $0.sessionId == first.sessionId }).prefix(20))
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        let batch = Batch(visitorId: visitorId, sessionId: first.sessionId, platform: "ios",
                          appVersion: Self.code(version), events: selected.map(\.event))
        guard let data = try? JSONEncoder().encode(batch), data.count <= 16_384 else { return }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 202, enabled else { return }
            let sentIds = Set(selected.map(\.event.id))
            pending.removeAll { sentIds.contains($0.event.id) }
            persistPending()
            flushMoreAfterSuccess = !pending.isEmpty
        } catch {
            // Network failures never block UI or generate loops. Retry on next activity.
        }
    }
}

private extension ISO8601DateFormatter {
    static func iumrahParse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
