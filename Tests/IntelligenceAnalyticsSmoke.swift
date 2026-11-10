import Foundation

@main
struct IntelligenceAnalyticsSmoke {
    static func main() async throws {
        let storage = UserDefaults.standard
        storage.removeObject(forKey: "iumrah.intelligence.enabled")
        storage.removeObject(forKey: "iumrah.intelligence.visitor.v1")
        storage.removeObject(forKey: "iumrah.intelligence.pending.v1")
        storage.removeObject(forKey: "iumrah.hasCompletedOnboarding.cinematic.v4")
        let tracker = IumrahIntelligence.shared
        await tracker.start(initialScreen: "onboarding")
        await tracker.record("onboarding_step", screen: "onboarding", element: "step_0")
        await tracker.screenChanged(to: "home")
        await tracker.record("tap", screen: "home", element: "flights")
        await tracker.record("search_started", screen: "flights", element: "global")
        await tracker.enterBackground()
        guard let data = storage.data(forKey: "iumrah.intelligence.pending.v1") else {
            fatalError("Telemetry must remain queued when network is absent")
        }
        let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        let names = records.compactMap { ($0["event"] as? [String: Any])?["name"] as? String }
        precondition(names.contains("app_first_open"))
        precondition(names.contains("screen_view"))
        precondition(names.contains("screen_exit"))
        precondition(names.contains("app_background"))
        let sessions = Set(records.compactMap { $0["sessionId"] as? String })
        precondition(sessions.count == 1)
        let firstSession = sessions.first!
        let events = records.compactMap { $0["event"] as? [String: Any] }
        let payload: [String: Any] = [
            "visitorId": storage.string(forKey: "iumrah.intelligence.visitor.v1")!,
            "sessionId": firstSession,
            "platform": "ios",
            "appVersion": "2.1.0",
            "events": events
        ]
        let output = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(data: output, encoding: .utf8)!)
        await tracker.setEnabled(false)
        precondition(storage.data(forKey: "iumrah.intelligence.pending.v1") == nil)
        precondition(storage.string(forKey: "iumrah.intelligence.visitor.v1") == nil)
    }
}
