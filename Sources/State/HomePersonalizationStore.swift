import Foundation
import Combine

struct HomeSmartDraft: Codable, Hashable {
    var preferences: SmartConfiguratorPreferences
    var step: Int
    var wasAssembled: Bool
    var updatedAt: Date = Date()
}

struct HomeHotelVisit: Codable, Hashable, Identifiable {
    var hotel: NuiteeHotel
    var checkin: Date
    var nights: Int
    var adults: Int
    var sandbox: Bool
    var viewedAt: Date = Date()
    var id: String { hotel.id }
}

struct HomeActivitySnapshot: Codable {
    var smart: HomeSmartDraft?
    var flightSearch: TripDraft?
    var hotels: [HomeHotelVisit] = []
}

/// Small, device-local convenience history. Never stores booking tokens, quotes,
/// passports or payment data. Account histories cannot be read by other accounts.
@MainActor
final class HomePersonalizationStore: ObservableObject {
    static let shared = HomePersonalizationStore()
    private let defaults: UserDefaults
    private let historyKey = "iumrah.home.activity.v1"
    private let preferenceKey = "iumrah.home.personalization.enabled.v1"
    private var histories: [String: HomeActivitySnapshot]
    @Published private(set) var revision = 0
    @Published private(set) var enabled: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let initialEnabled = defaults.object(forKey: preferenceKey) as? Bool ?? true
        enabled = initialEnabled
        histories = initialEnabled ? (defaults.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([String: HomeActivitySnapshot].self, from: $0) } ?? [:]) : [:]
    }

    static func owner(_ account: IumrahAccountStore) -> String? {
        guard account.isAuthenticated else { return "guest" }
        guard let id = account.iumrahID, !id.isEmpty else { return nil }
        return "account:" + id
    }

    func snapshot(owner: String?) -> HomeActivitySnapshot {
        guard enabled, let owner else { return HomeActivitySnapshot() }
        var value = histories[owner] ?? HomeActivitySnapshot()
        let today = Calendar.current.startOfDay(for: Date())
        let month = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
        if let smart = value.smart, smart.preferences.month < month { value.smart = nil }
        if let trip = value.flightSearch, trip.departureDate < today { value.flightSearch = nil }
        return value
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        defaults.set(value, forKey: preferenceKey)
        if !value { histories.removeAll(); defaults.removeObject(forKey: historyKey) }
        revision &+= 1
    }

    func clear(owner: String?) {
        guard let owner else { return }
        histories.removeValue(forKey: owner)
        persist()
    }

    func saveSmart(_ value: HomeSmartDraft?, owner: String?) {
        update(owner: owner) { $0.smart = value }
    }

    func saveFlight(_ value: TripDraft, owner: String?) {
        update(owner: owner) { $0.flightSearch = value }
    }

    func visitHotel(_ value: HomeHotelVisit, owner: String?) {
        var clean = value
        clean.hotel.minimumRate = nil // Prices are never replayed from history.
        clean.hotel.rateStatus = nil
        update(owner: owner) {
            $0.hotels.removeAll { $0.id == clean.id }
            $0.hotels.insert(clean, at: 0)
            $0.hotels = Array($0.hotels.prefix(6))
        }
    }

    private func update(owner: String?, _ body: (inout HomeActivitySnapshot) -> Void) {
        guard enabled, let owner else { return }
        var value = histories[owner] ?? HomeActivitySnapshot()
        body(&value)
        histories[owner] = value
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(histories) { defaults.set(data, forKey: historyKey) }
        revision &+= 1
    }
}
