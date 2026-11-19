import Foundation

// Linux-compatible observation shims: exercise the actual catalog model, not SwiftUI rendering.
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
protocol ObservableObject {}
enum NuiteeCity: String { case makkah, madinah }
enum APIError: Error { case invalidResponse }

actor CatalogFixture {
    static let shared = CatalogFixture()
    private var attempts: [String:Int] = [:]
    func next(_ id: String) -> Int { attempts[id, default: 0] += 1; return attempts[id]! }
    func count(_ id: String) -> Int { attempts[id, default: 0] }
}
struct NuiteeHotelService {
    struct PriceRow: Sendable { let id: String; let minimumRate: NuiteeHotelMinimumRate?; let rateStatus: String? }
    struct PricePage { let ok: Bool; let sandbox: Bool; let pricesStale: Bool; let rateError: String?; let hotels: [PriceRow] }
    struct CatalogRateResult: Sendable { let row: PriceRow; let rateLimited: Bool }
    static func dateText(_ date: Date) -> String { String(Calendar.current.startOfDay(for: date).timeIntervalSince1970) }
    static func isRateLimited(_ error: Error) -> Bool { false }
    static func positive(_ id: String, _ price: Double) -> PriceRow {
        .init(id:id, minimumRate:.init(hotelId:id,price:price,currency:"USD",offerId:"offer-\(id)"),rateStatus:"available")
    }
    func hotels(city:String,checkin:Date,checkout:Date,adults:Int,catalogOnly:Bool) async throws -> NuiteeHotelListEnvelope {
        let ids = city == "makkah" ? (1...87).map { "page\($0)" } : ["lp1", "lp2", "lp3", "lp4"]
        let items = ids.map { id in
            NuiteeHotel(id:id,name:id,city:city,address:nil,stars:4,rating:nil,reviewCount:nil,coverImageURL:nil,previewImages:nil,latitude:nil,longitude:nil,minimumRate:nil)
        }
        return .init(ok:true,sandbox:false,city:city,checkin:"",checkout:"",adults:adults,hotelCatalogStale:false,pricesStale:false,pricesUpdatedAt:nil,rateError:nil,hotels:items)
    }
    func pricePage(city:String,checkin:Date,checkout:Date,adults:Int,hotelIDs:[String],childrenAges:[Int] = []) async throws -> PricePage {
        if city == "makkah" {
            _ = await CatalogFixture.shared.next("batch")
            try await Task.sleep(nanoseconds: 150_000_000)
            return .init(ok:true,sandbox:false,pricesStale:false,rateError:nil,hotels:hotelIDs.map{Self.positive($0,200)})
        }
        return .init(ok:true,sandbox:false,pricesStale:false,rateError:nil,hotels:hotelIDs.filter{$0 == "lp1"}.map{Self.positive($0,childrenAges.isEmpty ? 200 : 350)})
    }
    func catalogRate(hotelID:String,checkin:Date,checkout:Date,adults:Int,childrenAges:[Int] = []) async -> CatalogRateResult {
        let count = await CatalogFixture.shared.next(hotelID)
        let row: PriceRow
        switch hotelID {
        case "lp2": row = Self.positive(hotelID, 300)
        case "lp3": row = count == 1 ? .init(id:hotelID,minimumRate:nil,rateStatus:"not_returned") : Self.positive(hotelID,400)
        default: row = .init(id:hotelID,minimumRate:nil,rateStatus:"no_availability")
        }
        return .init(row:row,rateLimited:false)
    }
}
@main struct CatalogHydrationSmoke {
    @MainActor static func main() async {
        let model=NuiteeCatalogModel(), start=Date(), end=Date().addingTimeInterval(172800)
        await model.reload(city:.madinah,checkin:start,checkout:end,adults:2)
        precondition(model.hotels.count == 4)
        precondition(model.hotels[0].minimumRate?.price == 200)
        precondition(model.hotels[1].minimumRate?.price == 300)
        precondition(model.hotels[2].rateStatus == "not_returned")
        precondition(model.hotels[3].rateStatus == "no_availability")
        precondition(model.rateError == "RATES_INCOMPLETE")
        let initialCount=await CatalogFixture.shared.count("lp1")
        precondition(initialCount == 0)
        await model.retryMissingPrices(city:.madinah,checkin:start,checkout:end,adults:2)
        precondition(model.hotels[0].minimumRate?.price == 200 && model.hotels[1].minimumRate?.price == 300)
        precondition(model.hotels[2].minimumRate?.price == 400)
        precondition(model.hotels[3].rateStatus == "no_availability" && model.rateError == nil)
        let secondCount=await CatalogFixture.shared.count("lp2"), unavailableCount=await CatalogFixture.shared.count("lp4")
        precondition(secondCount == 1 && unavailableCount == 1)
        await model.reload(city:.madinah,checkin:start,checkout:end,adults:2,childrenAges:[7])
        precondition(model.hotels[0].minimumRate?.price == 350)
        precondition(!model.matches(city:.madinah,checkin:start,checkout:end,adults:2,stars:0,query:"",favorites:nil))
        await model.reload(city:.madinah,checkin:start,checkout:end,adults:2)
        precondition(model.hotels[0].minimumRate?.price == 200)
        let paged = NuiteeCatalogModel()
        let task = Task { await paged.reload(city:.makkah,checkin:start,checkout:end,adults:2) }
        for _ in 0..<100 { if paged.pricesLoading { break }; try? await Task.sleep(nanoseconds: 1_000_000) }
        precondition(paged.pricesLoading && paged.hotels.count == 87)
        precondition(paged.visibleHotels(stars: 4).count == 87)
        precondition(paged.visibleHotels(stars: 5).isEmpty)
        precondition(paged.visibleHotels(stars: 0, query: "page27").count == 1)
        precondition(paged.matches(city:.makkah,checkin:start,checkout:end,adults:2,stars:5,query:"page27",favorites:nil))
        await paged.loadMore(city:.makkah,checkin:start,checkout:end,adults:2)
        precondition(paged.hotels.count == 87 && paged.pricesLoading)
        await task.value
        precondition(paged.hotels.allSatisfy { $0.minimumRate?.price == 200 })
        precondition(!paged.pricesLoading && paged.nextOffset == nil)
        let batchCount = await CatalogFixture.shared.count("batch")
        precondition(batchCount == 3)
        await paged.reload(city:.makkah,checkin:start,checkout:end,adults:2,stars:5)
        let afterFilter = await CatalogFixture.shared.count("batch")
        precondition(afterFilter == batchCount)
        print("Configurator: child occupancy isolates prices; all metadata visible during rate hydration; filters local — passed")
        print("Catalog hydration: partial batch, automatic individual fallback, targeted retry, retained positive prices, confirmed unavailability — passed")
    }
}
