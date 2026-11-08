# iumrah Services — iOS ZIP update · 2026-11-08

This is a **cumulative overlay ZIP** intended for the existing `apply-beta-update.yml` workflow. Upload the ZIP at the repository root on `main`. The existing unpacker copies paths relative to the repository root; **do not unpack into an extra `kepler-ios-main/` directory**.

## Changed files

- `Sources/Views/Home/HomeAppleStoreSections.swift`: updates only `IumrahHomeServicesSection`, retaining its original `onTransfer`, `onESIM`, `onFlights`, `onZiyarats` initializer for compatibility with existing HomeDashboard code.
- `Sources/Views/Home/IumrahServicesView.swift`: single source of truth for service data, localizations (RU/EN/UZ Latin/UZ Cyrillic), compact cards and the dedicated accordion screen. NavigationLink opens with the originating service expanded and scrolls to it.
- `Resources/Assets.xcassets/IumrahVisaServicesHero.imageset/*`: self-contained document illustration for the visa service, based on the repository's existing Riyadh background; does **not** reproduce an official government visa.
- `Resources/Assets.xcassets/IumrahServicesFlightHero.imageset/*`: existing iumrah plane imagery recropped for consistent presentation.

Other service images are reused from existing assets: `MakkahBackground`, `TransferCarnival`, `GiftCardJourney`, `ZiyaratQuba1`, `HaramainHero`, `ZiyaratQuba3`, `IumrahESIMHomeCard`.

## Feature behavior

1. Home section heading `Сервисы iumrah`, explanatory subtitle, horizontal carousel (visa first) and `Все сервисы` link.
2. Each carousel card navigates to `IumrahServicesView`, with matching service expanded and scrolled into view.
3. Collapsed/expanded service sections share visuals and copy with the carousel.
4. Visa section clarifies single-entry vs multiple-entry, 90-day vs 1-year validity, stay duration, Umrah vs Hajj, and discretionary issuance. Official KSA Visa link included.
5. Optional Haramain and digital add-ons are not asserted to be included in every purchased package.
6. No third-party runtime image requests or mock Liquid Glass elements.

## Verification and source limitation

Source replacement was prepared against the latest iOS archive accessible to this session (`kepler-ios-main 2(9).zip`, dated 2026-10-08). The original HomeDashboardView and GitHub workflows are **not included**, reducing the risk of overwriting newer app routing and release changes. **If HomeAppleStoreSections.swift has been changed since that archive, review the diff before applying**, because the ZIP replaces that whole file. Swift files passed a `swiftc -frontend -parse` check, not a full iOS Xcode compile, since the macOS SDK is not available here.

The original image files behind the earlier inline design preview cannot be extracted from that preview. This ZIP contains bundled project imagery and a new visa illustration in a similar layout, not pixel-identical copies of the remote preview photos.
