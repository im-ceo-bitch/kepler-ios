# iumrah — Booking confirmation email redesign (10 November 2026)

## What this patch changes

- Production Cloudflare Package Engine email renderer `src/booking-email.ts`, not a mock UI.
- 4 supported mail locales: RU, EN, UZ Latin, UZ Cyrillic.
- The first mail has an accurate **request received / checking availability** subject. It does **not** claim that flights, hotels, or payment have been confirmed.
- Trip length includes **days and nights**, using `booking.stay.totalDays/totalNights`; as a fallback, derives counts from validated start/end dates. Example: 14–17 November = **4 days / 3 nights**.
- Itinerary flight cards are built from the actual `booking.generatorTrace.outbound/inbound` already saved by iOS `BookingDraftBuilder`. Cards show available airlines, flight numbers, airport route, local airport departure/arrival times, verified stop count, duration, and multi-segment connections. **No fake flights or times are generated.** The prior concise `booking.flight` string remains a safe fallback for older bookings.
- Local flight times are translated using known IATA time zones for Uzbekistan and Saudi Arabia (otherwise explicitly shown with `UTC` to avoid mislabeling).
- Hotel cards retain their public HTTPS images from operational hotel data and now share the flight cards' visual styling.
- The email footer has support@iumrah.app and supports configured phone numbers (UZ, SA), Telegram, and WhatsApp. Any missing or invalid contact is hidden; no unverified contact is fabricated.
- Reuses original iOS AppIcon artwork as a publicly served sender avatar PNG at `/api/package/email-brand/avatar.png`. Existing email wordmark is at `/api/package/email-brand/logo.png`. **A Gmail inbox sender avatar is controlled by Gmail: the PNG resource alone does not activate BIMI.**
- Status notification workflow, Resend provider, idempotency, OTP security, database schema, and iOS screen code are unchanged.

## Install

Upload the root-level patch ZIP to the same iOS repository as the input `kepler-ios-main 7.zip` and unpack with the existing repository ZIP-applier. Patch paths start at `Backend/PackageEngine/...`; no extra `kepler-ios-main/` directory. No `.github/workflows/` edits are included.

Deploy the **Package Engine Worker** after the patch has been applied. An iOS TestFlight build is **not necessary** for these backend-only email template changes.

## Support contacts — must be configured by the owner

Set on the **existing** `iumrah-package-api` Cloudflare Worker under Settings > Variables and Secrets (as Worker secrets; do not put these values in the iOS app):

| Variable | Example value format | Effect |
|---|---|---|
| `BOOKING_SUPPORT_PHONE_UZ` | `+998 XX XXX XX XX` | Uzbekistan phone / tap to call |
| `BOOKING_SUPPORT_PHONE_SA` | `+966 XX XXX XXXX` | Saudi phone / tap to call |
| `BOOKING_SUPPORT_TELEGRAM` | `@your_support_username` or `https://t.me/your_support_username` | Open support chat in Telegram |
| `BOOKING_SUPPORT_WHATSAPP` | `+998 XX XXX XX XX` | Open WhatsApp chat |

These settings are optional but **a support number is shown only if a real number has been supplied**. A Telegram CTA still points to the booking/app area when no direct support username is configured, consistent with the existing booking linking workflow. All links are validated and HTML-escaped.

Email support is always `support@iumrah.app`; the booking CTA is `https://iumrah.app/booking`. Keep the existing `RESEND_API_KEY`, `ACCOUNT_EMAIL_FROM`, `ACCOUNT_EMAIL_REPLY_TO` Cloudflare secrets/configuration.

## Inbox sender avatar (requires mail-domain DNS/admin access)

1. The actual app icon is now available after deployment at `https://iumrah.app/api/package/email-brand/avatar.png`, suitable as an official brand image source for downstream setup. It is **not** a certified BIMI SVG.
2. Confirm the sending domain is verified with Resend and set SPF, DKIM, and **DMARC at enforcement** (`p=quarantine` or `p=reject`, meeting the mailbox provider's requirements).
3. Convert/prepare a compliant BIMI SVG Tiny PS based on the official brand asset and obtain a VMC/CMC if required by the mailbox provider. Host it over HTTPS and publish the BIMI DNS TXT record pointing to the actual hosted SVG and certificate where applicable. Do not use a guessed SVG URL or certificate.
4. Validate DNS and message authentication and check display in Gmail/Apple Mail. **Inbox avatar display cannot be guaranteed in each client** even after proper setup. The email's internal logo works independently of BIMI.

## Tests run locally

- `tsc --noEmit`: PASS.
- `bash scripts/runtime-tests.sh`: **45/45 PASS**, including new real-payload itinerary card, i18n, local airport times, HTML safety, support links, avatar PNG and existing mail/OTP lifecycle tests.
- Full static contracts `node --test test/*.test.mjs`: **140/145 PASS**. The five failures check old Swift UI behavior in files untouched by this patch (`FinalPackageView.swift`, `RootView.swift`, and account / booking views). They are unrelated pre-existing contract drift in the supplied source. The standard deploy workflow runs `npm test`, so those failures must be reconciled before the existing workflow can reach deploy. This patch does not bypass CI or change unrelated iOS UI to satisfy stale assertions.
- Xcode and live Cloudflare/Resend sending were **not** run here.

## Changed files

- `Backend/PackageEngine/src/booking-email.ts`
- `Backend/PackageEngine/src/booking-email-avatar.ts` (new)
- `Backend/PackageEngine/src/env.ts`
- `Backend/PackageEngine/src/index.ts`
- `Backend/PackageEngine/scripts/runtime-tests.sh`
- `Backend/PackageEngine/test/booking-email-design.runtime.mjs` (new)
- `Backend/PackageEngine/test/guest-booking-email.runtime.mjs` (initial email subject test updated)
- `IUMRAH_BOOKING_EMAIL_REDESIGN_20261110.md` (this file)
