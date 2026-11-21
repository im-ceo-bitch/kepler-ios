import Foundation
struct Hotel: Equatable, Identifiable { let id: String; let roundedStars: Int; let minimumRate: Double?; let rateStatus: String? }
@MainActor
final class Catalog {
    var hotels: [Hotel] = []
    private static func uniqueHotels(_ rows: [Hotel]) -> [Hotel] {
        var seen = Set<String>()
        return rows.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
    func visibleHotels(stars: Int) -> [Hotel] {
        let rows = hotels.filter { stars == 0 || $0.roundedStars == stars || $0.roundedStars == 0 }
        return stars == 0 ? rows : rows.filter { $0.roundedStars == stars } + rows.filter { $0.roundedStars == 0 }
    }
    func mergeMetadata(_ new: [Hotel], sameScope: Bool) {
        let old = Dictionary(self.hotels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let oldOrder = Dictionary(self.hotels.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let fresh = Self.uniqueHotels(new)
        let ordered = sameScope
            ? fresh.enumerated().sorted {
                let a = oldOrder[$0.element.id] ?? Int.max
                let b = oldOrder[$1.element.id] ?? Int.max
                return a == b ? $0.offset < $1.offset : a < b
            }.map(\.element)
            : fresh
        self.hotels = ordered.map { hotel in
            let previous = old[hotel.id]
            return Hotel(id: hotel.id, roundedStars: hotel.roundedStars, minimumRate: sameScope ? previous?.minimumRate : nil, rateStatus: sameScope ? previous?.rateStatus : nil)
        }
    }
}
@main struct Test {
    static func main() async {
        let c = Catalog()
        c.mergeMetadata([Hotel(id:"a",roundedStars:5,minimumRate:nil,rateStatus:nil), Hotel(id:"b",roundedStars:0,minimumRate:nil,rateStatus:nil), Hotel(id:"a",roundedStars:5,minimumRate:nil,rateStatus:nil), Hotel(id:"c",roundedStars:5,minimumRate:nil,rateStatus:nil)], sameScope:false)
        precondition(c.visibleHotels(stars:5).map(\.id)==["a","c","b"])
        c.mergeMetadata([Hotel(id:"c",roundedStars:5,minimumRate:1,rateStatus:"available"),Hotel(id:"a",roundedStars:5,minimumRate:nil,rateStatus:"no_availability"), Hotel(id:"b",roundedStars:0,minimumRate:4,rateStatus:"available"), Hotel(id:"d",roundedStars:5,minimumRate:nil,rateStatus:nil)], sameScope:true)
        precondition(c.visibleHotels(stars:5).map(\.id)==["a","c","d","b"])
        print("PASS Swift stable IDs, deduplication, grouping and metadata order")
    }
}
