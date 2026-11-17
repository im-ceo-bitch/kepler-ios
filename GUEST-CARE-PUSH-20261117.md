# Guest Care + APNs cumulative V4

Base: kepler-ios-main 7.zip + cumulative V3 (Smart, passports, Seamless Booking).

## Fixed in the client
- The legacy `hasCareAccount && active booking` gate incorrectly excluded guest reservations. A non-closed booking with its own server-issued proof now resolves to the booking-scoped chat. An authenticated account uses the unified account chat only for a matching owner. Missing credentials, unrelated profiles, and closed trips remain blocked. The server continues to authorize every request.
- Care header, hero CTA, trip entry and push deep links resolve an actual chat scope, rather than always opening `account`. Account-level events without a proven mapping do not open arbitrary bookings. Guest event owner IDs are checked against the local booking; leading zeros are normalized.
- Booking APNs registration no longer exits early for an authenticated account. Register each authorized reservation with its own proof or matching profile bearer; retain installation-level notification registration. Serialize overlapping registration requests and reject false `ok` responses. Existing production APNs environment retained.
- Chat caches remain credential-scoped; asynchronous results are rejected if the scope changes. Chat reloads when its mapped push arrives and on the existing polling loop.

## Production verification still required
Current unified Worker and Business source are not in this iOS archive. The old embedded PackageEngine is not the production Worker; do not deploy it. Confirm the real Worker accepts `x-booking-token` on `/api/catalog/hotels/client/chats/{bookingID}/messages` and attachments, and returns the same authorized conversation Business writes to. If messages are stored only under a canonical pilgrim thread, resolve guest booking to that thread server-side, after checking ownership. Confirm `/api/catalog/hotels/client/push/devices` persists booking/owner and current APNs token, and installation registration does not overwrite booking subscriptions. Check APNs provider credentials, production topic, response reason, delivery and deep link with a real TestFlight install. Do not make the guest client call an account route without valid account authorization. No live Worker changes or APNs delivery tests performed.

Tests: 16 guest routing runtime checks, 12 Seamless policy checks, 14 Smart static checks, hotel decoding compatibility, Swift syntax parse. No Xcode build or real device test possible in Linux. No workflow changes.
