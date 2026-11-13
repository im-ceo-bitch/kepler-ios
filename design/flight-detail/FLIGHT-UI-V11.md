# iumrah Flight UI V11 — 2026-11-13

Baseline: kepler-ios-main 3.zip (after Unified Core migration). Overlay only; no workflow, Worker, D1, AppConfig, booking or pricing implementation changes.

- One in-content navigation header on flight details; native navigation bar hidden. Only background extends into the status-bar safe area. Full-width graphite first hero; no expansion button, no overlapping native title. Back/share remain available; round-trip share still includes full itinerary. No fixed bottom booking buttons on detail pages.
- Real geographic dot hemisphere, fixed crop with gentle light variation and reduced-motion support. No colored decorative accents. Live progress uses the existing actual-position freshness gate.
- Compact airport itinerary, actual terminal/gate/baggage belt/aircraft rows only when known. Refresh via the existing unified API; an understated status row distinguishes missing schedule, quota, and server errors. No fabricated baggage, prices, aircraft or flight positions.
- Flight First and browse results share compact neutral cards; supplier labels are small secondary text; times are prominent; selected search date is not repeated; nearby and next-day dates remain visible. Header route has only the airplane, no horizontal line.
- Calendar rail uses observed grouped calendar fares and actual offers. Continuous date window +/-14 days with valid lower bound, no fabricated prices; missing values use a neutral dash. Native UICollectionView snaps to center and emits selection feedback per date, commits once when scrolling ends. Calendar month observations cached for 5 minutes. Exact date offers fetched before calendar observations; calendar rows never become bookable flights.
- All first-party API calls still resolve through `https://iumrah-backend.helloiumrah.workers.dev`. Existing compatibility path `/api/package/flights/detail` is served by the unified backend. No changes to Cloudflare credentials.

## QA
- 311 Swift source files parsed with swiftc -frontend -parse.
- 148/148 existing static contracts; one client-only contract adjusted to check actual shared ShareLink rather than the removed duplicate toolbar.
- 70/70 existing runtime tests; TypeScript typecheck passed.
- Geographic projection test passed across four viewpoints. Date-window test passed for 29 dates, minimum fare, month boundary, missing/invalid prices, inbound lower bound and past-date exclusion.
- Not validated: full SwiftUI build/archive on Xcode, visual layout on device, physical haptics and real supplier response/credentials.

## Apply
Upload only this patch to the kepler-ios repo already at the baseline above. Run TestFlight after unpack. No backend deployment or D1 migration is required. Verify iPhone 11 and 13 mini in both appearances, outbound/return, date swipes/taps, flight details opened from configurator/catalog/package/bookings, share/back, and no-published-fare state. If additional operational data is unavailable, inspect the unified Worker configuration separately rather than changing the iOS origin.
