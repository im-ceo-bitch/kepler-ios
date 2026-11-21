# iumrah Beta — Hotels V4 Stability (cumulative update 18)

## Base and compatibility

- Combines all files from `iumrah-beta-update-booking-empty-splash-17-final-cumulative.zip` with Claude's `iumrah-hotels-v3.zip` and the stability improvements below.
- Install as **one ZIP at the root of `kepler-ios`**; do not extract into a new nested folder. Compatible archive filename prefix: `iumrah-beta-update-`.
- Only `Sources/Views/Hotels/NuiteeHotelsCatalogView.swift` changes relative to Claude V3. `Sources/Services/NuiteeHotelService.swift` is byte-identical to Claude's file and to cumulative update 17.
- This update does not change Backend/Business, API endpoints, hotel purchases or availability decisions.

## Changes / safeguards

1. **Stable hotel-card order:** retain supplier order, with selected-star cards before unrated cards, even after `pricesLoading` finishes. No ordering changes due to streamed rate data or sold-out statuses. Keep Claude's price counter, progress indicator, review-count handling, confirmed sold-out copy and independent availability errors.
2. **Duplicate and empty IDs:** deduplicate both city-cached and new supplier snapshots before `ForEach`. Use duplicate-safe dictionary construction; avoid a possible runtime trap during metadata refresh.
3. **Stable refresh:** when refreshing metadata for the same hotel search, preserve the original order of existing cards; append new ones in provider order.
4. **Batched model updates:** receive individual fallback room-rate responses in groups of three and publish their price/status changes once per group, avoiding unnecessary whole-list recomputation per hotel.
5. **Cancelled tasks:** if an in-flight request is cancelled, convert unfinished skeletons to a retryable status rather than leaving them stuck indefinitely. Supplier rate-limit handling remains intact.
6. **Photo carousel:** keep original multi-photo collages; avoid publishing provisional photos followed by another photo replacement. Debounce costly per-card photo verification when a card enters the visible viewport repeatedly, and bound/negative-cache failed detail-photo lookups.
7. **Ratings:** require a positive review count before showing a numerical rating. A zero-review or unknown-review-count rating is not surfaced as an apparently verified score.

## Verification done

- Archive integrity and unsafe-path checks.
- All 348 app Swift source files (original repository + cumulative patch) passed **Swift parser** checks on Linux.
- `scripts/test_hotels_v4_stability.py`: 21 source/model regression assertions passed.
- `scripts/swift_algorithm_smoke.swift`: actual Swift compiler smoke test passed for ID deduplication, stable sorting and star grouping (run `swiftc -parse-as-library scripts/swift_algorithm_smoke.swift -o /tmp/iumrah-algorithm-test && /tmp/iumrah-algorithm-test`).
- Confirmed supplier service file byte-identical to Claude V3.

## Verification NOT done (requires Apple environment / real backend)

- Full iOS **Xcode type-check and build**, code signing and TestFlight installation.
- Frame-time profiling on iPhone 11 / 13 mini, real Nuitee provider calls, navigation stack dismissal and on-device memory pressure.

## Smoke tests on a phone

1. Open Makkah and Madinah catalogs with 150+ cards; scroll during price loading. No card should jump when prices finish.
2. Switch dates, city and guest count repeatedly. Old prices must not bleed into a different stay; controls remain responsive.
3. Select star filters and search by hotel name during hydration; filters should apply locally without canceling catalog loads.
4. Open a hotel while its card's price is loading; check full photo gallery, room rates, selecting a room and returning to the same scroll position.
5. Check supplier-confirmed no-rooms vs rate outage; avoid false sold-out messaging when provider gives ambiguous/no response.
6. Scroll up/down repeatedly over the same hotel cards; photo collages should not flicker or trigger noticeable repeated network work.
7. Trigger a rate-limit or airplane mode; the catalog should remain visible with retry, not crash or show indefinite skeletons.
