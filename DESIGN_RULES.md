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

- On the **five primary tabs**, the black world-map masthead **scrolls away with the page when the user swipes up**; it is never pinned. When the user is already at the top and pulls down to refresh, only the content below the masthead reveals the indicator; the masthead itself does not stretch or descend. At rest, the status-bar safe area is black. Pushed journey-stage headers follow their own existing scroll behavior.
- The white search/route disclosure card sits approximately **half above and half below** the black-to-white/gray page boundary. It has a continuous **30 pt** radius and a subtle muted emerald outline (not sand/gold).
- Tap the search summary to **expand inline**. Show human-readable travelers, cabin and travel dates, not `2 + 0 + 0`. Edit flight search atomically, invalidating previous offers and quotes.
- Nuitee is the only publicly exposed hotel catalogue. D1/Business hotel catalogue is compatibility-only for already persisted links and legacy server quotes. New Flight First routes use supplier hotel IDs, offer IDs, exact dated rates, and one customer-visible subtotal computed from the actual chosen components.
- Use `IumrahRootScrollingPage` on the five root tabs: its native `ProgressView` indicator appears **below** the masthead and its refresh action fires only after a deliberate top-of-page pull. Do **not** attach `.refreshable` to the whole root `ScrollView` (UIKit would show the indicator above the masthead). Never disable `UIScrollView.bounces` on these screens. On journey refresh recheck supplier hotel rates; if a selected offer disappears, invalidate the amount.

## Money and trust

- A cached Data API flight fare and a Nuitee room rate are **not a bookable package quote**. Do not display fabricated total prices for unknown passenger types, multiple rooms, or a missing supplier rate. Show `—` and explain why.
- The temporary on-device configurator uses **actual displayed, selected Data API flight fares and Nuitee hotel room totals**, plus the existing public PackageEngine service-price formula (tier-based markup, 2% fee, rounding, visas, meals, guides, transfers, ziyarat and optional add-ons). No provider secrets leave the Worker. All missing airfare variants and supplier rates remain unknown, never $0.
- The derived full-package figure is **a local estimate**, not a server-verified offer. A supplier price shown to customers may differ from internal wholesale cost, and availability may change.
- A full package checkout requires real flight availability, Nuitee revalidation/prebook/booking, authorization and a server-confirmed total. The local sum is labeled **preliminary subtotal of selected components**, not payable price.

## QA gate

Review iPhone 11, iPhone 13 mini, iOS 26 native controls, iOS 17 fallback, long names, Dynamic Type, VoiceOver, dark mode, both Saudi arrival airports, Makkah-only vs two cities, expired rates, no flight fare, USD currency, child/infant and multi-room limitations, pull-to-refresh when overscrolling. No acceptance without a native Xcode build and visual QA on simulator/device.

## Shared black header — 2026-11-08 update

- `IumrahSignatureHeaderGeometry` defines the shared hero top inset (14 pt), wordmark region (57.6 pt), bottom inset (80 pt), **Home-only** lower corner radius (30 pt), and journey summary overlap (46 pt). Home bottom inset was increased from 60 by 20 pt.
- The wordmark is **geometrically centered on all five primary tabs**, with identical dimensions (187.2 × 57.6 pt). Use `IumrahPrimaryHeaderBrandRow` consistently: native menu button on the left, notification button on the right. All five scroll upward with their content. Four non-Home tabs have a **straight lower header edge**; only Home retains its 30 pt lower rounding.
- The Flight, Hotel, Transfer and Review screens use `IumrahJourneyHeader`, which shares exactly those metrics; search disclosure expansion must never resize the black region.
- Hide the native bottom TabView bar ONLY while a journey destination is pushed (`.toolbar(.hidden, for: .tabBar)`). Restore it automatically on pop to one of the main five tabs. Do not replace it with a fake bar.
- `Nuitee` alone is the customer-facing Hotels tab source. The old D1 catalogue remains internal for preexisting deep links and stored bookings.
- Per-adult Data API flight prices are not valid child or infant fares; suppress the aggregate estimate until the fare mix is known. On refresh, revalidate exact selected Nuitee room offers; an unavailable rate invalidates that room and total. `Care` request = availability inquiry, NOT paid/confirmed booking.

## Five primary tabs and three searches — 2026-11-08 night revision

