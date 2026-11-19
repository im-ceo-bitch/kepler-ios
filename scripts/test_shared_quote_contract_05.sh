#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/main.swift" <<'SWIFT'
import Foundation
let sample = """
{"version":"trip-summary-v2","currency":"USD","components":[{"code":"flight_roundtrip","label":"Flight","amountUsd":1098},{"code":"makkah_hotel","label":"Hotel","amountUsd":360.36},{"code":"madinah_hotel","label":"Hotel","amountUsd":928.86},{"code":"visa","label":"Visa","amountUsd":240},{"code":"transfers","label":"Transfer","amountUsd":473.72},{"code":"accompaniment","label":"Guide","amountUsd":400},{"code":"ziyarat_makkah","label":"Ziyarat","amountUsd":100},{"code":"ziyarat_madinah","label":"Ziyarat","amountUsd":100}],"servicesSubtotalUsd":3700.94,"supportRate":0.09,"supportAmountUsd":333.08,"paymentRate":0.02,"paymentAmountUsd":82.4,"roundingUsd":3.58,"totalUsd":4120,"perPilgrimUsd":2060}
"""
func check(_ ok: Bool, _ name: String) { precondition(ok,name); print("PASS: " + name) }
let decoder=JSONDecoder()
let q=try decoder.decode(TripSummaryPublicPrice.self,from:Data(sample.utf8))
check(q.reconciles(with:4120),"verified quote reconciles to the cent")
check(!q.reconciles(with:4121),"reject mismatched final total")
for (from,to) in [("82.4","82.33"),("333.08","333.09"),("473.72","473.73"),("ziyarat_madinah","ziyarat_makkah"),("0.09","0.10")] {
 let bad=try decoder.decode(TripSummaryPublicPrice.self,from:Data(sample.replacingOccurrences(of:from,with:to).utf8))
 check(!bad.reconciles(with:4120),"reject corrupted pricing field " + from)
}
SWIFT
swiftc Sources/FlightEngine/FlightSearchRequest.swift Sources/Models/FlightModels.swift Sources/FlightEngine/FlightReferenceCatalog.swift "$tmp/main.swift" -o "$tmp/test"
"$tmp/test"
python3 - <<'PY'
from pathlib import Path
s=Path('Sources/State/JourneyStore.swift').read_text()
r=Path('Sources/Services/RemotePackageEngineClient.swift').read_text()
f=Path('Sources/Views/Package/FinalPackageView.swift').read_text()
m=Path('Sources/Views/Package/IumrahManualPackageView.swift').read_text()
a=Path('Sources/Views/SmartConfigurator/SmartConfiguratorStore.swift').read_text()
checks={
 'single-flight pricing requests': 'if quoteTaskKey == key, let task = quoteTask { await task.value; return }' in s and 'quoteTask?.cancel()' in s,
 'stale local results guarded': 'revision == packageQuoteRevision, localBookingInputKey == identity, !Task.isCancelled' in s,
 'stale catalog results guarded': 'revision == packageQuoteRevision, trip == tripForQuote, !Task.isCancelled' in s,
 'no 15-second quote deadline': 'timeoutInterval: 180' in r and 'nuiteeRooms == nil ? 15' not in r,
 'optional calendar cannot discard valid price': 'itineraryPreview = try? c.decodeIfPresent' in r,
 'shared review refuses booking without breakdown': 'journey.hasFinalGeneratorQuote && publicPrice != nil' in f,
 'missing breakdown can be refreshed': 'journey.quote?.tripSummary == nil' in f and 'PACKAGE_PRICE_BREAKDOWN_MISSING' in f,
 'manual exposes quote failure': 'pricedJourney?.errorMessage ?? estimateError' in m,
 'Smart exposes quote failure': 'journey.errorMessage ?? "SMART_QUOTE_UNAVAILABLE"' in a,
}
for n,ok in checks.items(): print(('PASS: ' if ok else 'FAIL: ')+n)
assert all(checks.values())
PY
