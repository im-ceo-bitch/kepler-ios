# iumrah Unified Catalog 11 — cumulative update

Apply this archive over the original repository, not over an assumed deployed version. Includes prior cumulative stage 10 and all current changed files. Old hash manifests are superseded by UNIFIED_CATALOG_11.sha256. No supplier booking or automatic purchases are added.

- Old PrimaryHotelView redirects into the shared Nuitee journey hotel picker. Previously selected published and Aviasales flights are carried into the shared journey; older hotel-first flexible/weekend entries without resolved flights now open the common flight-first selector.
- Shared full catalogue and local name/star filters, exact search-scoped positive price reuse, no manual catalogue pagination. Smart examines the whole eligible static catalogue, prices in batches.
- The standalone manual basket supports one adult-only room per city. Family/multiple-room browsing now displays first-room rates, with a hand-off to the full guided trip builder; that hand-off reselects flights.
- Existing collage and price detail flow retained. No fabricated stars or prices.
- Linux Swift frontend parse, compiled catalog model smoke and 14 static Smart integration checks passed; Xcode type checking/build and device UX not run.
