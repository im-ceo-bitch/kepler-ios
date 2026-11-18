#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
r=Path('Sources')
f=(r/'Views/SmartConfigurator/SmartConfiguratorFlow.swift').read_text()
s=(r/'Views/SmartConfigurator/SmartConfiguratorStore.swift').read_text()
v=(r/'Views/Package/FinalPackageView.swift').read_text()
h=(r/'Views/Tabs/HotelStorefrontCompatibility.swift').read_text()
j=(r/'State/JourneyStore.swift').read_text()
checks={
 'review navigation uses validated retained journey': 'guard store.reviewReady, let journey = store.result else { return }' in f and 'if showReview, let journey = reviewJourney' in f and 'reviewJourney = journey; showReview = true' in f,
 'review gets all explicit environment stores': all(x in f for x in ['.environmentObject(settings).environmentObject(bookings)', '.environmentObject(chrome).environmentObject(account)']),
 'one compact hotel card per city': 'ForEach(store.roomCities' in f and 'TripSummaryHotelOverview(rooms: rooms' in f and 'ForEach(Array(rooms.enumerated())' in (r/'Views/Package/TripSummarySupport.swift').read_text(),
 'hotel card shows verified full city total': 'store.hotelTotal(city: city)' in f and 'price.totalUsd == quote.totalPackagePrice' in s,
 'Smart preview refreshes after sealed quote': 'result = journey; progress = .ready\n            syncReview()' in s,
 'adult-only minimum, supplier room fallback': 'trip.rooms = max(1, (adults + 4) / 5)' in s and 'for count in minimum...fallback' in s,
 'readiness guards matching room dates and party': 'rooms.reduce(0) { $0 + $1.adults } == journey.trip.adults' in s and '$0.checkin == window.checkIn && $0.checkout == window.checkOut' in s,
 'review lazy sections and runtime metadata isolation': 'LazyVStack(alignment: .leading, spacing: 16)' in v and all('AnyView('+x+')' in v for x in ['compactFlights','compactHotels','compactServices','priceBreakdownCard','itineraryCard','summaryActions','reviewSheets','reviewDetailSheets','reviewNavigation']),
 'Smart and shared flight card agree on departure airport timezone': 'IumrahFlightClock.local(leg.departureAt, airport: leg.origin)' in h and 'TripSummaryFlightOverview(offer: flight' in f and 'FlightReferenceCatalog.timeZone(for: code)' in (r/'Views/Package/TripSummarySupport.swift').read_text(),
 'malformed mixed provider identity cannot cause index trap': 'providerIDs.count == 2' in j and 'providerIDs[index]' in j,
}
for k,ok in checks.items(): print(('PASS: ' if ok else 'FAIL: ')+k)
assert all(checks.values())
clock=(r/'Views/Flights/IumrahFlightResultCard.swift').read_text().split('enum IumrahFlightClock {',1)[1].split('\nstruct IumrahFlightFilterState:',1)[0]
models=(r/'Models/NuiteeHotelModels.swift').read_text().split('\nstruct NuiteeHotelListEnvelope:',1)[0]
Path(sys.argv[1]).write_text('import Foundation\nenum IumrahFlightClock {'+clock+'\n'+models+'''
func check(_ ok: Bool, _ message: String) { precondition(ok, message); print("PASS: " + message) }
let departure = "2026-11-29T11:40:00Z"
check(IumrahFlightClock.time(IumrahFlightClock.local(departure, airport:"JED")) == "14:40", "Jeddah departure is 14:40 local")
check(IumrahFlightClock.time(IumrahFlightClock.local(departure, airport:"TAS")) == "16:40", "Tashkent device zone must not replace Jeddah time")
check(IumrahFlightClock.local("2026-11-29T22:30:00Z", airport:"JED").hasPrefix("2026-11-30"), "local date rollover")
func hotel(_ stars: Double?) -> NuiteeHotel { .init(id:"h",name:"Hotel",city:"makkah",address:nil,stars:stars,rating:nil,reviewCount:nil,coverImageURL:nil,previewImages:nil,latitude:nil,longitude:nil,minimumRate:nil) }
check(hotel(4).roundedStars == 4 && hotel(4.6).roundedStars == 5, "valid star rating unchanged")
check(hotel(.nan).roundedStars == 0 && hotel(.infinity).roundedStars == 0 && hotel(1e100).roundedStars == 0 && hotel(-3).roundedStars == 0 && hotel(nil).roundedStars == 0, "invalid supplier star rating cannot trap")
''')
PY
swiftc Sources/FlightEngine/FlightSearchRequest.swift Sources/Models/FlightModels.swift Sources/FlightEngine/FlightReferenceCatalog.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
