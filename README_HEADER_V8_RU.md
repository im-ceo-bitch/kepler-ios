# iumrah — Header & Refresh Architecture V8 (31.10.2026)

## Changes
- One continuous black header on all 5 root tabs; no second black header drawn in ScrollView.
- Brand+title collapse on scrolling; selector remains pinned, left-aligned.
- Refreshable ScrollView starts below entire black header; overscroll stays light.
- The iOS safe-area above is black.
- Home prayer/weather expandable section is rendered inside the same black header.
- Nuitee, Umrah Flow, room photos, API, source of prices, bundle ID, workflow and build number unchanged.

## Application
Apply only over repository with V7 (which itself requires V5 + V6).
ZIP contains source files under Sources/...; do not unzip nested archives.

## QA LIMITATIONS
Linux Swift parser processed all source files in reconstructed repository; not Xcode compile/typecheck.
Native iOS pull-to-refresh spinner placement and scroll animation require testing on-device.
Do not send straight to TestFlight before build-only CI succeeds.
