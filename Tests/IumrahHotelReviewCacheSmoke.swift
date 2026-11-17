import Foundation
struct NuiteeGuestReview { let id: String }
struct NuiteeReviewsEnvelope { let ok: Bool; let reviews: [NuiteeGuestReview]; let total: Int?; let nextOffset: Int?; let stale: Bool }
enum APIError: Error { case invalidResponse }
actor MockReviewAPI {
    static let shared = MockReviewAPI()
    var calls: [String:Int] = [:]
    func fetch(hotelID: String, language: String, offset: Int) async throws -> NuiteeReviewsEnvelope {
        calls[hotelID+"|"+language+"|"+String(offset),default:0] += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        if hotelID == "bad" { throw APIError.invalidResponse }
        if hotelID == "empty" { return .init(ok:true,reviews:[],total:0,nextOffset:nil,stale:false) }
        return .init(ok:true,reviews:offset == 0 ? [.init(id:"a"),.init(id:"b")] : [.init(id:"b"),.init(id:"c")],total:3,nextOffset:offset == 0 ? 2:nil,stale:false)
    }
    func count(_ key: String) -> Int { calls[key,default:0] }
}
struct NuiteeHotelService { func reviews(hotelID:String,language:String,offset:Int) async throws -> NuiteeReviewsEnvelope { try await MockReviewAPI.shared.fetch(hotelID:hotelID,language:language,offset:offset) } }
@main struct Tests {
    static func main() async throws {
        let c = IumrahHotelReviewCache()
        async let a = c.load(hotelID:"1",language:"ru",more:false)
        async let b = c.load(hotelID:"1",language:"ru",more:false)
        let (one,two) = try await (a,b); precondition(one.reviews.count == 2 && two.reviews.count == 2)
        let count1 = await MockReviewAPI.shared.count("1|ru|0"); precondition(count1 == 1)
        let next = try await c.load(hotelID:"1",language:"ru",more:true); precondition(next.reviews.map(\.id) == ["a","b","c"] && next.nextOffset == nil)
        let again = try await c.load(hotelID:"1",language:"ru",more:false); precondition(again.reviews.count == 3)
        let more = try await c.load(hotelID:"1",language:"ru",more:true); precondition(more.reviews.count == 3)
        let count2 = await MockReviewAPI.shared.count("1|ru|2"); precondition(count2 == 1)
        _ = try await c.load(hotelID:"1",language:"en",more:false); let count3 = await MockReviewAPI.shared.count("1|en|0"); precondition(count3 == 1)
        _ = try await c.load(hotelID:"2",language:"ru",more:false); let count4 = await MockReviewAPI.shared.count("2|ru|0"); precondition(count4 == 1)
        _ = try await c.load(hotelID:"empty",language:"ru",more:false); _ = try await c.load(hotelID:"empty",language:"ru",more:false); let count5 = await MockReviewAPI.shared.count("empty|ru|0"); precondition(count5 == 1)
        do { _ = try await c.load(hotelID:"bad",language:"ru",more:false); fatalError("Expected error") } catch { }
        do { _ = try await c.load(hotelID:"bad",language:"ru",more:false); fatalError("Expected error") } catch { }
        let count6 = await MockReviewAPI.shared.count("bad|ru|0"); precondition(count6 == 2)
        print("Review cache: PASS (coalescing, pagination, dedup, language/hotel isolation, empty response, retry)")
    }
}
