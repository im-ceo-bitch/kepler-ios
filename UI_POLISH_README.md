# iumrah UI polish v1 · 2026-11-04

## Changes
- One shared five-tab black header: an accessible 48pt compact state on scroll; notification and menu actions remain interactive; brand, title and category rail smoothly yield viewport space.
- Hotels now uses the same collapse threshold; cleaner stage selector, search card outline and compact hotel-card typography.
- Home: hotel-search form first (Booking-like information architecture), followed by a smaller private-Umrah CTA without changing its destination or journey draft state.
- Care and Account: section scroll targets aligned to the top of their scroll viewport; restrained contact-card geometry.
- Home, Bookings, Care, Account and Hotels: unified practical bottom content breathing room with the system tab bar.
- Softer card outlines and neutral light page background. Business/API/network flows not changed.

## Apply
Upload `iumrah-beta-update-ui.zip` to the ROOT of the current `kepler-ios-main` GitHub repository main branch.
The existing `Apply iumrah Beta ZIP update` action applies relative `Sources/...` paths and removes the ZIP after applying. Do NOT unzip to an additional folder.
The TestFlight workflow is `workflow_dispatch` ONLY: start it manually after the apply action succeeds, and check its Release Xcode archive result before publishing.

## Checks run here
- Swift 6.2 syntax parse of all 285 files via `scripts/ci_preflight.py`: PASS.
- 54 client integration/contract tests: PASS.
- Full 138-case Node suite: 137 passed; one existing aviasales-data-contract fails because it expects `startFlightFirstTrip` in HotelsHomeView; that symbol was already absent in the INPUT ZIP, not changed here.
- True SwiftUI typechecking, iOS simulator screenshots, device Visual QA and signed Xcode build: NOT AVAILABLE on this Linux runner. Must be verified in macOS CI / TestFlight.

## Files
- Sources/AppShell/IumrahAccountView.swift
- Sources/Core/Components/IumrahSignatureChrome.swift
- Sources/Core/DesignSystem.swift
- Sources/Views/Home/HomeDashboardView.swift
- Sources/Views/Home/IumrahHomeHotelSearchView.swift
- Sources/Views/Hotels/NuiteeHotelsCatalogView.swift
- Sources/Views/Tabs/BookingsHomeView.swift
- Sources/Views/Tabs/CareHomeView.swift
- Sources/Views/Tabs/HotelsHomeView.swift
