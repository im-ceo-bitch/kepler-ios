# iumrah · Booking created experience

Base: kepler-ios-main 4.zip, commit 5b83c109d17860ed4d2ae29bc9f4ebb4738c6931.

## Changes
- Shared `IumrahBookingCreatedContent` for the guest checkout and legacy celebration. The new non-flippable black summary card uses the existing native, spectral `Canvas` renderer extracted from `IumrahBookingDomeCard`; the original renderer and flip-card appearance are preserved.
- Original PCM chip-ting sound bundled in Resources/Animations, success haptic synchronized with the drawn checkmark, once per mounted successful checkout. Reduce Motion draws the static confirmation immediately. Removed early success haptics and the competing automatic Hotel Storefront navigation.
- Shows real server booking number, pilgrim ID, party size, total and per-person price. The success screen is gated by the existing guest verification, server-identity reconciliation and contact attachment; no client-generated booking IDs or payment confirmation.
- Verified SMS/email destination, actual Telegram link flow (including linked state on return), status update explanation, next steps and opening the saved booking. Contact attachment is not a delivery receipt. No new account or payment endpoints.
- 30-minute **estimate** based on persisted server availability-start/creation timestamps, bounded by earlier server deadline; no new timer on reopen. After zero, display a continuing-check message, not failure or automatic confirmation. Current booking status refreshed while visible and active, every 20 seconds until availability phase ends. Booking tab/detail use the same estimate. Existing server SLA, payment hold and document deadlines remain intact.
- Main confirmation content translated into eight app languages. Existing navigation, theme and secure guest access remain in place.

## Verification
- Swift frontend parse succeeded for changed source files (Linux Swift; no iOS SDK). Full Xcode compile, iPhone rendering, sound/haptics and live backend delivery require device/TestFlight QA.
- `swiftc Sources/Models/IumrahBookingAvailabilityEstimate.swift Tests/IumrahBookingAvailabilityEstimateSmoke.swift -o /tmp/iumrah-eta && /tmp/iumrah-eta`: 11/11 passed.
- Four selected Node contract suites: 13/14 passed. The remaining storefront visual contract expected `iumrahFlightDetailChrome()` in `PackageFlightLegDetailCard`; that symbol is also absent from the uploaded unmodified source. It is unrelated to the completion patch and not silently suppressed.
- Renderer byte-for-byte comparison passed; all eight new copy tables contain 24 entries; original WAV is 44.1 kHz mono signed 16-bit PCM, 0.46s.
- Production notifications: iOS continues to call the unified backend verified-phone/verified-email routes. The uploaded repo documents that its PackageEngine source is rollback-only. Actual initial SMS and subsequent delivery cannot be proven from this iOS archive. Do not deploy that old backend; verify the unified Business worker's initial/status dispatch separately.

## Deployment
Upload the ZIP to the root of the current iOS repository; the existing `iumrah-beta-update-*.zip` workflow applies it. No workflow, signing, project configuration, backend or D1 migration changes. Trigger the usual TestFlight build after applying. Do not deploy the old PackageEngine.
