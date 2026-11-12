#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Can run locally with any Swift 5+ toolchain, including Linux.
BINARY="$(mktemp /tmp/iumrah-intelligence-smoke.XXXXXX)"
trap 'rm -f "$BINARY"' EXIT
swiftc -parse-as-library Sources/Core/AppConfig.swift Sources/Services/IumrahIntelligence.swift Tests/IntelligenceAnalyticsSmoke.swift -o "$BINARY"
"$BINARY"
