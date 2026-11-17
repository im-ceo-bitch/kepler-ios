import Foundation

@main struct IumrahGuestCarePolicySmoke {
    static func main() {
        func scope(_ status: String = "AVAILABILITY_CHECK", proof: String = "guest-proof", owner: String? = "00000090", accountOwner: String? = nil, accountToken: String? = nil, id: String = "trip-a") -> String? {
            IumrahSeamlessBookingPolicy.careScope(status: status, bookingID: id, bookingToken: proof, owner: owner, accountOwner: accountOwner, accountToken: accountToken)
        }
        let checks: [(String, Bool)] = [
            ("Guest checking availability", scope() == "trip-a"),
            ("Guest new booking", scope("NEW") == "trip-a"),
            ("Guest paid", scope("BOOKING_CONFIRMED") == "trip-a"),
            ("Guest in trip", scope("IN_TRIP") == "trip-a"),
            ("No proof no chat", scope(proof: "") == nil),
            ("Whitespace proof rejected", scope(proof: "  ") == nil),
            ("Same owner uses unified chat", scope(accountOwner: "90", accountToken: "verified") == "account"),
            ("Restored account booking", scope(proof: "", accountOwner: "90", accountToken: "verified") == "account"),
            ("Unrelated signed-in account uses guest proof", scope(accountOwner: "91", accountToken: "verified") == "trip-a"),
            ("Unrelated account cannot open booking without proof", scope(proof: "", accountOwner: "91", accountToken: "verified") == nil),
            ("Unknown owner does not use account route", scope(owner: nil, accountOwner: "90", accountToken: "verified") == "trip-a"),
            ("Completed booking closed", scope("COMPLETED") == nil),
            ("Cancelled booking closed", scope("cancelled") == nil),
            ("Deleted booking closed", scope("DELETED") == nil),
            ("Invalid account sentinel rejected", scope(id: "account") == nil),
            ("No credential inferred from ID", scope(proof: "", accountOwner: "90") == nil)
        ]
        for (name, ok) in checks { precondition(ok, name); print("PASS: \(name)") }
        print("\(checks.count)/\(checks.count) guest Care routing checks passed")
    }
}
