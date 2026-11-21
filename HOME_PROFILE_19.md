# iumrah Beta — Home 2.0 + Profile 2.0 — Update 19

## Installation
Patch for the existing `kepler-ios` repository. Can be applied after Hotels Stability 18.
Copy the `Sources/` paths into the same paths in the repository; do **not** nest the ZIP under an extra directory. Do not use a whole-project replacement.

## Home
- The original animated search hero (`IumrahHomeJourneySearchHero` / `IumrahGraphiteSearchSurface`) and the published flight selector remain in place. Outbound and return are chosen separately. Selected flights lead into the existing hotel flow.
- Approved Why iumrah eight-card carousel, mission, recent activity, notifications, ready offers (only published and valid), services included/available to configure, benefits and slogan.
- A compact Smart entry maintains access to the Smart configurator; no large duplicate sales card.
- Removed from the active home view: auto-playing video, duplicate standalone campaigns and rewards sections, redundant product / integration carousels, secondary oversized storytelling cards. Their underlying destination screens and code remain in the app.
- No repeated background 120-second booking / eSIM polling launched by the Home view itself. Existing app-level refresh and manual refresh continue.
- Benefits are displayed without a second dashboard network subscription on Home; open the existing Balance, Rewards and Friends pages for account-specific details.
- Published packages come from the existing `/api/storefront/packages` filtered cache. When there is no published offer, no empty promotion card appears; its loader remains mounted.
- Service list is a set of *configurable categories*, not a promise that every service is included at no extra cost. Actual inclusions/prices still follow the final package summary.

## Profile
- Compact account summary and six white mono-icon navigation groups: journeys, personal data, benefits, settings, help, services.
- Preserves direct access to Bookings, saved journeys, favorites, Find booking (guest and signed-in), pilgrim profiles, iumrah ID, Balance, Rewards, Friends, account security, notifications, Telegram, flights, ziyarats, eSIM, payment/refund/privacy policies.
- iumrah ID opens its existing full-screen card; Wallet action is available from the ID view, without a huge Wallet promotional card on Account.
- Personal recommendation toggle, recent-activity cleanup confirmation, automatic tips toggle moved into Settings instead of losing these actions.
- Existing sign-out and delete-account confirmation flows remain unchanged. The slogan and brand-world header remain.

## Verification (source-level only)
- `swiftc -frontend -parse` on all 348 available app Swift sources: passed.
- Version 19 Home/Profile static regression: 16/16 passed.
- Brand Experience 15, Booking/Splash 17, Seamless Booking, Smart editing and review, Shared Quote, Trip Summary Design, Flight browse semantic test, Hotel hydration, Hotels V4 stability: passed on the merged source tree.
- A full iOS SDK type-check, Xcode build, TestFlight and UI runtime validation on real devices **were not available here**. Do not treat parsing/static tests as a successful iOS build.

## Changed files
- `Sources/Views/Home/HomeDashboardView.swift`
- `Sources/Views/Home/HomePersonalizationSections.swift`
- `Sources/AppShell/IumrahAccountView.swift`
- `scripts/test_home_profile_19.py` (new)
- `scripts/test_booking_empty_splash_17.sh` (UI regression expectations updated, OTP checks unchanged)
- `scripts/test_seamless_booking.sh` (UI regression expectation updated, identity/ownership checks unchanged)
