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
    let minimumRate: NuiteeHotelMinimumRate?

    var roundedStars: Int { max(0, min(5, Int(stars?.rounded() ?? 0))) }
    var imageURL: String? { coverImageURL }
}

struct NuiteeHotelMinimumRate: Codable, Hashable {
    let hotelId: String
    let price: Double
    let currency: String
    let offerId: String?
}

struct NuiteeHotelListEnvelope: Decodable {
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
        all[stay.city.lowercased().contains("med") ? "madinah" : "makkah"] = stay
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }

    func selections() -> [String: NuiteeSelectedStay] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: NuiteeSelectedStay].self, from: data) else { return [:] }
        return decoded
    }
}
