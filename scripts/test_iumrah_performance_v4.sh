#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
find Sources -name '*.swift' -print0 | xargs -0 swiftc -frontend -parse
for test in test_iumrah_performance test_iumrah_image_coordinator test_nuitee_daily_cache test_iumrah_launch_geometry test_iumrah_performance_v3; do
  bash "scripts/${test}.sh"
done
if [[ "${1:-}" == --xcode-build ]]; then
  command -v xcodebuild >/dev/null || { echo 'Xcode is required for the iOS build.' >&2; exit 1; }
  command -v xcodegen >/dev/null || { echo 'XcodeGen is required.' >&2; exit 1; }
  xcodegen generate
  xcodebuild -project iUmra.xcodeproj -scheme iUmra -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
fi
