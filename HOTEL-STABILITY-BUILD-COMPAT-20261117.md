# iumrah V8 — hotel stability + archive compatibility

Cumulative overlay of the V7 patch onto the supplied `kepler-ios-main 7.zip`. Includes all prior V1–V7 patch files. No GitHub workflows changed. Target: existing kepler-ios repository root.

## Hotels
- In the Nuitee and legacy storefront list, select up to three distinct actual photographs. Normalize resize parameters, then compare decoded thumbnail RGB signatures across different URLs. If fewer than three are available, use only verified distinct images; load additional catalog media where possible. This is a bounded heuristic, not a guarantee against arbitrary crops or edits of the same image.
- Shared review snapshot cache per hotel and language; coalesced requests, pagination with ID deduplication, successful empty result caching, explicit retry on errors. Reappearance no longer clears reviews. Cache is in memory, fresh for 30 minutes.
- Detail and rate tasks are keyed by hotel/language and stay/guests; already completed data is not reset unnecessarily on return. Room display names prefer actual catalog category names, not feature lists; provider IDs and original rate fields remain unchanged.

## Build log 119349918404
The supplied Xcode archive log had 8 compiler diagnostics: missing itinerary executionState/managed properties, missing eSIM bridge methods, and BusinessOfferView's older verified-contact initializer. The model fields and compatible entry points are restored. eSIM data is fetched through the authenticated existing operational-trip endpoint, scoped to the booking/account generation. Business offer checkout uses the verified proof, not the unverified fallback closure. Newer calendar/service/offer files seen in the log but not contained in the provided baseline are not overwritten by this patch.

## Validation
- `scripts/ci_preflight.py`: syntax, language switches and asset/plist checks.
- `scripts/test_hotel_stability_v8.sh`: review cache, room titles, photo distance.
- Extracted actual itinerary declarations: legacy/new JSON and initializer compatibility; extracted Business offer initializer overload: Swift typecheck.
- Existing notification, guest Care, seamless, Smart and hotel paging/cache tests.
- A full Xcode archive and physical-device tests remain necessary. In particular, the real hotel image URLs and the newer full checkout are not available to validate on-device in this environment.
