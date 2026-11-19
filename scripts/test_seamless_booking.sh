#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc Sources/Core/IumrahSeamlessBookingPolicy.swift Tests/IumrahSeamlessBookingPolicySmoke.swift -o "$tmp/policy"
"$tmp/policy"
python3 - <<'PY'
from pathlib import Path
r=Path('Sources')
shared=(r/'Views/Booking/IumrahBookingConfirmationView.swift').read_text()
for p in ['Views/Package/FinalPackageView.swift','Views/Tabs/HotelStorefrontCompatibility.swift','Views/Booking/BookingCheckoutView.swift']:
 assert 'IumrahBookingConfirmationView(quote:' in (r/p).read_text(), p
smart=(r/'Views/SmartConfigurator/SmartConfiguratorFlow.swift').read_text()
assert 'FinalPackageView(onBack:' in smart and '.environmentObject(journey)' in smart
assert shared.index('attachVerifiedEmail(')<shared.index('exchangeProfile(')
assert shared.index('linkBooking(bookingID:')<shared.index('acceptVerifiedSession(auth')
assert 'if let savedBooking { committed = savedBooking }' in shared
status=(r/'Views/Booking/PilgrimCheckoutView.swift').read_text().split('private func checkoutContent',1)[1].split('private var availabilityPaymentLockedCard',1)[0]
assert 'if accountMatchesTrip' in status and 'IumrahBookingAccessCard' in status
assert 'activationCard(checkout)' not in status and 'loginCard(checkout)' not in status
profile=(r/'AppShell/IumrahAccountView.swift').read_text().split('var body: some View',1)[1].split('private var accountHeader',1)[0]
assert 'seamlessGuestProfile' in profile and 'IumrahBookingAccessCard(bookingID: nil)' in profile
assert 'loginCard\n' not in profile
root=(r/'Views/RootView.swift').read_text().split('private func linkLocalBookingsToAccount()',1)[1].split('private func syncLocalProfileFromAccount()',1)[0]
assert 'sameIdentity(owner, current)' in root
access=(r/'Views/Booking/IumrahBookingAccessCard.swift').read_text()
assert 'guard isMissingProfile(error), let target, !target.accessToken.isEmpty' in access
assert access.index('linkBooking(bookingID:')<access.index('acceptVerifiedSession(auth')
print('PASS: shared checkout, verified ownership, no signup cards, guarded recovery (static integration checks)')
PY
