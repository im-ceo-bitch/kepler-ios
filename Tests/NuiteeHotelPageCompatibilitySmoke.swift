import Foundation

@main struct NuiteeHotelPageCompatibilitySmoke {
    static func main() throws {
        let json = """
        {"ok":true,"sandbox":false,"city":"makkah","checkin":"2026-11-25","checkout":"2026-11-28","adults":2,"hotelCatalogStale":false,"pricesStale":false,"rateError":"RATES_UNAVAILABLE","hotels":[
        {"id":"a","name":"Alpha","city":"makkah","stars":3,"rateStatus":"provider_error"},
        {"id":"b","name":"Beta","city":"makkah","stars":4},
        {"id":"c","name":"Alpha Annex","city":"makkah","stars":3},
        {"id":"d","name":"Delta","city":"makkah","stars":3}]}
        """
        let legacy = try JSONDecoder().decode(NuiteeHotelListEnvelope.self, from: Data(json.utf8))
        precondition(legacy.total == nil)
        func page(_ stars: Int = 0, _ offset: Int = 0, _ size: Int = 2, _ query: String = "", _ ids: Set<String>? = nil) -> NuiteeHotelListEnvelope {
            NuiteeHotelListEnvelope.normalizedPage(legacy, stars: stars, offset: offset, pageSize: size, query: query, favorites: ids)
        }
        let first = page(3)
        precondition(first.total == 3 && first.nextOffset == 2 && first.hotels.map(\.id) == ["a", "c"])
        precondition(first.rateError == "RATES_UNAVAILABLE" && first.hotels.first?.minimumRate == nil)
        let next = page(3, 2)
        precondition(next.total == 3 && next.nextOffset == nil && next.hotels.map(\.id) == ["d"])
        precondition(page(4).hotels.map(\.id) == ["b"])
        precondition(page(3, 0, 10, "alpha").total == 2)
        precondition(page(0, 0, 10, "", ["b"]).hotels.map(\.id) == ["b"])
        precondition(page(0, 0, 10, "", []).total == 0)
        precondition(page(3, 99).hotels.isEmpty && page(3, 99).nextOffset == nil)
        let modern = NuiteeHotelListEnvelope.normalizedPage(first, stars: 4, offset: 10, pageSize: 1, query: "other", favorites: [])
        precondition(modern.hotels.map(\.id) == ["a", "c"] && modern.total == 3 && modern.nextOffset == 2)
        let unknown = NuiteeHotel(id: "unknown", name: "Unrated", city: "madinah", address: nil, stars: nil, rating: nil, reviewCount: nil, coverImageURL: nil, previewImages: nil, latitude: nil, longitude: nil, minimumRate: nil)
        let unrated = NuiteeHotelListEnvelope(ok: true, sandbox: false, city: "madinah", checkin: "2026-11-25", checkout: "2026-11-28", adults: 2, hotelCatalogStale: false, pricesStale: false, pricesUpdatedAt: nil, rateError: nil, hotels: [unknown])
        for stars in 1...5 { precondition(NuiteeHotelListEnvelope.normalizedPage(unrated, stars: stars, offset: 0, pageSize: 12, query: "", favorites: nil).hotels.map(\.id) == ["unknown"]) }
        // Official and manual share 12-item pages, deduplication and cursor handling.
        let many = (0..<35).map { index in
            NuiteeHotel(id: "h\(index)", name: "Hotel \(index)", city: "makkah", address: nil, stars: 3, rating: nil, reviewCount: nil, coverImageURL: nil, previewImages: nil, latitude: nil, longitude: nil, minimumRate: nil)
        }
        let full = NuiteeHotelListEnvelope(ok: true, sandbox: false, city: "makkah", checkin: "2026-11-25", checkout: "2026-11-28", adults: 2, hotelCatalogStale: false, pricesStale: false, pricesUpdatedAt: nil, rateError: nil, hotels: many)
        var accumulated: [NuiteeHotel] = []
        var offset = 0
        for expected in [12, 24, 35] {
            let page = NuiteeHotelListEnvelope.normalizedPage(full, stars: 3, offset: offset, pageSize: NuiteeHotelPaging.pageSize, query: "", favorites: nil)
            accumulated = NuiteeHotelPaging.append(accumulated, page.hotels)
            precondition(accumulated.count == expected)
            if let next = NuiteeHotelPaging.nextOffset(page, requestedOffset: offset) { offset = next }
            else { precondition(expected == 35) }
        }
        precondition(accumulated.map(\.id) == many.map(\.id))
        precondition(NuiteeHotelPaging.append(accumulated, many).count == 35)
        var totalOnly = first; totalOnly.nextOffset = nil
        precondition(NuiteeHotelPaging.nextOffset(totalOnly, requestedOffset: 0) == 2)
        var invalid = first; invalid.nextOffset = 0
        precondition(NuiteeHotelPaging.nextOffset(invalid, requestedOffset: 0) == nil)
        var cursorOnly = first; cursorOnly.total = nil
        precondition(NuiteeHotelListEnvelope.normalizedPage(cursorOnly, stars: 3, offset: 0, pageSize: 1, query: "", favorites: nil).hotels.count == 2)
        precondition(NuiteeHotelPaging.nextOffset(cursorOnly, requestedOffset: 0) == 2)
        print("PASS: legacy decoding, filters, pagination, outage and modern response compatibility")
    }
}
