#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
r=Path('Sources')
flow=(r/'Views/SmartConfigurator/SmartConfiguratorFlow.swift').read_text()
store=(r/'Views/SmartConfigurator/SmartConfiguratorStore.swift').read_text()
flight=(r/'Views/Flights/IumrahGuidedFlightSelectionView.swift').read_text()
hotel=(r/'Views/Hotels/NuiteeJourneyHotelsView.swift').read_text()
passport=(r/'AppShell/IumrahTravelerProfileView.swift').read_text()
hub=(r/'Views/Booking/IumrahBookingPassportsView.swift').read_text()
checkout=(r/'Views/Booking/PilgrimCheckoutView.swift').read_text()
service=(r/'Services/IumrahAccountService.swift').read_text()
checks={
 'flight editor returns to Smart': 'if let smartConfirm { smartConfirm() } else { showHotelPicker = true }' in flight,
 'Smart keeps guest composition in flight search': 'lockParty: smartConfirm != nil' in flight and 'next.trip.adults == previous.trip.adults' in store,
 'hotel editor targets only chosen city and uses real star picker': 'smartCity.map { [$0] }' in hotel and 'ForEach(1...5' in hotel,
 'hotel editor preserves child ages': '_ages = State(initialValue: smartChildAges)' in hotel and 'guard smartCity == nil else { return }' in hotel and 'journey.tripSummaryChildAges != value' in hotel,
 'hotel confirmation returns to Smart': 'if let smartConfirm { smartConfirm(); return }' in hotel,
 'isolated edit journey': 'let next = JourneyStore()' in store and 'next.localJourneyRooms = previous.localJourneyRooms' in store,
 'new price before replacing result': store.index('await next.buildQuote()',store.index('func applyEdit')) < store.index('result = next',store.index('func applyEdit')),
 'old rooms refreshed on changed dates': 'refreshPreviousRooms(old, window: window' in store and 'hotelsChangedWithFlights' in flow,
 'transfer photos and capacity': 'TripSummaryVehicleOverview(vehicle: vehicle' in flow and 'Image(vehicle.assetName)' in (r/'Views/Package/TripSummarySupport.swift').read_text() and 'vehicle.passengerCapacity < candidate.trip.travelerCount' in flow,
 'passport-only booking views': 'passportOnly: true' in hub and 'passportOnly: true' in checkout and 'if !passportOnly { manualCard }' in passport,
 'passport upload verifies identity and response': 'guard hasVerifiedAccess, let token = account.bearerToken' in passport and 'guard response.ok else' in service,
 'passport progress uses uploads': 'value.travelers.filter(\\.hasPassport).count' in checkout,
 'Smart orbit does not collapse on ready': 'mergeToCenter: false, pinRevealDuration: 1.2' in flow and 'pinnedSymbol: step == .assembly ? nil' in flow,
 'booking blocked while reprice pending': 'store.busy || store.replacingCity != nil || pendingEdit != nil' in flow,
}
for name, ok in checks.items():
 print(('PASS' if ok else 'FAIL') + ': ' + name)
assert all(checks.values())
print(f'{len(checks)}/{len(checks)} static integration checks passed')
PY
