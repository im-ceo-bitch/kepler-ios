import Foundation

@main struct IumrahSeamlessBookingPolicySmoke {
    static func main() {
        let checks: [(String, Bool)] = [
            ("Canonical ID with leading zeros", IumrahSeamlessBookingPolicy.sameIdentity("00001234", "1234")),
            ("Different owners never match", !IumrahSeamlessBookingPolicy.sameIdentity("00001234", "00001235")),
            ("Missing IDs never match", !IumrahSeamlessBookingPolicy.sameIdentity(nil, nil)),
            ("Zero IDs never match", !IumrahSeamlessBookingPolicy.sameIdentity("0", "00000000")),
            ("Invalid IDs never match", !IumrahSeamlessBookingPolicy.sameIdentity("", "unknown")),
            ("Email normalized", IumrahSeamlessBookingPolicy.matchesContact(email: " Example@Mail.com ", phone: nil, channel: "email", contact: "example@mail.com")),
            ("Different email rejected", !IumrahSeamlessBookingPolicy.matchesContact(email: "a@example.com", phone: nil, channel: "email", contact: "b@example.com")),
            ("Phone normalized", IumrahSeamlessBookingPolicy.matchesContact(email: nil, phone: "+998 (90) 123-45-67", channel: "sms", contact: "+998901234567")),
            ("Different phone rejected", !IumrahSeamlessBookingPolicy.matchesContact(email: nil, phone: "+998901234567", channel: "sms", contact: "+998901234568")),
            ("Unknown channel rejected", !IumrahSeamlessBookingPolicy.matchesContact(email: "a@example.com", phone: nil, channel: "telegram", contact: "a@example.com")),
            ("Missing contact rejected", !IumrahSeamlessBookingPolicy.matchesContact(email: nil, phone: nil, channel: "email", contact: "a@example.com")),
            ("Channel cannot substitute identity", !IumrahSeamlessBookingPolicy.matchesContact(email: "a@example.com", phone: nil, channel: "sms", contact: "a@example.com")),
        ]
        for (name, ok) in checks { precondition(ok, name); print("PASS: \(name)") }
        print("\(checks.count)/\(checks.count) seamless booking policy checks passed")
    }
}