- All five root headers start at the **physical top edge** of the device: the **status bar must be white on the black header**, never white-on-white. Root NavigationStack backgrounds must not extend the page-gray fill over the top safe area. The five root headers belong inside the same page scroll as the content, and MUST scroll away on upward swipes.
- The black hero's content height is **151.6 pt**, excluding the actual device status-bar safe area. The four non-Home tabs use the **same 187.2 × 57.6 pt wordmark** as Home. All five center the wordmark using a symmetrical menu-left / notifications-right row. Do not move both buttons to the right where they collide with the centered logo.
- Header navigation symbols are **native circular `.glass` / `.buttonBorderShape(.circle)` controls** on iOS 26. Do not force oversized custom circle backgrounds or use blurred images to approximate them. No duplicate custom back controls in journey stages.
- Account: title and concise subtitle inside black hero. Bookings: title and **Booking / Status / Schedule** capsule selection inside hero **only with an active booking**. Care: title, then **Call / Telegram / Chat** capsule actions inside hero; chat requires an existing booking ID, not an invented conversation.
- Hotels public root is rebuilt from zero. Exactly three modes: **Hotels / Flights / Weekends**, each with its own input form but a consistent visual envelope. Hotels uses city, optional hotel name, stay dates, nights, room count, adults, children and children's ages; Flights uses origin, destination, outbound/return dates, adults/children/infants and cabin; Weekends uses origin, travel start, 2–4 nights and passenger mix. Search must open the existing supplier-backed results, not placeholder lists.
- **Hotels-tab search-card border** overrides the earlier emerald rule **for this card only**: corner radius **40 pt**, monochrome animated angular-gradient outline **3.5 pt**, with `TimelineView` paused in background and when Reduce Motion is enabled. This animation is **ordinary brand decoration, never Liquid Glass**. The solid black CTA remains a 56-pt capsule.
- Nuitee catalog is the only public hotel source. An occupancy request involving >1 room, children, or >6 adults may show a **rate-free hotel discovery list** but **must not pretend a single adult-rate room is a confirmed group quote**; provide direct Care inquiry instead. Never expose vendor credentials in the app.
- Bottom native TabView remains visible on primary tabs, disappears in pushed configurator/search or Care request views, and reappears on pop.

## Root refresh and Services integration — 2026-11-09

- **Each main tab has one `IumrahRootScrollingPage`**, containing the masthead and page content in a single `ScrollView`. Do not pin the masthead in a surrounding `VStack`. This wrapper uses overscroll compensation and the system `ProgressView` below the masthead, rather than `.refreshable`, which would position `UIRefreshControl` above the masthead.
- The Home tab also supports the shared pull-to-refresh; it reloads bookings, customer notifications and public storefront data. The four other tabs refresh their existing data flows. The spinner appears immediately **below** the non-stretching masthead during top-edge overscroll.
- Preserve the approved **28 pt Home** and **40 pt Hotels** search-card overlaps while allowing the entire hero to scroll away. These overlaps must not cover the pull-to-refresh spinner beneath the masthead.
- Home's dynamic headline animation remains active in the scrolling search surface; it must not be tied to the header-only component after splitting the views.
- The 2026-11-08 Services ZIP is preserved. `IumrahHomeServicesSection` opens `IumrahServicesView` for the selected service and the assets `IumrahVisaServicesHero` and `IumrahServicesFlightHero` remain required. For `AppSettingsStore.Language` cover Russian, English, Uzbek Latin, Uzbek Cyrillic, Turkish, Indonesian, Malay and Arabic in every exhaustive language switch; unsupported translations may fall back to English.


## Root-tab vertical scrolling (2026-11-09)
- All five tabs share one scrolling coordinate space that **includes the black masthead**. Swiping UP must scroll the header entirely away, with no sticky/pinned overlay.
- Pulling DOWN while already at the top must NOT stretch the masthead. Only the content beneath it reveals the system ProgressView indicator.
- Never put `.refreshable` on a ScrollView that contains the black masthead: native UIRefreshControl would render ABOVE the masthead. Use `IumrahRootScrollingPage` for under-header refresh.
- Do not nest a second vertical ScrollView inside `IumrahRootScrollingPage`; nested scrolling would leave the masthead pinned.
- Home search-card overlap 28 pt; Hotels search-card overlap 40 pt. Keep native Liquid Glass controls and iumrah Services intact.

## Centered shared branding and flat root headers — 2026-11-09 (latest)

- **All five primary tabs**, including Hotels, Booking, Support and Account, must use exactly the same wordmark size and geometrical center alignment as Home (`IumrahPrimaryHeaderBrandRow`). Menu is left, notifications right. These are official system Liquid Glass controls on supported iOS versions; never simulate them.
- Root titles in Hotels, Booking, Support and Account use `IumrahType.bold(28, relativeTo: .largeTitle)`; the Home search headline is 22 pt Lato Bold. Make headings legible without truncating the action capsules or stretching the masthead.
- Only **Home** rounds the two lower corners of its black world-map header (`bottomRadius = 30`). The other four primary tabs have a **completely square bottom edge**. This does not alter the journey-stage header geometry.
- Search cards on Home and Hotels are allowed to visually overlap the black hero. Never give the scroll masthead a foreground `zIndex` that covers the title or inputs in the top of these cards. Never cap the top-overscroll offset compensation: even a strong downward pull must not reveal empty space above the masthead.
- Existing scroll requirement remains: header scrolls away on UP swipe; it does not stretch on top-edge pull; refreshing appears immediately below. Do not pin it while scrolling.
