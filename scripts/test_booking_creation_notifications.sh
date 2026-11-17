#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
r=Path('Sources')
model=(r/'Models/BookingModels.swift').read_text()
intent=model.split('struct BookingCreationNotificationIntent: Encodable {',1)[1].split('\n}',1)[0]
envelope=model.split('struct BookingCreateEnvelope: Encodable {',1)[1].split('\n}',1)[0]
Path(sys.argv[1]).write_text('import Foundation\nstruct BookingDraftRequest: Encodable { let id: String }\nstruct BookingCreationNotificationIntent: Encodable {'+intent+'\n}\nstruct BookingCreateEnvelope: Encodable {'+envelope+'''\n}
func json(_ value: BookingCreateEnvelope) throws -> [String: Any] { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any] }
let legacy = try json(.init(lang: "ru", booking: .init(id: "example"), quoteProof: "quote"))
precondition(legacy["notificationIntent"] == nil)
for (channel, contact, device) in [("sms", "+998901234567", "aabb" as String?), ("email", "guest@example.test", nil)] {
    let intent = BookingCreationNotificationIntent(requestID: "test-request", event: "booking_created", contactChannel: channel, contact: contact, verificationToken: "test-proof", locale: "ru", pushDeviceToken: device, pushEnvironment: "production", appBundleID: "com.iumrah.app", installationID: "installation")
    let payload = try json(.init(lang: "ru", booking: .init(id: "example"), quoteProof: "quote", notificationIntent: intent))
    let n = payload["notificationIntent"] as! [String: Any]
    precondition(n["contactChannel"] as? String == channel)
    precondition(n["contact"] as? String == contact)
    precondition(n["verificationToken"] as? String == "test-proof")
    precondition(n["event"] as? String == "booking_created")
    precondition(n["pushDeviceToken"] as? String == device)
}
print("PASS: legacy envelope and two verified contact variants encoded using production model declarations")
''')
shared=(r/'Views/Booking/IumrahBookingConfirmationView.swift').read_text()
for p in ['Views/Package/FinalPackageView.swift','Views/Tabs/HotelStorefrontCompatibility.swift','Views/Booking/BookingCheckoutView.swift']:
 s=(r/p).read_text(); assert 'createBooking: { profile, notificationIntent in' in s and 'notificationIntent: notificationIntent' in s,p
assert shared.index('guard let verificationProof else') < shared.index('prepareBookingCreationToken()') < shared.index('createBooking(profile, intent)')
assert shared.index('createBooking(profile, intent)') < shared.index('attachVerifiedPhone(')
assert 'if let savedBooking { committed = savedBooking }' in shared
assert 'notificationIntent: notificationIntent' in (r/'Core/BookingDraftBuilder.swift').read_text()
assert 'notificationIntent: notificationIntent' in (r/'State/BookingStore.swift').read_text()
assert 'notificationIntent' not in model.split('struct StoredBookingSession:',1)[1]
assert 'canOpenBookingFromPush(id: bookingID)' in (r/'Views/RootView.swift').read_text()
assert 'guard isAuthorized else { return nil }' in (r/'Services/PushNotificationManager.swift').read_text()
print('PASS: all checkout routes, verified proof ordering, legacy attachment, safe routing, no proof in session storage (static)')
PY
swiftc "$tmp/main.swift" -o "$tmp/check"
"$tmp/check"
