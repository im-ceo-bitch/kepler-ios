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
        try await APIClient.hotelPrices.get("/api/package/nuitee/hotels", query: [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "checkin", value: Self.dateText(checkin)),
            URLQueryItem(name: "checkout", value: Self.dateText(checkout)),
            URLQueryItem(name: "adults", value: String(adults)),
            URLQueryItem(name: "catalogOnly", value: catalogOnly ? "1" : "0")
        ], timeoutInterval: 604800)
    }

    func detail(hotelID: String, language: String = "en") async throws -> NuiteeHotelDetail {
        let response: NuiteeHotelDetailEnvelope = try await api.get(
            "/api/package/nuitee/hotel", query: [URLQueryItem(name: "hotelId", value: hotelID), URLQueryItem(name: "language", value: language)], timeoutInterval: 35
        )
        return response.hotel
    }

    func reviews(hotelID: String, language: String, offset: Int = 0) async throws -> NuiteeReviewsEnvelope {
        try await api.get("/api/package/nuitee/reviews", query: [
            URLQueryItem(name: "hotelId", value: hotelID),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "offset", value: String(offset))
        ], timeoutInterval: 35)
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
        return try await APIClient.hotelPrices.post("/api/package/nuitee/rates", body: Request(
            hotelId: hotelID, checkin: Self.dateText(checkin), checkout: Self.dateText(checkout), adults: adults, children: childrenAges, language: language
        ), timeoutInterval: 604800)
    }

    static func deadlineText(_ value: String, locale: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd HH:mm:ss"
        guard let date = parser.date(from: value) else { return value }
        let display = DateFormatter(); display.locale = Locale(identifier: locale)
        display.timeZone = parser.timeZone; display.dateStyle = .medium; display.timeStyle = .short
        return display.string(from: date)
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
