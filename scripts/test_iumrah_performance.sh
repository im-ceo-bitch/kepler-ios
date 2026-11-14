#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
{ echo 'import Foundation'; sed -n '/^enum IumrahFlightClock {/,/^}/p' Sources/Views/Flights/IumrahFlightResultCard.swift; } > "$tmp/FlightClock.swift"
swiftc -swift-version 5 Sources/Core/Components/IumrahViewMemo.swift Sources/FlightEngine/FlightReferenceCatalog.swift "$tmp/FlightClock.swift" Tests/IumrahPerformanceSmoke.swift -o "$tmp/performance-test"
"$tmp/performance-test"
