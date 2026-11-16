# Seamless Booking — iOS client and unified backend integration contract

**Source:** kepler-ios-main 7.zip + smart-compact-ux-v1. The active API base is the unified iumrah-backend Worker. The `Backend/PackageEngine` tree shipped with iOS is explicitly superseded by Unified Core V8; do not deploy it.

## iOS changes
- Shared `IumrahBookingConfirmationView` for FinalPackageView (Smart and manual), storefront, BookingCheckoutView. Fixed CTA, compact orbit, quote display if non-estimated, first/last name and verified notification contact. Existing guest SMS/email OTP and booking creation flow remain. Contact is attached using its existing verified proof. The app tries a profile exchange only after successful attachment. A failed exchange does not recreate or invalidate the reservation.
- Server-issued profile session and booking link are accepted only after returned canonical IDs match. Existing signed-in profiles retain their session. No account credentials are generated or stored by the client. Existing Keychain vaults are used.
- Profile tab: no sign-in/signup pills or registration form. Locally available guest trip information and recovery by email/SMS. Availability-check status does not request activation. Protected payment/passport/document UI remains gated by the verified server session and owner ID. Recovery uses existing OTP login; only an explicit known-profile-not-found response plus a local booking token may fall back to the old passwordless booking activation API. No registration form or password is shown. No blind merging of local trips into another profile.
- Old server fallback: if `/booking-session` is not deployed, a completed booking remains visible and the user can confirm access by OTP when needed. Previously unactivated bookings on another device may not be recoverable by legacy login alone. This is a transitional mode, not the final single-OTP backend behavior.
- Old auth views are retained as unused compatibility code, not rendered by the updated profile or booking status pages. No signing/workflow or server origin change.

## Actual unified backend integration required (NOT deployed here)
`booking-session-reference.patch` is a typechecked reference diff against the archived PackageEngine account security module. It is **not** a patch for the live unified Worker. Port the function into the current unified Worker, mapping its real DB bindings, auth/session and ownership functions, and adapt as necessary. Never deploy the old Worker. The current Business backend repo was not supplied. The reference is intentionally not applied to the old source inside this ZIP.

### Contract
`POST /api/package/client/account/booking-session`
Header `x-booking-token`: opaque booking proof. JSON: `{ bookingID, verificationToken, channel: "email" | "sms", device }` (existing device registration shape). Successful response is the existing `IumrahAccountAuthResponse`: `{ok:true, account:{iumrahID,displayName,firstName,lastName,phone,email,telegram,whatsapp},session:{token,expiresAt}}`. Reject expired/mismatched proof, proof without attached booking, invalid device, cross-owner collision. Do not trust client-supplied contact or ID. Read contact from a verified challenge consumed for precisely this booking and compare against attached verified contact. Use an atomic unique contact claim, preserve existing credential rows and canonical ID. Do not merge users on unverified names/phone/email. Verify existing link-booking endpoint accepts this session and only links the authorized booking; do not blindly relink other trips. Preserve current booking numbers and existing history, audit records and Telegram bindings. On a race return a retryable conflict, no duplicate user.

Before production, verify: actual D1 migrations/unique constraints and canonical links; existing/first profile; same email/phone across devices; wrong/expired/replayed proofs; different contact on previously established profile; simultaneous attempts; idempotency on network loss; payment/passport ownership; expiry/recovery and old guest migration. Current reference uses the old schema and server-issued sessions; TypeScript typecheck succeeded, but no real D1 or live endpoint test was possible.

### Notifications and Telegram
Existing verified-email/SMS attach and push registration routes are preserved. Confirm actual unified Worker sends creation and each status notification on the selected channel, including SMS (OTP delivery is not proof that status SMS works), and that email status updates use durable deduplication. The Telegram bridge remains as-is: explicit Telegram authorization is required; email or phone cannot supply Telegram user ID. Actual bot/unified backend source is needed to persist one canonical `telegram_user_id` mapping and enforce uniqueness/consent, verified server-side Telegram login/Mini App initData, revocation, subscription routing and ownership. Do not infer a Telegram ID or silently send messages. Android/web/bot source not included in this archive; no modifications to those apps. No actual migrations or deployments performed.

## Verification
- Linux Swift frontend parse of all Sources: PASS. Not an Xcode build or UI test.
- `bash scripts/test_seamless_booking.sh`: 12 runtime policy checks and static integration checks PASS.
- Previous cumulative hotel compatibility and performance/launch/Hotel First smoke tests: PASS.
- Reference legacy TypeScript module `tsc --noEmit`: PASS while temporarily applied; reverted to avoid accidental legacy deploy.
- TestFlight on iPhone and production Worker E2E still required. Verify OTP from real email/phone and both old and new profile flows before App Store rollout.
