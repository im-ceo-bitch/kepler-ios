# iumrah Arabic / RTL implementation — 2026-10-12

## Applied scope

- App-wide `ar` in `AppSettingsStore.Language`, with `ar_SA` locale.
- SwiftUI root `.environment(\.layoutDirection, .rightToLeft)` follows **the app-selected language**, not the device language; all other app languages remain LTR.
- Arabic option in language-selection flow, instant RTL preview, and confirmation.
- Full `L10n` source dictionary (553 English keys) has a matching Arabic translation, with format-placeholder signatures checked.
- Additional exact source phrase translations (1066 strings) and Arabic branches in screen-specific language switches, including 19 composite language/state switches.
- Arabic display strings for eSIM, Home, booking/checkout, Hotels, flight search, trip planner, Umrah Flow and guide selection.
- Language-sensitive date formatting uses `ar_SA` where screens explicitly assign a locale. Flight/IATA timeline stays LTR so chronological origin/destination ordering is not reversed.
- Semantic chevrons use `forward/backward` where possible for natural RTL mirroring.
- Widget Extension supports `ar`, localized labels, native Arabic date formatting and RTL layout; route/IATA order explicitly remains LTR.
- Booking itinerary on the Package Engine supports `ar`, `ar-SA`, `ar_SA`; account verification/reset email supports Arabic and `dir=rtl`, security code forced LTR.
- The Umrah Flow catalog already has Arabic text and Arabic audio URL entries. This patch preserves those assets and the previous Umrah Flow fix.

## Automated verification performed on Linux

- Swift compiler **syntax parsing** on 265 Swift files (including widget).
- Independent Swift compiler **type checking** of `ArabicLocalization.swift`.
- Swift runtime assertions for representative Arabic catalog keys, phrases and technical-code fallback.
- `scripts/ci_language_audit.py` static language exhaustiveness and format checks (470 general switches; 19 composite switches checked).
- JSON/plist and 91 asset-catalog validations from `scripts/ci_preflight.py`.
- Package Engine `tsc --noEmit` passed.
- Package Engine **125** Node contract tests passed (including 3 new Arabic/backend/widget RTL tests).
- Package Engine **24** runtime tests passed.

## Critical release gates not yet performed

1. **Real macOS Xcode compile and archive** using the complete iOS and widget targets; Linux Swift parsing does not typecheck SwiftUI/UIKit or detect every Swift compiler problem.
2. Run visual RTL QA on iPhone 11 and iPhone 13 mini and an iPad (Home, Hotels, Flights, booking, ID/Account, QR, Umrah Flow, prayer, weather, eSIM, widgets, calendar).
3. Run interactive booking/flight/price tests with live backend data; remote CMS descriptions can remain in source language until Arabic CMS content exists.
4. Deploy changed `Backend/PackageEngine` via `Deploy iumrah Package Engine` GitHub workflow **after** confirming TypeScript tests and reviewing diff. No new database, schema migration or signing secrets are required by these changes.
5. Once the backend deployment succeeds, run TestFlight and check `ar_SA` emails, saved booking itinerary and Umrah Flow audio connectivity.

Do **not** represent this artifact as a guaranteed successful TestFlight until `xcodebuild` completes successfully. The ZIP patch bot currently does not typecheck Swift before committing files to `main`; a native Xcode build remains the authoritative release gate.
