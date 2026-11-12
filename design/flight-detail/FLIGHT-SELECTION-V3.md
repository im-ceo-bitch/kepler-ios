# Flight selection V3 — centered fare rail

Cumulative iOS-only patch based on kepler-ios-main 9 plus the previous premium flight detail and monochrome hero revisions. Upload to the repository root. No backend, D1, secrets, workflows or Cron changes. If AeroDataBox was never deployed, use the previously supplied premium-flight-detail backend update separately.

- The existing full-width branded black header now includes the active IATA route and the localized outbound/return instruction. The search summary contains dates, passengers and cabin; no duplicate route or date labels in the result section or direction picker.
- The shared list card makes IATA codes and flight number prominent and omits dates matching the search day, retaining different local dates and estimated-arrival labeling. Unknown fares are not synthesized.
- The shared horizontal fare rail uses native UICollectionView scrolling, a centered item with symmetric insets (including first/last dates), monochrome prices/bars, a dollar sign on every available fare, and a neutral dash for the selected date without a fare. The focused day receives a UISelectionFeedbackGenerator tick only when the center moves to a different date; tapping also has selection feedback. Native deceleration and center snapping; a single selection callback after drag/deceleration or tap animation completes. No requests on intermediate drag updates.
- The guided list preserves the previous fare calendar during date-only reloads and rejects invalid return dates. Existing booking choices, endpoints and sources remain intact.

Validation: 148/148 existing contract checks, 70/70 runtime checks and TypeScript typecheck passed. Swift syntax parsed for all bundled Swift files. Xcode compilation, actual device haptics and visual layout still require TestFlight verification.
