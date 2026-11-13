# iumrah V19 — Home, travel widgets, catalogue paging

- Home order: search → help/notifications → video → services → build your Umrah → travel widgets → audience → remaining sections. Legacy ready package/hotel showcase sections and Home-triggered storefront warmup removed.
- Existing support team asset `IumrahCareTeamHero` reused. eSIM copy explains mobile data and internet calls; private transfer copy clarifies dedicated transport. Individual service detail links remain.
- The CTA uses the parent's search expansion binding and existing ScrollViewReader to open the actual search card, not a second configurator.
- The booking carousel is moved to Home; one selection binding controls swipe and segmented selector. Native glass on iOS 26, segmented fallback on older systems. Booking tab names changed without replacing their underlying screens.
- Hotel and flight lists reveal 20 rows initially, then 20 on each button press, reset on filters or search. Guided flights share one limit across direct, connecting and nearby sections. Existing server list endpoint is unchanged: first request obtains the catalogue, pagination is local and does not repeat requests. Images remain loaded on demand by existing image cache.
- Nuitee hotel list responses are persisted to the iOS Caches directory, keyed by city, arrival, departure, adult count, and list/rates mode. Entries expire at local midnight or 24h, whichever comes first. Successful rate responses retain upstream stale flags; failed rate responses are not cached. Manual refresh bypasses cache for regular hotel results. Booking detail rates and quote validation remain live. Cache can be evicted by the OS.
- Includes the previous V13 flight-view changes for compatibility. Does not replace V18 private configurator files, backend, or workflows. No deploy required.

## Validation
- `python3 scripts/ci_preflight.py`: 314 Swift files parsed; 434 language switches; 95 assets/plists. Two existing unassigned asset warnings.
- Standalone Swift cache test: 12 checks (disk persistence, separate request keys, expiry, corrupted file, etc.). Run `bash scripts/test_nuitee_daily_cache.sh`.
- No Xcode/iOS runtime in this environment. Full TestFlight build and device UI validation required.
