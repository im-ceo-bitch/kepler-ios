import Foundation
import Security

enum BookingSessionVault {
    private static let service = "com.iumrah.app.booking-sessions"
    private static let account = "sessions"

    private static let queue = DispatchQueue(label: "com.iumrah.booking.vault", qos: .userInitiated)
    // Only successful reads/writes are cached; a temporarily locked Keychain
    // must not be mistaken for a durable empty vault.
    private static var persisted: [StoredBookingSession]?

    static func load() -> [StoredBookingSession] {
        queue.sync { loadLocked() }
    }

    static func loadAsync() async -> [StoredBookingSession] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: loadLocked()) }
        }
    }

    private static func loadLocked() -> [StoredBookingSession] {
        if let persisted { return persisted }
        let trace = IumrahPerformanceTrace.begin("Booking vault read")
        defer { IumrahPerformanceTrace.end("Booking vault read", trace) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return [] }
        guard let sessions = try? JSONDecoder().decode([StoredBookingSession].self, from: data) else { return [] }
        persisted = sessions
        return sessions
    }

    @discardableResult
    static func save(_ sessions: [StoredBookingSession]) -> Bool {
        queue.sync { saveLocked(sessions) }
    }

    /// All async booking operations await this ordered background write before
    /// returning. The synchronous migration path still uses save(_:).
    @MainActor
    static func saveAsync(_ sessions: [StoredBookingSession]) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: saveLocked(sessions)) }
        }
    }

    private static func saveLocked(_ sessions: [StoredBookingSession]) -> Bool {
        if persisted == sessions { return true }
        let trace = IumrahPerformanceTrace.begin("Booking vault write")
        defer { IumrahPerformanceTrace.end("Booking vault write", trace) }
        guard let data = try? JSONEncoder().encode(sessions) else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { persisted = sessions; return true }
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let ok = SecItemAdd(add as CFDictionary, nil) == errSecSuccess
            if ok { persisted = sessions }
            return ok
        }
        return false
    }
}

/// One-time cleanup for the pre-account device identities. These values are no longer
/// accepted as user identity: the permanent eight-digit iumrah ID is the only account identity.
enum LegacyClientIdentityCleanup {
    static func purge() {
        for account in ["client-user-id", "stable-client-id"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.iumrah.app.client-identity",
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}
