#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -swift-version 5 Sources/Core/IumrahPerformancePolicy.swift Tests/IumrahPerformanceV3Smoke.swift -o "$tmp/policy"
"$tmp/policy"
# Test the real index functions with compact fixtures, not a second implementation.
python3 - "$tmp/HotelIndex.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/State/HotelStorefrontStore.swift').read_text()
def block(start):
    i=s.index(start); first=s.index('{',i); level=1; j=first+1
    while level:
        if s[j]=='{': level+=1
        elif s[j]=='}': level-=1
        j+=1
    return s[i:j]
functions=['buildPackagePriceIndex','groupHotelServerPackages','isUsableHotelFirstSnapshot','buildHotelQuoteIndexes','isValidHotelFirstGroup','isPublicPackageID','sortedHotelFirstSnapshots']
header='''import Foundation
struct HotelPackagePricePoint: Identifiable, Hashable { let id: String; let date: Date; let pricePerPersonUSD: Decimal; let isEstimated: Bool; let packageID: String }
enum PackageTier: Hashable { case economy, standard, comfort, luxury }
struct PackageQuote { let totalPackagePrice: Decimal; let pricePerPerson: Decimal; let currency: String; let isEstimated: Bool; let quoteId: String?; let quoteProof: String? }
struct HotelStorefrontQuote { let tier: PackageTier; let packageQuote: PackageQuote; let hotelNightlyUsd: Decimal; let hotelNights: Int; let rooms: Int; let travelers: Int; let flightFarePerTravelerUsd: Decimal }
struct HotelStorefrontService { static let hotelFirstEngineVersion = 6 }
struct StorefrontServerPackageSnapshot {
    struct Leg { let departureAt: String }
    struct Configuration { let rooms: Int; let adults: Int; let children: Int; let infants: Int }
    let id: String; let entryMode: String; let status: String; let currency: String
    let tier: PackageTier; let startDate: String; let pricePerPerson: Decimal?; let totalPackagePrice: Decimal?; let isEstimated: Bool
    let hotelFirstAnchorHotelId: String?; let makkahHotelId: String?; let madinahHotelId: String?
    let hotelFirstEngineVersion: Int?; let hotelFirstVariantIndex: Int?; let hotelFirstVariant: String?
    let hotelFirstVariantMinDays: Int?; let hotelFirstVariantMaxDays: Int?
    let outboundOfferId: String; let inboundOfferId: String; let outbound: Leg
    let totalDays: Int; let totalNights: Int; let configuration: Configuration?
}
enum IndexHarness {
'''
parts=[block('    private struct HotelQuoteIndexes').replace('private struct','struct')]
parts.extend(block('    nonisolated private static func '+name).replace('nonisolated private static','static',1) for name in functions)
Path(sys.argv[1]).write_text(header+'\n'.join(parts)+'\n}\n')
PY
cat > "$tmp/Test.swift" <<'SWIFT'
import Foundation
@main struct Main {
    static func main() {
        func variant(_ hotel: String, _ index: Int, _ price: Int, _ number: Int, date: String = "2026-12-10", status: String = "ready", currency: String = "USD", estimated: Bool = false, engine: Int = 6) -> StorefrontServerPackageSnapshot {
            .init(id: String(format: "%010d", number), entryMode: "hotel-first", status: status, currency: currency,
                  tier: .standard, startDate: date, pricePerPerson: Decimal(price), totalPackagePrice: Decimal(price * 2), isEstimated: estimated,
                  hotelFirstAnchorHotelId: hotel, makkahHotelId: hotel, madinahHotelId: nil, hotelFirstEngineVersion: engine,
                  hotelFirstVariantIndex: index, hotelFirstVariant: ["short", "balanced", "extended"][index], hotelFirstVariantMinDays: nil, hotelFirstVariantMaxDays: nil,
                  outboundOfferId: "out-\(hotel)", inboundOfferId: "in-\(hotel)-\(index)", outbound: .init(departureAt: date),
                  totalDays: 5 + index, totalNights: 4 + index, configuration: nil)
        }
        let a = (0..<3).map { variant("a", $0, 1200 + $0 * 100, 100 + $0) }
        let b = (0..<3).map { variant("b", $0, 950 + $0 * 100, 200 + $0, estimated: true) }
        let c = [variant("partial", 0, 100, 300)]
        let invalid = [variant("bad", 0, 0, 400), variant("bad", 1, 100, 401, status: "pending")]
        let differentDate = (0..<3).map { variant("later", $0, 1500, 500 + $0, date: "2026-12-20") }
        let oldEngine = (0..<3).map { variant("legacy", $0, 50, 600 + $0, engine: 5) }
        let duplicate = variant("a", 0, 1200, 100)
        let groups = IndexHarness.groupHotelServerPackages(a + b + c + invalid + differentDate + oldEngine + [duplicate])
        precondition(groups["a"]?.count == 3)
        precondition(groups["bad"] == nil)
        precondition(groups["partial"]?.count == 1)
        let index = IndexHarness.buildHotelQuoteIndexes(groups)
        precondition(index.prices.count == 2)
        precondition(index.prices[0].id == "2026-12-10")
        precondition(index.prices[0].pricePerPersonUSD == 950)
        precondition(index.prices[0].isEstimated)
        precondition(index.prices[0].packageID == "0000000200")
        precondition(index.prices[1].id == "2026-12-20")
        precondition(index.standard["partial"]?.packageQuote.pricePerPerson == 100)
        precondition(index.standard["bad"] == nil)
        let empty = IndexHarness.buildHotelQuoteIndexes([:])
        precondition(empty.prices.isEmpty && empty.standard.isEmpty)
        print("PASS: 12 actual Hotel First grouping, index, estimate and quote contract checks")
    }
}
SWIFT
swiftc -swift-version 5 "$tmp/HotelIndex.swift" "$tmp/Test.swift" -o "$tmp/index"
"$tmp/index"
