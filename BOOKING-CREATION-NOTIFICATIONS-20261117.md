# Booking creation notifications — iOS V5

Cumulative client patch on V4. All three shared checkout callers forward `notificationIntent` with the existing quote-authorized booking creation envelope. The verified contact is collected using the existing OTP endpoints. Push permission is requested if undetermined, and the client waits up to 1.2 seconds for APNs after permission returns; denied/pending APNs does not prevent booking. The existing authenticated contact attachment and profile exchange remain in place. No local notification impersonates a remote delivery. No credentials are embedded; notification proof exists only in the request, not the booking profile or vault.

## Backend integration required (not deployed by this ZIP)

The existing create route receives an optional top-level `notificationIntent`:

```json
{
  "requestID": "stable UUID for checkout attempt",
  "event": "booking_created",
  "contactChannel": "sms or email",
  "contact": "normalized verified destination",
  "verificationToken": "opaque OTP proof",
  "locale": "ru",
  "pushDeviceToken": "optional APNs token",
  "pushEnvironment": "production",
  "appBundleID": "com.iumrah.app",
  "installationID": "existing notification installation identifier"
}
```

The authoritative backend must validate the existing OTP proof, scope, expiry and recipient, bind the contact to the canonical booking, and enqueue booking-created channel jobs durably with the booking transaction. Never trust the raw recipient or the client's event/price as authorization. Deduplicate booking creation by requestID scoped to verified identity and canonical quote; deduplicate events by bookingID/event/channel/destination. Derive email contents from the canonical stored booking (public package total, itinerary, hotel names and rooms, transfer, included services, dates, travelers count, booking number; no internal cost or passport data). SMS and APNs should carry the short summary plus safe booking navigation, not sensitive documents or access credentials. APNs payload type `booking_created`, bookingID canonical ID; optional pilgrimID, destination `booking`, destinationBookingID. Support late device registration and replay creation once to the authorized device; do not send duplicates on registration retries. Server must support the existing verified-phone/email attachment and profile exchange idempotently even when the proof was already bound at creation. Do not consume proof in a way that breaks these existing requests. Never persist raw OTP proof or log it. Use server-side delivery/outbox states, not client success as proof of delivery.

Older backend may ignore the new optional field; the existing contact attach still runs. The live backend acceptance and delivery behavior have not been tested. Do not automatically retry with a second create request on an ambiguous failure. Real SMS/email/remote push require Worker integration and provider configuration. No Android, web, Business, or workflow changes in this client ZIP.

## Tests
`bash scripts/test_booking_creation_notifications.sh` checks encoding via the actual extracted request declarations and static integration. Xcode/TestFlight and real APNs/SMS/email remain required.
