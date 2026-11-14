import Foundation

@main
struct IumrahBookingAvailabilityEstimateSmoke {
    static func main() {
        typealias E = IumrahBookingAvailabilityEstimate
        let start = "2026-11-14T11:00:00.000Z"
        let created = "2026-11-14T10:58:00Z"
        let clock = ISO8601DateFormatter()
        let t0 = clock.date(from: "2026-11-14T11:00:00Z")!
        let deadline = E.deadline(start: start, created: created, serverDeadline: "2026-11-14T17:00:00Z")!
        precondition(deadline == t0.addingTimeInterval(1800), "six hour SLA must not override estimate")
        precondition(E.remaining(until: deadline, now: t0) == 1800)
        precondition(E.remaining(until: deadline, now: t0.addingTimeInterval(61)) == 1739)
        precondition(E.remaining(until: deadline, now: t0.addingTimeInterval(1799.9)) == 1)
        precondition(E.remaining(until: deadline, now: t0.addingTimeInterval(1800)) == 0)
        precondition(E.remaining(until: deadline, now: t0.addingTimeInterval(7200)) == 0)
        precondition(E.remaining(until: deadline, now: t0.addingTimeInterval(-60)) == 1800)
        precondition(E.deadline(start: nil, created: created, serverDeadline: nil) == t0.addingTimeInterval(1680))
        precondition(E.deadline(start: "invalid", created: created, serverDeadline: nil) == t0.addingTimeInterval(1680))
        precondition(E.deadline(start: start, created: created, serverDeadline: "2026-11-14T11:15:00Z") == t0.addingTimeInterval(900))
        precondition(E.deadline(start: nil, created: "invalid", serverDeadline: nil) == nil)
        print("11/11 availability estimate checks passed")
    }
}
