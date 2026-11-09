import Foundation

struct NuiteeHotelService {
    private let api = APIClient.shared

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        // DatePicker produces local calendar days; UTC can shift dates in Uzbekistan.
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func hotels(city: String, checkin: Date, checkout: Date, adults: Int, catalogOnly: Bool = false) async throws -> NuiteeHotelListEnvelope {
        try await api.get("/api/package/nuitee/hotels", query: [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "checkin", value: Self.dateText(checkin)),
            URLQueryItem(name: "checkout", value: Self.dateText(checkout)),
            URLQueryItem(name: "adults", value: String(adults)),
            URLQueryItem(name: "catalogOnly", value: catalogOnly ? "1" : "0")
        ], timeoutInterval: 35)
    }

    func detail(hotelID: String, language: String = "en") async throws -> NuiteeHotelDetail {
        let response: NuiteeHotelDetailEnvelope = try await api.get(
            "/api/package/nuitee/hotel", query: [URLQueryItem(name: "hotelId", value: hotelID), URLQueryItem(name: "language", value: language)], timeoutInterval: 35
        )
        return response.hotel
    }

    func rates(hotelID: String, checkin: Date, checkout: Date, adults: Int, childrenAges: [Int] = [], language: String = "en") async throws -> NuiteeRatesEnvelope {
        struct Request: Encodable {
            let hotelId: String
            let checkin: String
            let checkout: String
            let adults: Int
            let children: [Int]
            let language: String
        }
        return try await api.post("/api/package/nuitee/rates", body: Request(
            hotelId: hotelID, checkin: Self.dateText(checkin), checkout: Self.dateText(checkout), adults: adults, children: childrenAges, language: language
        ), timeoutInterval: 35)
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}

extension AppSettingsStore.Language {
    var hotelContentCode: String {
        switch self {
        case .russian: return "ru"
        case .uzbek: return "uz"
        case .uzbekCyrillic: return "uz-Cyrl"
        default: return String(rawValue.prefix(2)).lowercased()
        }
    }
}
