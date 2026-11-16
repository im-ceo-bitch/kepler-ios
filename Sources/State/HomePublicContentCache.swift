import Foundation

/// Public, non-sensitive discovery cache. Only reads existing published offers
/// and catalogue metadata; never requests a package generation or live rate scan.
@MainActor
final class HomePublicContentCache {
    static let shared = HomePublicContentCache()
    private struct PackageEntry { let date: Date; let values: [StorefrontServerPackageSnapshot] }
    private struct HotelEntry { let date: Date; let value: NuiteeHotelListEnvelope? }
    private struct PackageEnvelope: Decodable { let ok: Bool; let items: [StorefrontServerPackageSnapshot] }
    private var packageEntries: [String: PackageEntry] = [:]
    private var packageTasks: [String: Task<[StorefrontServerPackageSnapshot], Never>] = [:]
    private var hotelEntries: [String: HotelEntry] = [:]
    private var hotelTasks: [String: Task<NuiteeHotelListEnvelope?, Never>] = [:]

    func packages(origin: String) async -> [StorefrontServerPackageSnapshot] {
        let key = origin.uppercased()
        if let entry = packageEntries[key], Date().timeIntervalSince(entry.date) < 300 { return entry.values }
        if let task = packageTasks[key] { return await task.value }
        let task = Task { @MainActor () -> [StorefrontServerPackageSnapshot] in
            defer { packageTasks[key] = nil }
            let values: [StorefrontServerPackageSnapshot]
            do {
                let response: PackageEnvelope = try await APIClient.shared.get("/api/storefront/packages", query: [
                    URLQueryItem(name: "mode", value: "hotel-first"), URLQueryItem(name: "origins", value: key), URLQueryItem(name: "limit", value: "24")
                ], timeoutInterval: 15)
                let today = SmartConfiguratorPreferences.key(Date())
                values = response.ok ? Array(response.items.filter {
                    $0.status.lowercased() == "ready" && $0.currency.uppercased() == "USD" && ($0.pricePerPerson ?? 0) > 0 &&
                    $0.originCode.uppercased() == key && String($0.startDate.prefix(10)) >= today &&
                    $0.id.range(of: "^\\d{10}$", options: .regularExpression) != nil
                }.sorted { $0.startDate < $1.startDate }.prefix(4)) : []
            } catch { values = [] }
            if packageEntries.count >= 8 { packageEntries.removeAll() }
            packageEntries[key] = .init(date: Date(), values: values)
            return values
        }
        packageTasks[key] = task
        return await task.value
    }

    func hotels(city: String, checkin: Date, nights: Int, adults: Int) async -> NuiteeHotelListEnvelope? {
        let checkout = Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin
        let key = [city, SmartConfiguratorPreferences.key(checkin), SmartConfiguratorPreferences.key(checkout), String(adults)].joined(separator: "-")
        if let entry = hotelEntries[key], Date().timeIntervalSince(entry.date) < 900 { return entry.value }
        if let task = hotelTasks[key] { return await task.value }
        let task = Task { @MainActor () -> NuiteeHotelListEnvelope? in
            defer { hotelTasks[key] = nil }
            let service = NuiteeHotelService()
            let rates = await service.cachedHotels(city: city, checkin: checkin, checkout: checkout, adults: adults)
            let catalogue = await service.cachedHotels(city: city, checkin: checkin, checkout: checkout, adults: adults, catalogOnly: true)
            var result = rates ?? catalogue
            if result == nil {
                result = try? await service.hotels(city: city, checkin: checkin, checkout: checkout, adults: adults, catalogOnly: true, smartTimeout: true)
            }
            if hotelEntries.count >= 8 { hotelEntries.removeAll() }
            hotelEntries[key] = .init(date: Date(), value: result)
            return result
        }
        hotelTasks[key] = task
        return await task.value
    }
}
