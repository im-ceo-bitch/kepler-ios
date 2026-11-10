# iumrah — Booking tab SwiftUI crash mitigation (2026-11-10)

## Evidence

Two device crash reports for iUmra 2.1.1 (222), iOS 27.2.1 (iPhone12,1), at 20:07:00 and 20:07:07 local time. Both show the main thread dying with `EXC_BAD_ACCESS / SIGSEGV` in a repeated `swift::Demangle::__runtime::TypeDecoder::decodeMangledType` / `decodeGenericArgs` sequence. The call path contains `swift_getTypeByMangledName`, `VStack.init`, and SwiftUI graph updates. This matches stack exhaustion during runtime metadata decoding for a deeply nested SwiftUI view type.

No backend/network error was observed in these reports; an exact line-level symbolication is unavailable without the release dSYM for build 222.

## Changes

- `Sources/Views/Tabs/BookingsHomeView.swift`: introduce `AnyView` runtime metadata boundaries around the tab root, scrolling header/content and active/empty booking branches.
- Split the active booking's three conditional panels into individually type-erased subtrees (`bookingPanelContent`) so opening the tab does not construct a generic union spanning progress, status and calendar branches.
- Add boundaries around complex booking sections (trip context, identity, flight details, cards) without removing or changing their actions.
- Retain navigation destinations, Telegram linking, refresh, status lifecycle, cancellation and all three booking sub-tabs.
- `Backend/PackageEngine/test/bookings-stack-overflow-client-contract.test.mjs`: regression checks that guard the new boundaries and retained features.

## Verification performed

- `swiftc -frontend -parse Sources/Views/Tabs/BookingsHomeView.swift`: PASS.
- 29 targeted existing/new Node contract tests: PASS.
- ZIP entries and CRC: PASS.

## Remaining verification

This environment cannot build an iOS binary using Xcode or run it on an iPhone. Compile in the existing GitHub Actions/TestFlight workflow, install the new build, then open Bookings with both (1) a saved active booking and (2) no active booking; switch between Booking / Status / Schedule and open the detail screen. If the same crash persists, upload the new `.ips` along with the build's dSYM to identify the remaining nested view precisely. Do not treat a successful static test as a verified on-device fix.

## Deployment

Upload the ZIP at the repository root and process it with the existing `iumrah-beta-update-...zip` unpacker. This is an **additive patch**, not a full-repository replacement. It contains no backend deployment changes and does not overwrite the earlier transactional email update.
