# iumrah — guest booking Email/SMS confirmation and transactional emails (2026-10-16)

## User-facing behavior

- **Hotels First, Flight First and Configurator** all share `IumrahBookingConfirmationView`.
- Full-page passport name → surname → a **native SMS / Email segmented control** → six-digit OTP. No account login or password is created.
- Guest SMS remains on `booking-contact/sms/*`. Email uses new `booking-contact/email/start|confirm` routes and a verified-email attach route authorized by the original booking token.
- On completion, the page displays the booking confirmation, **indicative total + per-person price**, availability recheck and no-payment notice, and optional Telegram connection using the existing secure Telegram integration.
- Email is sent **only to an address whose guest OTP was verified**, and only for a booking linked using its access token.

## Emails

Status templates (Russian, English, Uzbek Latin, Uzbek Cyrillic):

1. `new` / `availability_check` → booking confirmed **as a request**, components still under availability recheck, **payment not yet accepted**.
2. `payment_pending` → availability confirmed, payment and passport-data stage.
3. `paid` / `booking_confirmed` → payment received and booking confirmed.
4. `documents_ready` / `ready_to_travel` → documents ready (view securely in booking, not via exposed email attachments).
5. `in_trip` → travelling.

The email includes a real booking ID / 4-digit number when available from `pilgrim_trips`, pilgrim, tier, nights/days, travelers, **total USD and USD per traveler**, flight, hotels, and photos when available as public HTTPS image URLs from the booking snapshot or hotel records. No hotel image or price is manufactured when missing. Prices remain **indicative** unless an explicitly confirmed final price is stored in the operational trip record.

HTML email branding uses the existing iOS Asset `LaunchWordmark` converted to a public `/api/package/email-brand/logo.png` Worker route. Templates also include a text/plain fallback, a Telegram CTA (which opens the iumrah booking area; real Telegram linking still requires user authorization in the app), a booking button, support email, domain, and a branded footer. No passport document is attached.

The sending address uses the pre-existing `RESEND_API_KEY`, `ACCOUNT_EMAIL_FROM`, and `ACCOUNT_EMAIL_REPLY_TO` settings in the **Cloudflare Package Engine Worker**; there is no new provider. The email OTP is independent of existing account email OTP: separate challenges, salt+PBKDF2 hashes, 10 minute expiry, max 5 attempts, throttling, and 15-minute single-booking verification proof.

## Delivery and status updates

The Cloudflare Worker now has an additional cron schedule **every five minutes**. It checks verified-email bookings against both operational `pilgrim_trips.status` and `bookings.status`. It sends one email per distinct recognized status, with optimistic per-booking leases and Resend idempotency keys; temporary failures remain retriable. The existing daily flight-cache cleanup cron remains intact. There is no new Business status UI or independent booking database.

## Installation

1. Apply this single root ZIP to the **iOS + Package Engine repository**. Do not upload it to the separate website repository.
2. Verify `RESEND_API_KEY` is bound to the deployed **Package Engine Worker** and its sender address is verified in Resend. If email codes are already sent by the Package Engine with these credentials, no new API key is needed. Do **not** expose credentials to the iOS client, HTML, or `NEXT_PUBLIC_*` values.
3. Run **Deploy iumrah Package Engine**; this deploys the two new email routes, email logo, and five-minute cron. The email challenge/subscription D1 tables are created idempotently via code and do not require destructive migrations.
4. Run the **TestFlight build**. Full signed compilation must pass before a production release.
5. Test genuine SMS OTP, email OTP, wrong/expired/reused code, attached booking, duplicate taps, initial email, email status changes through Business, and Telegram opt-in. Check email rendering in Apple Mail, Gmail, dark mode, and image-blocking mode.

### Important limitations

- `xcodebuild` **cannot run** in this Linux container; Swift syntax parsing is not proof of a successful iOS build. No real Resend or DevSMS message was sent by these tests.
- Sender avatar/logo **in the inbox** is controlled by mail clients; SPF/DKIM/DMARC and possibly BIMI are required and even then display isn't guaranteed. The logo **inside** the email is implemented.
- Telegram bot cannot initiate a conversation from an email or phone number alone. The existing in-app connect card must complete the actual bot linking, and the email's Telegram CTA is a navigation entry, **not automatic subscription**.
- App push requires a registered device and notification permission; email verification alone does not grant push permission.
- The booking-status CTA opens the public booking area. Do not expose access tokens or passport data in email URLs.
- The patch was applied against the most recently available full iOS repository plus the previous booking-confirmation patch. It has **not** been diffed against the live GitHub `main` branch.

## Local checks

- 266 Swift files parsed successfully.
- TypeScript strict typechecking passed.
- Existing 126 backend contract tests passed.
- 26 runtime tests passed, including the guest-email OTP, linked booking, 4-digit number, and 5 status notifications.
- ZIP integrity check passed.
