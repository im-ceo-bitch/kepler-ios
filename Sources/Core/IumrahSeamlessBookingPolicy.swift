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
    /// Local routing only; every request still requires a valid server credential.
    static func careIsActive(_ status: String) -> Bool {
        let status = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return !status.isEmpty && !["COMPLETED", "CANCELLED", "CANCELED", "DELETED"].contains(status)
    }
    static func careScope(status: String, bookingID: String, bookingToken: String,
                          owner: String?, accountOwner: String?, accountToken: String?) -> String? {
        guard careIsActive(status), !bookingID.isEmpty, bookingID != "account" else { return nil }
        if let token = accountToken, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           sameIdentity(owner, accountOwner) { return "account" }
        return bookingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bookingID
    }
}
