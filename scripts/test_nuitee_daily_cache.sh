#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Use the actual Codable meal model without importing the unrelated UI model graph.
sed -n '/^struct HotelMealChoices: Codable, Hashable {/,/^}/p' Sources/Models/LocalJourneySelection.swift > "$tmp/HotelMealChoices.swift"
swiftc -swift-version 5 Sources/Models/NuiteeHotelModels.swift Sources/Services/NuiteeDailyHotelCache.swift "$tmp/HotelMealChoices.swift" Tests/NuiteeDailyHotelCacheSmoke.swift -o "$tmp/cache-test"
"$tmp/cache-test"
