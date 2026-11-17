#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
s=Path('Sources/Views/Package/FinalPackageView.swift').read_text()
start=s.index('private enum FinalPackageFlightGate {')
end=s.index('private enum ConfiguratorBookingError',start)
assert 'flightSelectionReady &&' in s
assert 'guard flightSelectionReady else' in s
assert 'fresh.bookingAllowed == true, acceptedInput == journey.localBookingInputKey, canBook' in s
assert 'fresh.totalPackagePrice == acceptedTotal' in s
Path(sys.argv[1]).write_text('import Foundation\n'+s[start:end]+'''
let curated = "curated:published-123"
let avia = "aviasales:ow:JED:TAS:2026-12-16:-:XY:123:-:-"
let mixed = "mixed:" + curated + "~" + avia
let now = Date()
func flight(_ id: String, _ direction: FlightDirection, _ origin: String, _ destination: String, _ source: String, _ identity: String, _ offset: Double = 0) -> FlightOffer {
    FlightOffer(id:id, direction:direction, airline:"Flynas", flightNumber:"XY 123", origin:origin, destination:destination,
                departureAt:now.addingTimeInterval(86400 + offset), arrivalAt:now.addingTimeInterval(100800 + offset),
                stops:0, durationMinutes:240, totalPackagePrice:100, currency:"USD", sourceLabel:source,
                fareAmount:100, fareScope:.perPassenger, fareObservedAt:now, providerItineraryID:identity)
}
func quote(_ allowed: Bool = true, _ id: String = "server-123", _ proof: String? = "sealed") -> PackageQuote {
    var q = PackageQuote(totalPackagePrice:5110, pricePerPerson:2555, currency:"USD", isEstimated:false, quoteId:id, quoteProof:proof)
    q.bookingAllowed = allowed
    return q
}
let out = flight("out", .outbound, "TAS", "MED", "iumrah Published", mixed)
let back = flight("back", .inbound, "JED", "TAS", "Aviasales Data", mixed, 86400 * 6)
func ready(_ out: FlightOffer? = out, _ back: FlightOffer? = back, _ q: PackageQuote? = quote(), _ id: String? = mixed, _ local: Bool = true, _ round: Bool = true, _ ids: [String] = ["out", "back"]) -> Bool {
    FinalPackageFlightGate.ready(outbound:out, inbound:back, roundTrip:round, usesLocalJourney:local, mixedIdentity:id, localFlightIDs:ids, quote:q)
}
var count = 0
func check(_ value: Bool, _ description: String) {
    precondition(value, description); count += 1; print("PASS: " + description)
}
check(!out.isVerifiedForBooking && !back.isVerifiedForBooking, "reproduce original mixed display records rejected by generic gate")
check(ready(), "server-confirmed mixed journey with distinct Saudi airports is bookable")
let reversed = "mixed:" + avia + "~" + curated
check(ready(flight("out", .outbound, "TAS", "MED", "Aviasales Data", reversed), flight("back", .inbound, "JED", "TAS", "iumrah Published", reversed, 86400*6), quote(), reversed), "reverse supplier order")
check(!ready(out, back, nil), "missing quote rejected")
check(!ready(out, back, quote(false)), "non-bookable quote rejected")
check(!ready(out, back, quote(true,"estimate-123")), "non-server quote rejected")
check(!ready(out, back, quote(true,"server-123",nil)), "missing proof rejected")
check(!ready(out, back, quote(true,"server-123","  ")), "blank proof rejected")
check(!ready(out, nil), "missing return rejected")
check(!ready(out, back, quote(), mixed, false), "mixed exception restricted to local journey")
check(!ready(out, back, quote(), mixed, true, false), "mixed exception restricted to round trip")
check(!ready(out, back, quote(), mixed, true, true, ["different", "back"]), "different selected flight rejected")
check(!ready(out, flight("back", .inbound, "JED", "SKD", "Aviasales Data", mixed, 86400*6)), "incompatible return airport rejected")
check(!ready(out, flight("back", .inbound, "JED", "TAS", "iumrah Published", mixed, 86400*6)), "wrong supplier label rejected")
check(!ready(out, flight("back", .inbound, "JED", "TAS", "Aviasales Data", reversed, 86400*6)), "different provider identity rejected")
check(!ready(out, flight("back", .inbound, "JED", "TAS", "Aviasales Data", mixed, -86400)), "return before outbound rejected")
let ordinary = flight("ordinary", .outbound, "TAS", "MED", "Aviasales Data", "aviasales:ow:TAS:MED:2026-12-13:-:XY:123:-:-")
check(ordinary.isVerifiedForBooking && ready(ordinary, nil, nil, nil, false, false, []), "ordinary Aviasales validation unchanged")
check(!ready(out, back, quote(), nil), "unidentified mixed records still rejected by ordinary gate")
print("\\(count)/\\(count) executable checks passed")
''')
PY
swiftc Sources/FlightEngine/FlightSearchRequest.swift Sources/Models/FlightModels.swift Sources/FlightEngine/FlightReferenceCatalog.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
