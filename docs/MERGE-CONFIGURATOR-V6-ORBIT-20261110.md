# Merge report — Configurator Booking V6 + Orbit Visible V2

## Installation
Upload **only** `iumrah-beta-update-20261110-configurator-v6-orbit-merged.zip` to the GitHub repository root and apply it with the existing ZIP workflow. Do not install either source update separately. This is an incremental update using root-relative paths, not a complete repository.

## Source precedence and resolution
- Configurator Booking V6 is authoritative for booking, PackageEngine, Nuitee, confirmation, quote, and pricing logic.
- Orbit V2 contributes visible UI on Home, product card, onboarding, guest Account, circular generator stages and package assembly.
- Six file paths overlapped. Four V6 files were byte-identical to base repo8 before Orbit changed only visual UI.
- The V6 `LocalJourneyReviewView.swift` replaces obsolete local Care checkout and **must remain unchanged**. The Orbit card is instead inserted inside `LegacyFinalPackageView`, shared by both local and legacy reviews (one extra UI line).
- Four regressions found by comparing V6 with the **current** `kepler-ios-main 8.zip` were resolved, without removing V6's booking changes:
  1. `Backend/PackageEngine/src/env.ts`: kept four existing BOOKING_SUPPORT_* secret definitions.
  2. `Backend/PackageEngine/src/index.ts`: retained booking email avatar image route and its import.
  3. `Backend/PackageEngine/scripts/runtime-tests.sh`: runs **both** V6 configurator booking runtime tests and the existing booking-email-design runtime test.
  4. `Sources/Views/Tabs/BookingsHomeView.swift`: retained the newer type-erased scroll root that was introduced to prevent the iOS 27 booking tab runtime metadata crash. V6's older view changed only that regression workaround and a cosmetic CTA; no V6 booking logic is dropped.
- Updated the existing Home Configurator UI contract test to assert the new Orbit ring (rather than the removed static image), retaining the original card height and color checks. No test is disabled.
- Intentional V6 replacement of flight selection UI and local pricing/checkout remains: these are V6's functional changes, not conflicts with Orbit.

## Integrity
- Original V6 hashes: `docs/UPDATE-V6-SHA256-before-merge.json` (unaltered snapshot).
- V6 file paths with final merged hashes: `docs/UPDATE-V6-SHA256.json`.
- Every actual source file in the merged ZIP: `docs/UPDATE-MERGED-SHA256.json`.
- Source V6 entries: 91; Orbit entries: 9; overlapping paths: 6.

## Build & deployment limitations
- Xcode/iOS SDK archive and on-device UI/booking smoke tests must run in GitHub Actions or on a Mac.
- Apply both iOS and PackageEngine changes. Deploy PackageEngine before using the V6 configurator; do not create real bookings with sandbox provider credentials.
- Canonical `/api/bookings` service is external to PackageEngine and is not covered by this ZIP.
- Review `docs/UPDATE-20261110-CONFIGURATOR-BOOKING-V6.md` for V6 implementation boundaries and test caveats.
