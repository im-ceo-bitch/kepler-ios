#!/usr/bin/env bash
# Linux-compatible semantic check of the real catalogue model. Network and
# Combine/UI dependencies are replaced with local fixtures; not an iOS build.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/FlightBrowse.swift" <<'PY'
from pathlib import Path
import sys
root=Path('Sources')
def section(path, start, end=None):
    s=(root/path).read_text(); s=s[s.index(start):]
    return s[:s.index(end)] if end else s
model=section('Views/Flights/IumrahFlightBrowseCatalog.swift','@MainActor\nfinal class IumrahFlightBrowseModel')
local=section('Models/LocalJourneySelection.swift','struct LocalJourneyFlight','struct LocalJourneyRoom')
offer=section('Services/AviasalesFlightDiscoveryService.swift','struct FlightDiscoveryOffer','struct FlightDiscoveryCalendarDay')
curated=section('Models/CuratedFlightRecommendationModels.swift','struct CuratedFlightRecommendation:')
stubs='''import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
enum FlightCabinClass: String { case economy, business }
struct Filters { var cabinClass = FlightCabinClass.economy }
struct TripDraft { var originCode = "TAS"; var effectiveFlightFilters = Filters() }
struct AppSettingsStore { enum Language { case russian } }
enum IumrahPerformanceTrace { static func begin(_ name: String) -> Int { 0 }; static func end(_ name: String, _ trace: Int) {} }
enum NuiteeCopy { static func text(_ a: String, _ b: String, _ c: String, _ l: AppSettingsStore.Language) -> String { a } }
enum FlightReferenceCatalog { static func airlineName(code: String, fallback: String) -> String { fallback } }
enum IumrahFlightDiscoveryStore { static let dayFormatter = DateFormatter(); static let monthFormatter = DateFormatter() }
@MainActor final class CuratedFlightRecommendationService {
    static let shared = CuratedFlightRecommendationService()
    func load(trip: TripDraft, from: Date, days: Int) async throws -> [CuratedFlightRecommendation] { [] }
}
struct AviasalesFlightDiscoveryService {
    func offers(origin: String, destination: String, departure: String, direct: Bool, limit: Int) async throws -> (offers: [FlightDiscoveryOffer], currency: String, generatedAt: String?) { ([], "USD", nil) }
}
'''
segments=(root/'Services/FlightDiscoveryVerifiedSegment.swift').read_text()
Path(sys.argv[1]).write_text(stubs+'\n'+segments+'\n'+offer+'\n'+curated+'\n'+local+'\n'+model)
PY
swiftc -swift-version 5 -typecheck "$tmp/FlightBrowse.swift"
echo 'PASS: flight browse model semantic compilation (mocked UI/network dependencies)'
