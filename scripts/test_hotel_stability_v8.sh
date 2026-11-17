#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
swiftc -swift-version 5 Sources/Services/IumrahHotelReviewCache.swift Tests/IumrahHotelReviewCacheSmoke.swift -o "$tmp/reviews"
"$tmp/reviews"
swiftc -swift-version 5 Sources/Models/IumrahHotelRoomTitle.swift Tests/IumrahHotelRoomTitleSmoke.swift -o "$tmp/rooms"
"$tmp/rooms"
swiftc -swift-version 5 Sources/Models/IumrahHotelPhotoSignature.swift Tests/IumrahHotelPhotoSignatureSmoke.swift -o "$tmp/photos"
"$tmp/photos"
