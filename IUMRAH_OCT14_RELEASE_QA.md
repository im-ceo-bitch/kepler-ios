# iumrah iOS — 2026-10-14 flights, hotels, weather & support

Scope: 7 Swift files and 1 Cloudflare Worker backend file. This is a ZIP update, not a full Git repository.

- Hotels/Flights: the root title is inside the ScrollView, with the shared 18-point page inset; the top header is no longer pinned. Three large SF Symbols board controls.
- Global flight search: revalidates the proxy Data API when entering the tab again; exact-itinerary price verification updates the corresponding list entry when the user returns from ticket details.
- Calendar: starts at the current month rather than an already-selected future departure month; fetches additional months of observed fares and never fills gaps with invented prices.
- Price chart: outbound and return strips displayed simultaneously, up to 150 days, prices on all observed dates and '?' when missing; smooth horizontal scrolling with throttled soft haptics.
- iumrah recommendations: full-width vertical lists, with an outbound/return segmented selector.
- Backend: grouped_price day observations are retained even if precise flight departure time is not provided; sparse months are supplemented from real Data API observations only.
- Booking dashboard: prayer and weather widgets link to full prayer and weather pages.
- Weather: redesigned dark immersive page for Makkah and Madinah, measured hourly conditions and seven-day temperatures from MET Norway, no synthetic weather figures.
- Care: Call, Telegram, and internal booking chat buttons directly after the header. Chat is disabled without an active booking.

## Deployment

Apply this ZIP only after comparing the seven Swift files and one TS file with the latest GitHub main. It was merged from kepler-ios-main.zip (uploaded on 2026-10-12) + the prior Oct 12 prayer, Arabic, video-style prayer and Home/Hotels RTL patches; it is not a live GitHub commit.

Because Backend/PackageEngine/src/aviasales-data.ts changed, trigger your existing Cloudflare Package Engine deployment workflow. Then run TestFlight (iOS release archive).

## Verification scope

- Swift syntax parser: 266 Swift sources and 473 language switch checks PASS.
- Composite TR/ID/MS/AR language switches: 19 checked, PASS.
- Xcode compiled app: NOT RUN (no macOS/Xcode in this environment).
- TypeScript: tsc --noEmit PASS.
- Backend automated tests: 125 contract and 24 runtime PASS.
- All source files are UTF-8 and ZIP extraction tested; this is not proof of a successful TestFlight.

IMPORTANT: Aviasales Data API represents recently searched/cache fares, not live ticket inventory. A request with fresh=1 bypasses the iumrah edge cache but does not force a new airline quote upstream. Missing dates remain without fares. Booking must revalidate price and availability.
