# iumrah iOS — OTP-only account entry (2026-10-14)

## Scope

**Client (iPhone/iPad)**

- `Account > Sign in`: SMS (+998 DevSMS) or email (Resend) -> one-time six-digit code -> server-issued session. No password inputs or iumrah ID login selection.
- `Account > Register`: SMS/email -> verification code -> create the canonical account -> persist the verified auth response in Keychain; no password creation/re-entry.
- `Booking > Status > Activate`: email/SMS code only; no iumrah ID/password activation form.
- `Booking > Status > Existing account`: email/SMS code only, then explicit link to the booking; no password login. Apple/Google unchanged.
- The permanent eight-digit iumrah ID remains visible as an **account identifier**. It is not an authentication factor.

**Server (Cloudflare PackageEngine, D1)**

- Adds `POST /api/package/client/account/login/email/start` with `{email,locale}`; response `{ok,challengeID,expiresAt}`.
- Adds `POST /api/package/client/account/login/email/confirm` with `{challengeID,code,device}`; response `{ok,account,session}`.
- Email login is permitted ONLY when the email is already **verified and linked to the same activated account** (`iumrah_client_account_emails`, `verified_at` and `iumrah_accounts`). The unverified `pilgrims.email` field cannot be used to take over an account.
- Existing email challenge infrastructure is reused (`purpose='verify_email'`) because the D1 schema allows that purpose, and verification is additionally bound to an already-verified email/address/account tuple. Challenge codes are hashed, one-time, expire in 10 minutes, and are subject to rate and attempt limits.
- Four OTP-completion routes (`activate/email/confirm`, `activate/sms/confirm`, `register/email/confirm`, `register/sms/confirm`) no longer require a supplied password. To keep the existing non-null credentials schema backwards compatible, when no password is supplied the server generates a fresh high-entropy **unrecoverable internal credential** that is neither returned to the user nor used by the new OTP clients. Existing legacy clients that send passwords still behave as before.
- Apple/Google login, session persistence, account-linked bookings, security/device controls, and legacy password routes remain intact for compatibility. No migration is required.

## Delivery order

1. **Deploy Cloudflare PackageEngine first** (existing D1 migration set unchanged). Verify `RESEND_API_KEY`, `ACCOUNT_EMAIL_FROM`, `DEVSMS_API_TOKEN` and provider delivery permissions in the deployed environment; the ZIP cannot validate production secrets or sender verification.
2. Only after successful API deployment, apply the iOS changes and run GitHub Actions **TestFlight**.
3. Verify on actual iPhone/iPad with a TEST account: SMS sign-up -> SMS sign-in, email sign-up -> email sign-in, legacy account OTP sign-in via verified email/phone, booking-linked activation, existing account booking link, wrong/expired/reused code, resend/rate-limiting, App Store session restoration, and Apple/Google.

## Important behavior

- A legacy account whose email exists ONLY in the old `pilgrims.email` field, **without a verified linked email**, cannot authenticate using the new email OTP entry until the email is verified and attached through a trusted existing authentication/verification flow. This avoids taking over someone else's bookings through an unverified address. SMS/Apple/Google remain available if configured.
- SMS OTP currently supports +998 Uzbekistan numbers only. Other countries should use email, Apple or Google.
- This archive is a patch against the latest available local iOS source composite (`kepler-ios-main.zip` plus previous updates through 2026-10-14). Do not blindly overwrite newer GitHub `main` files without diffing.
- Syntax parsing on Linux is **not** Xcode compilation. A successful iOS archive/TestFlight upload is not confirmed here.

## Local validation

- Swift parser: full project source scan.
- TypeScript `tsc --noEmit`.
- Node source contracts and runtime production tests.
- Dedicated 5-case passwordless entry contract checks.
- ZIP integrity and relative path validation.
