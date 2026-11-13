#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BIN="$(mktemp -d)"
trap 'rm -rf "$BIN"' EXIT
swiftc Sources/Core/Components/IumrahHemisphereProjection.swift \
  Sources/App/IumrahLaunchGeometry.swift Sources/App/IumrahLaunchLandDots.swift \
  Tests/IumrahLaunchGeometrySmoke.swift -o "$BIN/launch-smoke"
"$BIN/launch-smoke"
