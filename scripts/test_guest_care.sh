#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
swiftc Sources/Core/IumrahSeamlessBookingPolicy.swift Tests/IumrahGuestCarePolicySmoke.swift -o "$tmp/care"
"$tmp/care"
python3 - <<'PY2'
from pathlib import Path
r=Path('Sources')
store=(r/'State/BookingStore.swift').read_text()
care=(r/'Views/Tabs/CareHomeView.swift').read_text()
chat=(r/'Views/Chat/BookingChatView.swift').read_text()
root=(r/'Views/RootView.swift').read_text()
assert 'var canUseCareChat: Bool { defaultCareChatKey != nil }' in store
assert 'careScope(for: session) == bookingID' in store and '["x-booking-token": session.accessToken]' in store
assert 'guard !hasCareAccount else' not in store
assert 'registerBookingPushes(token:' in store and 'pushHeaderCandidates(for: session)' in store
assert 'BookingChatView(bookingID: key).id(key)' in care and 'BookingChatView(bookingID: "account")' not in care
assert 'bookings.canUseCareChat(for: requestedBookingID)' in chat
assert 'bookings.careChatKey(for: event) == bookingID' in chat
assert 'bookings.careChatKey(for: event)' in root
assert 'chatCacheKey(for: bookingID) == key' in store
print('PASS: static integration of guest chat, push registration, payload routing, credential-scoped cache')
PY2
