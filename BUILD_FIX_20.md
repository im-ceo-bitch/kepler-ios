# iumrah Beta — Build Fix 20 (Account / Profile 2.0)

Based on cumulative update 19. Fixes Xcode compile error in `Sources/AppShell/IumrahAccountView.swift:295`: 'AccountRewardsPage' is inaccessible due to 'private' protection level.

The `Saved hotels` navigation now opens the existing `NuiteeHotelsCatalogView(refreshSignal: 0, favoritesOnly: true)` in a scrolling destination, with a localized title. This does not change the hotel catalog logic, saved favorites data, Home 2.0, Profile 2.0 design, booking, or backend.

Validation: log analysis and Swift syntax parsing on Linux. Full iOS Xcode archive and device testing are not available in this environment.

To install after Update 19, use the small `iumrah-beta-update-account-build-fix-20.zip` patch. To apply all changes on a fresh base, use the cumulative version.
