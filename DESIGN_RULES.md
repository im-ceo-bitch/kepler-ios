# iumrah — DESIGN RULES (binding)

**Status:** Mandatory for every iOS patch, UI agent, screen and code review. Supersedes conflicting examples in older design notes. See also `IUMRAH_IOS_DESIGN_RULES.md`.

## Native Liquid Glass: absolute restriction

- On iOS 26+, navigation, sheet-dismissal, floating menu, phone and notification **chrome buttons** must be real SwiftUI `Button` using `.buttonStyle(.glass)` (or system `.glassProminent` when appropriate), `.buttonBorderShape(.circle)` for icon chrome and the standard iOS interaction system. For grouped controls use `GlassEffectContainer` only when actually needed. Native `Picker(.segmented)`, `NavigationStack`, `sheet`, toolbar and `refreshable` are preferred.
- Never emulate Glass with custom circles, translucent fills, `Material`, `blur`, `UIVisualEffectView`, gradients, strokes, shadows or bespoke animations. A decorative world-map background is content, NOT Glass.
- On iOS 17–25 use the system `.bordered` fallback with a circular border shape; do **not** synthesize Glass.
- The label inside a native glass icon button is the SF Symbol at ~17 pt in a 23×23 pt frame; **do not** embed a 48+ pt gray background shape inside the styled button. Let iOS size the control. Never use arbitrary oversized glass circles.

## CTA vs chrome: strict separation

- Main CTA: **solid, non-glass, full capsule** (`Capsule()`), adaptive full available width, **56 pt** height, semibold clear text, black/white brand contrast. No corner radius 12/14/18/22 masquerading as pill; no `.buttonStyle(.glass)` on CTA.
- All CTA instances should use `IumrahPrimaryButtonStyle` from `Sources/Core/DesignSystem.swift`. Secondary solid capsules use `IumrahSecondaryButtonStyle`.
- The appearance in the supplied Spyder Wallet screenshot is the visual reference for capsule proportion, not a requirement to reuse the Spyder branding or color palette.

## Journey composition

- The black world-map header and its native chrome scroll **with** content. Do not pin a black navigation rectangle to the top. At rest the status-bar-safe-area background is black; after hero scrolls away it transitions to page color.
- The white search/route disclosure card sits approximately **half above and half below** the black-to-white/gray page boundary. It has a continuous **30 pt** radius and a subtle muted emerald outline (not sand/gold).
- Tap the search summary to **expand inline**. Show human-readable travelers, cabin and travel dates, not `2 + 0 + 0`. Edit flight search atomically, invalidating previous offers and quotes.
- Nuitee is the only publicly exposed hotel catalogue. D1/Business hotel catalogue is compatibility-only for already persisted links and legacy server quotes. New Flight First routes use supplier hotel IDs, offer IDs, exact dated rates, and one customer-visible subtotal computed from the actual chosen components.
- `ScrollView.refreshable` provides the native pull-to-refresh progress indicator. Never disable `UIScrollView.bounces` on these screens. On refresh recheck supplier hotel rates; if a selected offer disappears, invalidate the amount.

## Money and trust

- A cached Data API flight fare and a Nuitee room rate are **not a bookable package quote**. Do not display fabricated total prices for unknown passenger types, multiple rooms, or a missing supplier rate. Show `—` and explain why.
- The temporary on-device configurator uses **actual displayed, selected Data API flight fares and Nuitee hotel room totals**, plus the existing public PackageEngine service-price formula (tier-based markup, 2% fee, rounding, visas, meals, guides, transfers, ziyarat and optional add-ons). No provider secrets leave the Worker. All missing airfare variants and supplier rates remain unknown, never $0.
- The derived full-package figure is **a local estimate**, not a server-verified offer. A supplier price shown to customers may differ from internal wholesale cost, and availability may change.
- A full package checkout requires real flight availability, Nuitee revalidation/prebook/booking, authorization and a server-confirmed total. The local sum is labeled **preliminary subtotal of selected components**, not payable price.

## QA gate

Review iPhone 11, iPhone 13 mini, iOS 26 native controls, iOS 17 fallback, long names, Dynamic Type, VoiceOver, dark mode, both Saudi arrival airports, Makkah-only vs two cities, expired rates, no flight fare, USD currency, child/infant and multi-room limitations, pull-to-refresh when overscrolling. No acceptance without a native Xcode build and visual QA on simulator/device.

## Shared black header — 2026-11-08 update

- `IumrahSignatureHeaderGeometry` is the only accepted source for hero top inset (14 pt), wordmark region (57.6 pt), bottom inset (80 pt), corner radius (30 pt), and journey summary overlap (46 pt). Home bottom inset was increased from 60 by 20 pt.
- The Home wordmark is centered; in **Hotels, Bookings, Care, and Account** the smaller wordmark is left-aligned, with notification and menu controls on the right. All five have the same black world-map frame height, all scroll away with the page.
- The Flight, Hotel, Transfer and Review screens use `IumrahJourneyHeader`, which shares exactly those metrics; search disclosure expansion must never resize the black region.
- Hide the native bottom TabView bar ONLY while a journey destination is pushed (`.toolbar(.hidden, for: .tabBar)`). Restore it automatically on pop to one of the main five tabs. Do not replace it with a fake bar.
- `Nuitee` alone is the customer-facing Hotels tab source. The old D1 catalogue remains internal for preexisting deep links and stored bookings.
- Per-adult Data API flight prices are not valid child or infant fares; suppress the aggregate estimate until the fare mix is known. On refresh, revalidate exact selected Nuitee room offers; an unavailable rate invalidates that room and total. `Care` request = availability inquiry, NOT paid/confirmed booking.
