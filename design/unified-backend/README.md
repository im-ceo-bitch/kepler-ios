# Unified backend — iOS candidate V7

The only first-party API origin in the iOS client is `https://iumrah-backend.helloiumrah.workers.dev`. The public website remains `https://iumrah.app` for shared hotel, package and identity links. API paths and payloads are intentionally preserved, including `/api/package/*`; this is a URL namespace, not a separate deployment target. The client does not fall back to the legacy API origin. First-party API URLs received as absolute URLs are re-resolved to the unified host, preserving query strings. Authenticated API media from an unknown host is rejected instead of forwarding credentials.

## Installation gate — do not publish the iOS build yet

The current Business/unified backend repository was not supplied in this conversation and could not be recovered from the file library. Public endpoint checks were unavailable in the working environment. The iOS routing code is ready, but the deployed Worker has NOT been verified to implement the complete client contracts. Before rollout:

1. Inspect the current `lattice-mobile` repository and its `iumrah-backend` routing, D1 binding(s), migrations and auth/session compatibility. Compare against `ios-route-inventory.txt` (literal route inventory, not an exhaustive proof of methods or schemas).
2. Port the required package, flight detail/AeroDataBox, booking and other missing route handlers into the existing Worker, using the actual D1/R2 bindings and existing auth logic. Do not deploy the old `Backend/PackageEngine` as another Worker. Do not rename/delete a Worker, change workflows, or migrate/delete existing data blindly.
3. Use the existing secrets in `iumrah-backend`. Verify authorization, account session continuity, hotels and prices, flight search and enrichment, quotes, booking reads and writes, chat, media, identity and analytics in staging. Test both AeroDataBox keys only within authorized plan limits. Deploy the existing unified backend workflow, then TestFlight.

External public services (Umrah Flow Supabase translation/audio, weather, prayer times, exchange rates, public logos and external links) are unchanged. If the single-origin requirement covers those too, implement corresponding backend endpoints and migrate those clients with the actual backend source; do not invent route contracts or disable existing functionality.

## Patch scope

Includes the iOS sources from flight cumulative V6 plus unified origin changes, a routing smoke test, the analytics test build adjustment and this inventory. Intentionally excludes all legacy Backend/PackageEngine code and all workflows. This preserves the previous flight UI updates without redeploying the obsolete Worker. AeroDataBox server-side V6 is not yet installed into the unified Worker.

Local checks: Swift routing smoke test, analytics smoke test, Swift parser on changed files, existing PackageEngine test suite (151 static/contract + 79 runtime). Those tests do not validate deployed iumrah-backend or compile the full iOS app in Xcode.
