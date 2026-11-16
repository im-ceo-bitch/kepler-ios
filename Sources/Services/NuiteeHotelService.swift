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

    private func listKey(city: String, checkin: Date, checkout: Date, adults: Int, catalogOnly: Bool) -> String {
        "\(city.lowercased())-\(Self.dateText(checkin))-\(Self.dateText(checkout))-\(adults)-\(catalogOnly ? "catalog" : "rates")"
    }

    func cachedHotels(city: String, checkin: Date, checkout: Date, adults: Int, catalogOnly: Bool = false) async -> NuiteeHotelListEnvelope? {
        await NuiteeDailyHotelCache.shared.read(key: listKey(city: city, checkin: checkin, checkout: checkout, adults: adults, catalogOnly: catalogOnly))
    }

    func hotels(city: String, checkin: Date, checkout: Date, adults: Int, catalogOnly: Bool = false, forceRefresh: Bool = false, smartTimeout: Bool = false) async throws -> NuiteeHotelListEnvelope {
        let key = listKey(city: city, checkin: checkin, checkout: checkout, adults: adults, catalogOnly: catalogOnly)
        if !forceRefresh, let cached = await NuiteeDailyHotelCache.shared.read(key: key) { return cached }
        let response: NuiteeHotelListEnvelope = try await (smartTimeout ? APIClient.shared : APIClient.hotelPrices).get("/api/package/nuitee/hotels", query: [
            URLQueryItem(name: "city", value: city),
            URLQueryItem(name: "checkin", value: Self.dateText(checkin)),
            URLQueryItem(name: "checkout", value: Self.dateText(checkout)),
            URLQueryItem(name: "adults", value: String(adults)),
            URLQueryItem(name: "catalogOnly", value: catalogOnly ? "1" : "0")
         ], timeoutInterval: smartTimeout ? 45 : 604800)
        // Cache successful responses while preserving upstream staleness flags.
        // Provider failures are never saved as successful results.
        if response.ok && (catalogOnly || response.rateError == nil) {
            await NuiteeDailyHotelCache.shared.write(response, key: key)
        }
        return response
    }

    func hotelPage(city: String, checkin: Date, checkout: Date, adults: Int, stars: Int = 0,
                   offset: Int = 0, pageSize: Int = 10, query: String = "", favorites: Set<String>? = nil,
                   catalogOnly: Bool = false, allowCatalogFallback: Bool = true) async throws -> NuiteeHotelListEnvelope {
        var params = [URLQueryItem(name: "city", value: city), URLQueryItem(name: "checkin", value: Self.dateText(checkin)),
                      URLQueryItem(name: "checkout", value: Self.dateText(checkout)), URLQueryItem(name: "adults", value: String(adults)),
                      URLQueryItem(name: "stars", value: String(stars)), URLQueryItem(name: "offset", value: String(offset)),
                      URLQueryItem(name: "pageSize", value: String(pageSize)), URLQueryItem(name: "query", value: query),
                      URLQueryItem(name: "catalogOnly", value: catalogOnly ? "1" : "0")]
        if let favorites { params.append(URLQueryItem(name: "hotelIds", value: favorites.sorted().joined(separator: ","))) }
        do {
            let result: NuiteeHotelListEnvelope = try await api.get("/api/package/nuitee/hotels", query: params, timeoutInterval: 45)
            guard result.ok else { throw APIError.invalidResponse }
            return NuiteeHotelListEnvelope.normalizedPage(result, stars: stars, offset: offset, pageSize: pageSize, query: query, favorites: favorites)
        } catch {
            try Task.checkCancellation()
            guard !catalogOnly, allowCatalogFallback else { throw error }
            // A provider outage must not remove the independently available catalogue.
            let fallback = try await hotelPage(city: city, checkin: checkin, checkout: checkout, adults: adults,
                stars: stars, offset: offset, pageSize: pageSize, query: query, favorites: favorites, catalogOnly: true, allowCatalogFallback: false)
            let rows = fallback.hotels.map { hotel -> NuiteeHotel in
                var row = hotel; row.minimumRate = nil; row.rateStatus = "provider_error"; return row
            }
            return NuiteeHotelListEnvelope(ok: fallback.ok, sandbox: fallback.sandbox, city: fallback.city,
                checkin: fallback.checkin, checkout: fallback.checkout, adults: fallback.adults,
                hotelCatalogStale: fallback.hotelCatalogStale, pricesStale: false, pricesUpdatedAt: nil,
                rateError: "RATES_UNAVAILABLE", hotels: rows, total: fallback.total, nextOffset: fallback.nextOffset)
        }
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

    func rates(hotelID: String, checkin: Date, checkout: Date, adults: Int, childrenAges: [Int] = [], language: String = "en", smartTimeout: Bool = false) async throws -> NuiteeRatesEnvelope {
        struct Request: Encodable {
            let hotelId: String
            let checkin: String
            let checkout: String
            let adults: Int
            let children: [Int]
            let language: String
        }
        return try await (smartTimeout ? APIClient.shared : APIClient.hotelPrices).post("/api/package/nuitee/rates", body: Request(
            hotelId: hotelID, checkin: Self.dateText(checkin), checkout: Self.dateText(checkout), adults: adults, children: childrenAges, language: language
        ), timeoutInterval: smartTimeout ? 35 : 604800)
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
