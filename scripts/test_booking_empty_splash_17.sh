#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
root=Path('Sources')
b=(root/'Views/Tabs/BookingsHomeView.swift').read_text()
a=(root/'AppShell/IumrahAccountView.swift').read_text()
l=(root/'App/IumrahLaunchExperience.swift').read_text()
s=(root/'App/IumrahSignatureLaunchLayer.swift').read_text()
r=(root/'Views/Booking/IumrahBookingAccessCard.swift').read_text()
store=(root/'State/BookingStore.swift').read_text()
e=b.split('private var emptyBookingHome: some View {',1)[1].split('private var bookingEmptyStatusCard',1)[0]
checks={
 'empty state skips obsolete promo modules':all(x not in e for x in ['emptyConfiguratorCard','emptyCareCard','IumrahTelegramEntryCard','explorePackagesButton']),
 'new trip CTA performs existing action':'startNewTrip()' in e,
 'booking lookup available': 'IumrahFindBookingView()' in e and 'initiallyExpanded: true' in r,
 'saved journey link retained':'SavedJourneysView()' in e,
 'account entry for logged-in users': 'compactAccountContent(profile)' in a and 'NavigationLink { IumrahFindBookingView() }' in a,
 'guest account lookup preserved':'compactGuestActions' in a and 'IumrahFindBookingView()' in a,
 'existing OTP access preserved':'startEmailLogin(' in r and 'confirmPhoneLogin(' in r,
 'static splash':'TimelineView' not in s and 'IumrahSignatureLaunchLayer()' in l,
 'no artificial splash delays':all(x not in l for x in ['Task.sleep','ContinuousClock','firstPulse','secondPulse','CHHapticEngine']),
 'one soft haptic':'IumrahHaptics.soft()' in l and l.count('IumrahHaptics.soft()')==1,
 'cold links preserved':'onOpenURL' in l and 'onContinueUserActivity' in l,
 'network failure is not empty': 'accountTripsRestoreState == .failed' in b and 'accountTripsRestoreState = .failed' in store,
 'server response distinguished from empty list': 'failedTripDetails && sessions.isEmpty ? .failed : .loaded' in store,
}
for label,passed in checks.items(): print(('PASS' if passed else 'FAIL')+': '+label)
assert all(checks.values())
PY
