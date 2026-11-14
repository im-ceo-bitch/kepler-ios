# iumrah iOS — cumulative Performance V1–V4

## Installation
Unpack the update over the current iOS repository, preserving paths. Includes V1 and V2. No changes to backend, D1, API contracts, workflow or project configuration. XcodeGen includes the new Swift files under Sources automatically. Build a Release/TestFlight version. No backend deployment required.

## V3: architecture
- Hotel storefront snapshot decoding and coalesced atomic disk writes off the main thread; cached lookups and grouped hotel/price indexes; generation guards on airport changes. The cache is disposable, not a booking ledger.
- Hotel price graph memoized by source revision, date, locale and time zone. Reuse the current graph after asynchronous updates.
- Booking vault serializes secure Keychain writes, skips identical successful snapshots and awaits critical updates. Existing secure startup read and legacy migration remain synchronous to preserve startup identity/booking semantics. Existing Keychain access policy remains unchanged. Repeated reads reuse successful snapshots in process. Refresh merges once and guards against stale account tokens.
- Local journey input key memoized; existing price and booking rules retained.
- Adaptive rendering profile: efficiency (A12/A13, low power, serious/critical thermal state), balanced, performance. Decorative frame cadence at most 15/24/30 Hz respectively. Native scrolling and audio are not capped. Static backgrounds on efficiency, reduced blur and no automatic stage carousel presentation lap on efficiency; continuous carousel glow removed. Hidden tabs, background and reduce motion pause decorative timelines. Image cache target 24/48 MiB, memory warning purges cache.

## V4: verification and instrumentation
`bash scripts/test_iumrah_performance_v4.sh` parses Swift sources and runs portable smoke tests. On a Mac with the required Xcode/XcodeGen, `bash scripts/test_iumrah_performance_v4.sh --xcode-build` additionally attempts a Release simulator build. Simulator success does not establish physical-device performance.

In Xcode, use Product > Profile, Release configuration, a physical iPhone 11 and iPhone 13 mini; optionally the oldest supported iOS device. Record separate Animation Hitches, Time Profiler, Allocations, Network and Points of Interest traces. Signposts use subsystem `com.iumrah.app` and static operation names only: cold launch handoff, tab switches, flight catalogue/day/guided load, hotel snapshot read/write, hotel storefront prepare/indexing/journey load, image load, transfer prepare/confirm, final/manual quote, booking vault read/write/refresh. A signpost duration may include network wait and is not frame time. Cold launch handoff is not total OS launch time.

### Device release checklist
Run the same scenarios on the previous build and this build, same device, data, connectivity and Release settings. Repeat at least 10 times; record actual results, including slow outliers. Start with a cool device, repeat in Low Power Mode and after several minutes of continuous use.

| Scenario | Observe |
|---|---|
| Cold and warm launch, 10 tab switches | time to interactive, CPU, main-thread stalls |
| Flights: scroll quickly, change day/origin, choose outbound and return | hitches, stale results, duplicate requests |
| Hotels: fast scroll, open gallery and room, calendar and price changes | hitches, memory, stale prices, image requests |
| Flight-first and hotel-first configurator | selections, meals, transfer, ziyarat, quote, back navigation |
| Transfer: rapid vehicle swipes, train/VIP, confirm | frame time and correct selected service |
| Guest and signed-in bookings | booking ID, access, update/delete, restart and recovery |
| Background/resume, reduce motion, low power, offline/reconnect | idle CPU, stopped decorative ticks, functional state |
| Repeated catalogue and configurator cycles | sustained memory growth and thermal throttling |

Target: 60 Hz native interaction on iPhone 11 (16.67 ms frame budget), prompt input feedback, no sustained hitching or growth; compare actual metrics before accepting release. Validate network latency separately. Do not accept stale price, booking loss or altered API behavior as a performance tradeoff.

## Validation limits
Portable Swift parsing and smoke tests are not Xcode type checking, SwiftUI rendering tests or Instruments measurements. No physical iPhone or Xcode runtime was available for this patch. Release build, Instruments and full device regression remain required. No actual FPS, launch duration, or RAM savings are claimed.
