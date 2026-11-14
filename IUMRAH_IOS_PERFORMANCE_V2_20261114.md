# iumrah iOS — Performance V2 (cumulative V1 + V2)

## Installation
Upload the ZIP unchanged to the iOS repository's root and run the existing unpacker / TestFlight workflow. This archive includes V1, so applying it separately is unnecessary. No backend deployment, database migrations, GitHub workflows, project settings or signing changes.

## Changes beyond V1
- Hotel/airline image loader: at most four simultaneous load operations, shared same-key requests, cancellation when the last consumer leaves, separate size/URL identity, compressed disk cache periodic trim above 128 MiB down to 96 MiB (soft threshold), existing 48 MiB decoded NSCache target. Images in legacy and manual cards use 768px thumbnails. Fullscreen galleries retain larger images.
- Flight browse: sort/deduplicate off MainActor and publish after each route rather than each monthly response. Preserve all provider requests, pricing data, and selection rules; stale responses cannot publish.
- Journey hotels: cached derived filters and no results from the previous dates/city while a new search loads. Nuitee daily cache retains at most four hot keys in memory; expiry and disk persistence remain; final quotes are not newly cached.
- Transfer: skip rendering fully offscreen vehicles, remove redundant blur from a soft VIP gradient. Existing swipe behavior, VIP background, capacity rules and pricing remain.
- Booking/account: only link when booking identity/token changes or on foreground retry; deduplicate in-flight and successful links in the current account session. Canonical link changes that don't change stored data no longer republish or persist. No booking identifiers or backend contracts changed.
- Notifications, widgets and shortcuts: avoid duplicate publication, resorting and unchanged widget snapshot writes; shortcuts update only when relevant display number changes. Shared reachability monitor, probe throttling and lifecycle-aware status pill.
- Decorative Siri orb, glow and orbit ring: pause when offscreen/inactive, reduce animated sampling to 30 Hz, not the application's scroll frame rate. Reduce Motion respected. V1 static search header map decision retained.

## Verification
- Swift 5 syntax parsing of all 321 source files on Linux: passed. This does not constitute an Xcode/iOS SDK type-check or archive.
- Existing performance smoke: memoization and 2,000 repeated timezone conversions, arrival tests passed.
- Nuitee cache smoke: 16 checks passed including expiry, isolation, persistence, bounded hot entries and corrupt disk recovery.
- Image coordinator smoke: actual production coordination methods extracted and compiled with fake UIKit/network loader. Thirty equal requests share one load; twenty distinct requests peak at four concurrent loads; shared cancellation and full-cancellation retry pass. Actual ImageIO/URLSession rendering was not tested on iOS.
- Physical iPhone 11 and iPhone 13 mini QA is mandatory: compare release builds using Instruments (Animation Hitches, Time Profiler, Allocations), search filters/date changes, rapid scroll, switching cities, room selection, transfer and booking. Target smooth 60 Hz interaction, not a measured result. No guarantee of zero hitches or network latency.
