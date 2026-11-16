import Foundation

// Separate from the historical iumrah package catalogue. Nuitee room-only totals
// must never be decoded as complete flight+hotel+services package prices.
struct NuiteeHotel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    let address: String?
    let stars: Double?
    let rating: Double?
    let reviewCount: Int?
    let coverImageURL: String?
    let previewImages: [String]?
    let latitude: Double?
    let longitude: Double?
    var minimumRate: NuiteeHotelMinimumRate?
    var rateStatus: String? = nil

    var roundedStars: Int { max(0, min(5, Int(stars?.rounded() ?? 0))) }
    var imageURL: String? { coverImageURL }
}

struct NuiteeHotelMinimumRate: Codable, Hashable {
    let hotelId: String
    let price: Double
    let currency: String
    let offerId: String?
}

struct NuiteeHotelListEnvelope: Codable {
    let ok: Bool
    let sandbox: Bool
    let city: String
    let checkin: String
    let checkout: String
    let adults: Int
    let hotelCatalogStale: Bool
    let pricesStale: Bool
    let pricesUpdatedAt: Double?
    let rateError: String?
    let hotels: [NuiteeHotel]
    var total: Int? = nil
    var nextOffset: Int? = nil
}

extension NuiteeHotelListEnvelope {
    /// Older unified Worker contracts return the entire city without pagination.
    /// Apply the exact same filters locally only for that response shape.
    static func normalizedPage(_ result: NuiteeHotelListEnvelope, stars: Int, offset: Int, pageSize: Int,
                               query: String, favorites: Set<String>?) -> NuiteeHotelListEnvelope {
        guard result.total == nil else { return result }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = result.hotels.filter { hotel in
            (stars == 0 || hotel.roundedStars == stars) &&
            (favorites == nil || favorites?.contains(hotel.id) == true) &&
            (term.isEmpty || hotel.name.localizedCaseInsensitiveContains(term) || (hotel.address?.localizedCaseInsensitiveContains(term) ?? false))
        }
        let start = min(max(0, offset), filtered.count)
        let end = start + min(max(1, pageSize), filtered.count - start)
        return NuiteeHotelListEnvelope(ok: result.ok, sandbox: result.sandbox, city: result.city,
            checkin: result.checkin, checkout: result.checkout, adults: result.adults,
            hotelCatalogStale: result.hotelCatalogStale, pricesStale: result.pricesStale, pricesUpdatedAt: result.pricesUpdatedAt,
            rateError: result.rateError, hotels: Array(filtered[start..<end]), total: filtered.count,
            nextOffset: end < filtered.count ? end : nil)
    }
}

struct NuiteeHotelPolicy: Codable, Hashable, Identifiable {
    let title: String
    let description: String
    var id: String { title + description }
}

struct NuiteeRoomDescription: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String
    let maxOccupancy: Int?
    let images: [String]
    let amenities: [String]
}

struct NuiteeHotelDetail: Codable, Hashable {
    let id: String
    let name: String
    let city: String
    let address: String?
    let stars: Double?
    let rating: Double?
    let reviewCount: Int?
    let coverImageURL: String?
    let latitude: Double?
    let longitude: Double?
    let description: String
    let importantInformation: String
    let images: [String]
    let rooms: [NuiteeRoomDescription]
    let amenities: [String]
    let policies: [NuiteeHotelPolicy]
    let checkin: String?
    let checkout: String?
}

struct NuiteeHotelDetailEnvelope: Decodable {
    let ok: Bool
    let sandbox: Bool
    let hotel: NuiteeHotelDetail
}

struct NuiteeCancellationDeadline: Codable, Hashable {
    let until: String
    let amount: Double?
}

struct NuiteeArrivalCharge: Codable, Hashable {
    let amount: Double?
    let currency: String
}

struct NuiteeRoomRate: Codable, Hashable, Identifiable {
    let offerId: String
    let roomId: String
    let roomName: String
    let mealPlan: String
    let price: Double
    let currency: String
    let refundable: Bool
    let cancellationTag: String
    let cancellationDescription: String
    let cancellationDeadlines: [NuiteeCancellationDeadline]
    let chargeOnArrival: [NuiteeArrivalCharge]
    var includedMeals: HotelMealChoices? = nil

    var id: String { offerId + "|" + roomId + "|" + roomName }
}

struct NuiteeRatesEnvelope: Decodable {
    let ok: Bool
    let sandbox: Bool
    let checkin: String
    let checkout: String
    let adults: Int
    let rates: [NuiteeRoomRate]
    let cached: Bool
}

struct NuiteeSelectedStay: Codable {
    let provider: String
    let hotelId: String
    let hotelName: String
    let city: String
    let checkin: String
    let checkout: String
    let adults: Int
    let offerId: String
    let roomId: String
    let roomName: String
    let totalUSD: Double
    let mealPlan: String
    let cancellationTag: String
    let selectedAt: Date
}

@MainActor
final class NuiteeStaySelectionStore {
    static let shared = NuiteeStaySelectionStore()
    private let key = "iumrah.nuitee.hotelSelections.v1"

    func save(_ stay: NuiteeSelectedStay) {
        var all = selections()
        let city = stay.city.lowercased()
        let isMadinah = city.contains("mad") || city.contains("med") || city.contains("المدينة")
        all[isMadinah ? "madinah" : "makkah"] = stay
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    func remove(city: String) {
        var all = selections()
        all.removeValue(forKey: city)
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    func selections() -> [String: NuiteeSelectedStay] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NuiteeSelectedStay].self, from: data) else { return [:] }
        return decoded
    }
}

struct NuiteeGuestReview: Decodable, Identifiable {
    let id: String
    let name: String
    let country: String
    let date: String
    let rating: Double?
    let headline: String
    let pros: String
    let cons: String
    let source: String
    let language: String
    let originalHeadline: String?
    let originalPros: String?
    let originalCons: String?
    let isTranslated: Bool?
    let translationUnavailable: Bool?
}
struct NuiteeReviewsEnvelope: Decodable {
    let ok: Bool
    let reviews: [NuiteeGuestReview]
    let total: Int?
    let nextOffset: Int?
    let stale: Bool
}
