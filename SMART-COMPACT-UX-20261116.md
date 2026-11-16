# iumrah Smart — compact UX + flight and hotel regression fix

Base: `kepler-ios-main 7.zip`. Apply this ZIP to the repository root with the existing `Apply iumrah Beta ZIP update` workflow. No workflows, signing, assets, backend deployment or pricing rules changed.

## Smart
- One custom black header for the Home and first-launch flows. Step progress is in the fixed footer immediately above the CTA.
- The existing animated Orbit V5 is constrained to 76–148 pt by both viewport dimensions. The title and explanatory text are alongside it. The same layout is used for every step.
- Compact choices for airports, months, duration, route and hotel tier. All four hotel tiers are visible in a 2×2 grid, selected tier details below. One style for both passenger counters. Ages are explicitly selected; the previous silently defaulted age of six is removed.
- Scroll remains as an accessibility/small-display fallback and for the detailed final package. No artificial vertical scroll required for standard-size selection screens by design.
- Error states do not claim that flights are absent when family fares cannot be verified. Child/infant pricing remains subject to the server's supported fare contracts; no adult-fare substitution added.

## Flights
- Guided flight selection keeps existing results on a same-query refresh and skips the initial request when the trip has already loaded. Removed nested outer lazy containers and loading indicators that displaced nonempty results. Explicit changed-search requests still invalidate the prior results. Cancellation and request generation checks remain.

## Hotels
- Support both paginated responses and older city-wide responses missing `total`. The latter are filtered and paginated locally (stars, query, favorites), rather than rejected.
- If a rates request fails, browse screens may fall back to the catalog-only endpoint; rates are removed and availability is marked unverified. Smart assembly does not use that fallback, and still requires real validated room offers. A same-search failure keeps the catalogue but removes unverifiable prices.
- Guided hotels no longer auto-scroll to the top on every appearance; a successful already-loaded search is not repeated on detail return.

## Validation
- `bash scripts/test_nuitee_page_compatibility.sh`: PASS
- `bash scripts/test_iumrah_performance_v4.sh`: PASS (all Sources Swift syntax parse, snapshot/timezone, image coordination, cache, launch geometry, performance and hotel-first smoke checks)
- Actual Xcode/iOS simulator build, visual device check and production Worker/Nuitee end-to-end validation were not available in the Linux environment. Verify on TestFlight, including iPhone 13 mini / iPhone 11, the route back from flight details, four tier cards, and hotel search for Nov 25–28 with two adults and 3 stars. If the live Worker itself fails both rate and catalogue requests, its deployment/logs need separate inspection.
