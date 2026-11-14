import Foundation

@main struct IumrahPerformanceSmoke {
    static func main() {
        let memo = IumrahViewMemo<Int, Int>()
        var calls = 0
        for _ in 0..<1000 { precondition(memo.value(for: 1) { calls += 1; return 42 } == 42) }
        precondition(calls == 1)
        precondition(memo.value(for: 2) { calls += 1; return 43 } == 43 && calls == 2)
        precondition(memo.value(for: 1) { calls += 1; return 44 } == 44 && calls == 3)
        let timestamp = "2026-11-14T22:15:00Z"
        for _ in 0..<1000 {
            precondition(IumrahFlightClock.local(timestamp, airport: "TAS") == "2026-11-15T03:15:00")
            precondition(IumrahFlightClock.local(timestamp, airport: "JED") == "2026-11-15T01:15:00")
        }
        precondition(IumrahFlightClock.local("2026-11-14T22:15:00.123Z", airport: "TAS") == "2026-11-15T03:15:00")
        precondition(IumrahFlightClock.local("2026-11-14T22:15:00", airport: "TAS") == "2026-11-14T22:15:00")
        precondition(IumrahFlightClock.local(timestamp, airport: "XXX") == timestamp)
        let actual = IumrahFlightClock.arrival(actual: timestamp, departure: "", duration: 0, origin: "TAS", destination: "JED")
        precondition(actual?.time == "01:15" && actual?.day == "2026-11-15" && actual?.estimated == false)
        let estimate = IumrahFlightClock.arrival(actual: nil, departure: "2026-11-14T22:15:00", duration: 300, origin: "TAS", destination: "JED")
        precondition(estimate?.time == "01:15" && estimate?.day == "2026-11-15" && estimate?.estimated == true)
        let locale = Locale(identifier: "en_US")
        precondition(IumrahFlightClock.day(timestamp, locale: locale) == IumrahFlightClock.day(timestamp, locale: locale))
        print("PASS: snapshot memoization, invalidation, 2000 repeated timezone conversions, actual/estimated arrivals")
    }
}
