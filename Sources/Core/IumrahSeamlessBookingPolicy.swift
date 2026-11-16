import Foundation

/// Pure checks for client routing. These never replace the server's ownership check.
enum IumrahSeamlessBookingPolicy {
    static func sameIdentity(_ left: String?, _ right: String?) -> Bool {
        guard let left, let right,
              let lhs = Int(left.filter(\.isNumber)), let rhs = Int(right.filter(\.isNumber)),
              lhs > 0, rhs > 0 else { return false }
        return lhs == rhs
    }
    static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static func normalizedPhone(_ value: String) -> String { "+" + value.filter(\.isNumber) }
    static func matchesContact(email: String?, phone: String?, channel: String, contact: String) -> Bool {
        if channel == "email", let email, !email.isEmpty { return normalizedEmail(email) == normalizedEmail(contact) }
        if channel == "sms", let phone, !phone.isEmpty { return normalizedPhone(phone) == normalizedPhone(contact) }
        return false
    }
}
