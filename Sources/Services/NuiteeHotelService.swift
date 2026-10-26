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

    func hotels(city: String, checkin: Date, checkout: Date, adults: Int) async throws -> NuiteeHotelListEnvelope {
        try await api.get("/api/package/nuitee/hotels", query: [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "checkin", value: Self.dateText(checkin)),
            URLQueryItem(name: "checkout", value: Self.dateText(checkout)),
            URLQueryItem(name: "adults", value: String(adults))
        ], timeoutInterval: 35)
    }

    func detail(hotelID: String) async throws -> NuiteeHotelDetail {
        let response: NuiteeHotelDetailEnvelope = try await api.get(
            "/api/package/nuitee/hotel", query: [URLQueryItem(name: "hotelId", value: hotelID)], timeoutInterval: 25
        )
        return response.hotel
    }

    func rates(hotelID: String, checkin: Date, checkout: Date, adults: Int) async throws -> NuiteeRatesEnvelope {
        struct Request: Encodable {
            let hotelId: String
            let checkin: String
            let checkout: String
            let adults: Int
        }
        return try await api.post("/api/package/nuitee/rates", body: Request(
            hotelId: hotelID, checkin: Self.dateText(checkin), checkout: Self.dateText(checkout), adults: adults
        ), timeoutInterval: 35)
    }

    static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }
}
