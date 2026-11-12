# iumrah Beta — Package Engine log fix (2026-11-11)

Patch type: cumulative overlay on kepler-ios-main.zip (11 Nov 2026).
Unzip at the repository root. Paths intentionally do NOT include kepler-ios-main/.

What changed
- Bookings tab: break large SwiftUI navigation/body into erased root, branches and independent booking/status/calendar panels to limit type-checking complexity while retaining each view.
- Account: use existing verified Email/SMS OTP authentication instead of legacy password/iumrah ID entry; no account identifier or database schema change.
- Booking number labels: localize account and booking detail headers.
- Root: immediately synchronize selected app language to Widget snapshot.
- Tests: migrate obsolete assertions about retired Orbit graphic and package-tier carousel to current Home configurator CTA and server-priced review. Preserve pricing and auth contract coverage.

Validation performed locally (Node 22):
- npm run typecheck — passed.
- npm test — 148/148 source/contract tests and 49/49 compiled runtime tests passed.
- swiftc -frontend -parse on the changed SwiftUI sources — passed.
- iOS full Xcode/TestFlight build NOT available on Linux; run your TestFlight workflow to validate Swift type-checking and device runtime.

Deployment:
1. Upload this ZIP to main at repository root; apply-beta-update.yml extracts it.
2. After its apply job succeeds, rerun `Deploy iumrah Package Engine` manually if required. Its D1 migration steps are built into the workflow; no separate manual migration is necessary for this patch.
3. Build the iOS TestFlight app from the updated repository to ship client UI changes.

Note: Package Engine Worker runtime/DB migration files were NOT modified by this patch.
