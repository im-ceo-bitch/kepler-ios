#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^@MainActor$/,/^struct NuiteeHotelsCatalogView: View {/p' Sources/Views/Hotels/NuiteeHotelsCatalogView.swift | sed '$d'; } > "$tmp/Catalog.swift"
sed -n '/^struct HotelMealChoices: Codable, Hashable {/,/^}/p' Sources/Models/LocalJourneySelection.swift > "$tmp/HotelMealChoices.swift"
swiftc -swift-version 5 Sources/Models/NuiteeHotelModels.swift "$tmp/HotelMealChoices.swift" "$tmp/Catalog.swift" Tests/NuiteeCatalogHydrationSmoke.swift -o "$tmp/smoke"
"$tmp/smoke"
