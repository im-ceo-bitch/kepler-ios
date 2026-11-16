#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
sed -n '/^struct HotelMealChoices: Codable, Hashable {/,/^}/p' Sources/Models/LocalJourneySelection.swift > "$tmp/HotelMealChoices.swift"
swiftc -swift-version 5 Sources/Models/NuiteeHotelModels.swift "$tmp/HotelMealChoices.swift" Tests/NuiteeHotelPageCompatibilitySmoke.swift -o "$tmp/page-test"
"$tmp/page-test"
