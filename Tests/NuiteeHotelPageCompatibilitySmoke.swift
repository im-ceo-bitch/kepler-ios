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
        print("PASS: legacy decoding, filters, pagination, outage and modern response compatibility")
    }
}
