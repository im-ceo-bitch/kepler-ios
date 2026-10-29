# iumrah Configurator V1 — Visual Flow (29 October 2026)

Base: user-provided `kepler-ios-main 4.zip`. This is a PATCH, not a full repository.

## Implemented

- Four customer-facing stages in the existing Hotels root tab: Flights → Hotels → Services → Summary. Existing flight discovery, Nuitee catalogue and their stored choices remain in place. Sunday Umrah Club deep links remain supported.
- Same horizontally scrolling iumrah graphite/black stage pills in the root brand header. Flights open first. An accessible Next button progresses through the stages.
- Compact 56-pt pinned black title bar; the large title, world-dots texture and stage pills scroll away naturally with the body. Scroll refresh lives below the pinned bar. Safe-area top remains black.
- A single translucent bottom Umrah assembly cart for all four stages (not a real checkout). It shows real flight/stay counts and opens the Summary.
- Hotel tier filters: Economy 1–2★, Standard 3★, Comfort 4★, Luxury 5★. Existing star filter remains; changing tier resets the star filter.
- Visual hotel form for rooms, adults, children, infants and nights. IMPORTANT: the current Nuitee endpoint only quotes adults in one room; the UI explicitly states additional occupancy requires future verification. No fabricated prices.
- Services collected in a single page: transfer (private/shared), ziyarats, guide, Saudi visa, meals. Support and eSIM together in one block; no separate eSIM stage.
- Detailed visual final preview: selected flight route cards (JourneyStore), individual Makkah and Madinah stay cards (existing NuiteeStaySelectionStore), hotel room details/policies, service and support cards. Hotel cover images loaded by real saved hotel IDs when available.
- Package total and final booking intentionally NOT implemented. Disabled booking CTA and clear draft notice; no payment / booking / supplier calls.
- Visual service choices persist in local UserDefaults, separately from any live booking.

## Deliberately unchanged

- `.github/workflows/**` including TestFlight Intel and build numbers
- Nuitee secrets, Cloudflare API, server prices and payment logic
- Native iOS Liquid Glass tab bar and Umrah Flow V2
- Existing legacy package generation/booking flows

## Validation / limitations

- Swift frontend syntactic parse for all 281 Swift sources passed in the available Linux environment.
- No Xcode / iOS SDK on this environment: full SwiftUI typecheck, archive, TestFlight upload, UI tests and simulator QA are NOT confirmed.
- Test in Xcode: iPhone 11 (414 × 896), iPhone 13 mini (375 × 812); tab switch, pull to refresh, service persistence, Nuitee room selection then summary, staged flights then summary, keyboard and safe-area/cart overlap.
- Vendor Sandbox prices are not production prices and cannot be used to book.
- New draft UI labels are localized to RU/UZ Latin/EN with EN fallback for other locales. Expand to complete translation catalogue before public launch.

## Install

Put this ZIP at the repository root; the existing `apply-beta-update.yml` recognizes `iumrah-beta-update-*.zip`. It has no GitHub workflow edits. Then build with your existing TestFlight Intel workflow. Do not upload a full repository ZIP as an update.
