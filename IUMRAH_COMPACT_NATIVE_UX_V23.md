# iumrah V23 — compact native UX

Cumulative client patch: includes every V22.1 path. Apply to kepler-ios only. No workflow, D1, backend, secret, or pricing changes.

- Nuitee hotel detail: a single meal preference card directly after the stay summary in package selection. The chosen offer still supplies its own included meals to the existing pricing contract. No local price formula.
- Root tabs: explicit help context in the header, bell + question in one native glassEffect capsule. Help dismisses 2.5 seconds after typing or on outside tap.
- Flight detail: all six callers use NavigationStack system back, native ToolbarItemGroup for share/help; original hero remains. Custom flow headers use native glass APIs (legacy OS fallback).
- Compact search: remove duplicate padding, smaller fields, bounded expanded viewport (330pt, 420pt for accessibility), scroll for longer forms without clipping fields. Guided flight editor and transfer/package disclosure included.
- Booking identity: actual stored booking number, pilgrim ID and traveler name, per-field copy feedback, original 94pt suitcase on the right. No synthetic IDs.
- Sign-out: adaptive-height native sheet, SF Symbol, no neon artwork.

Verification: full repository preflight (321 Swift files parsed; 435 language switches; 95 assets/plists), 12 cache smoke checks, 12 launch geometry checks, 13 structural checks. Linux cannot typecheck SwiftUI or run Xcode/iPhone; visual/native interaction and end-to-end flows must be tested in TestFlight.
