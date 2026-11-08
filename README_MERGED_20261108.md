# iumrah · consolidated native headers + Nuitee patch (2026-11-08)

Cumulative relative to `kepler-ios-main 4.zip`: **do not apply previous 16- and 32-file patches first**. Upload this single ZIP to repository root and run the existing ZIP unpack workflow. No new workflow.

## Merged
- 32-file foundation: persisted package selection and Care inquiry, local staged journey and supplier Nuitee endpoint/runtime tests, adult/child room occupancy.
- 16-file quality: stable black header boundary, 56pt opaque capsule CTA, full mandatory `DESIGN_RULES.md`, public Hotels tab **only Nuitee**.
- Homepage header lower edge +20pt. Staged Flights/Hotels/Transfer/Review have one common geometry, and opaque emerald outlined search card overlaps hero; expander does not resize black hero.
- Four other root tabs show left wordmark and right native Glass notification+menu in identical scrollable world-map hero (Home wordmark stays centered). Tab bar hides while inside configurator.
- Fix calculation for non-adult travelers: adult Data API fare is NOT multiplied by child/infant; no estimated aggregate is shown until fare can be confirmed. Nuitee rates revalidated for selected offers on pull-to-refresh; expired rate removed.
- No simulated Liquid Glass: buttons use `.buttonStyle(.glass)` on iOS 26, `.bordered` system fallback on older iOS. Main CTA never Glass.

## IMPORTANT checks / limitations
- iOS Swift syntax parsing and backend tests are run locally; no macOS Xcode/iOS simulator is available. GitHub TestFlight workflow must verify typecheck, compilation, screenshots and interaction.
- 32-file patch server changes must be deployed with your **existing** PackageEngine workflow after the ZIP is applied.
- Published flights without fare: final estimate unknown; fares are not invented. Children/infants: aggregate unknown until ticketing price confirmed. Nuitee availability and final total remain subject to supplier confirmation.
- The client may submit a Care request; this is **not** direct supplier booking or payment.

- The four non-home primary tabs switch their status-bar surface from black to page color when the header scrolls away.

- Home no longer shows the old Business/D1 hotel showcase carousel; existing historical links remain readable.
