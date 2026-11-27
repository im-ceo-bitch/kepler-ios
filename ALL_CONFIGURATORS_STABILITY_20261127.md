# All Configurators Stability V3 — iOS
Cumulative against kepler-ios-main 10.zip; includes Official V2, supersedes prior client patches.
- Official: separate guide stage with available Davletbek preference; stable backend member ID.
- Manual: multi-room allocation from adult count, preserve selections while refreshing occupancy/date rates, partial estimates cannot authorize booking.
- Smart: shared rate recovery; preserve hotel identity, meal/refund terms and prior package if reprice fails.
- Shared JourneyStore: input-bound quotes, bounded recovery of expired rates, cancellation/revision protection; final review rechecks price before booking, requires authoritative reconciled price and booking permission. Preserve train choices and validate child ages.
- Policy: 1–5 adults minimum one room; 6+ minimum two; actual supplier capacity still required. Manual adult-only basket keeps existing six-adult limit. Manual summary edits do not overwrite original basket on back navigation; basket is recalculated. No automatic alternative tariff outside explicit review.
- Local checks: 37 executable shared/manual model checks; official 14 executable + 11 static; Smart edit 14 static; Smart review 5 executable + 10 static; mixed booking 18 executable; Swift syntax parse of 15 changed files. No Xcode/iOS SDK or live supplier checks in this environment. Legacy storefront previews inspected but not redesigned or tested end-to-end.
- Install Business V3 first and deploy its backend, then this patch and build TestFlight. No prior patch required. No workflow/signing changes.
