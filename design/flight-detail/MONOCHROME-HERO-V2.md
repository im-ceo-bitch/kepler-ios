# Flight Detail V2 — full-bleed monochrome hero

Base: kepler-ios-main 9 + 20261112 premium-flight-detail iOS changes.
This ZIP is cumulative for iOS only. The Package Engine endpoint introduced in the previous release is unchanged and is not included in this UI patch. If it was never deployed, deploy the previous backend update separately for AeroDataBox enrichment. No backend deployment is needed for this UI update itself.

## Layout
- First leg: native opaque graphite navigation bar (including status-bar background), inline airline title, standard back and share; zero top gap, full-width graphite hero. Remaining segments use embedded cards rather than extra navigation headers.
- Collapsed: large verified flight number, IATA codes, local departure/arrival times, aircraft symbol above thin route line; cropped upper half of the same native globe as a decorative layer.
- Expand/collapse: 44-point control with localized accessibility label; same 296-pt globe expands from 148-pt clip, real coordinate overlay only in expanded state, details below follow the animated layout. Reduce Motion disables spring and light sweep. The compact height is content-driven (roughly top third on standard iPhones, larger for accessibility text).
- Secondary dates, airports, airline branding, aircraft, terminal/gate and flight metrics are below the hero. Only confirmed fresh position permits green progress. Flight status/warnings retain semantic colors.
- Flight palette is adaptive and neutral: light page #F2F2F2, card #FFFFFF, gray graph bars, primary selection; dark equivalents use equal RGB channels. Airline logos retain their identity. The other product areas retain their palette.
- Flight First and discovery cards: larger local times, explicit verified number, monochrome route, neutral radio selection, price shown only if valid; no invented fare. Missing price leads to details instead of a placeholder. Date graph scrolls to selected day or closest available data, without synthesizing data.

## Validation
- Swift syntax parse of every Swift file in this update; geometry from prior component retained.
- Existing Package Engine source/contract suite: 148/148; runtime suite: 70/70, TypeScript compiled by runtime suite.
- Full SwiftUI typecheck, status-bar rendering, animation performance, layout at accessibility sizes and device interaction must be verified on macOS/Xcode and TestFlight. No iOS simulator available in this environment.

## Install
Upload the ZIP to the repository root using the existing unpacker. No .github/workflows, server files, migrations, secrets or Cron changes are included. The previous AeroDataBox service remains optional and gracefully falls back to existing data when its endpoint is unavailable.
