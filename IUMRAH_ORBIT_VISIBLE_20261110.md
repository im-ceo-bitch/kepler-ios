# iumrah Orbit visible / November 10, 2026

Source repo: kepler-ios-main 8.zip. This is an incremental ZIP for the existing apply-beta-update workflow.

1. Home > Build your Umrah > Configurator: visible animated orbit replaces static illustration.
2. Home > Our products > Configurator: larger, longer icon reveal remains.
3. Onboarding: final screen only (shown on first-run onboarding, not every app launch).
4. Account > guest: animated introduction with Sign in / Register buttons. These scroll to the existing authentication form and choose the corresponding mode.
5. Generator: compact five circular, non-interactive stage indicators based on the actual current stage replace the old 3D stage carousel.
6. Final package > Local journey and Legacy journey: selected real services animate toward the centre. This is a visual preview BEFORE confirmation, not a booking or payment success signal.

Animation: 72 dots, native SwiftUI Canvas+TimelineView, orbit spin and one-by-one SF Symbol reveal, larger and longer icon holding; Reduce Motion honoured.

Build: all 305 Swift files passed swiftc -frontend -parse (syntax only), but full Xcode compilation, TestFlight upload and device QA cannot be performed in this environment.

Installation: upload only this ZIP to the GitHub repo root on main. The workflow matches iumrah-beta-update-*.zip and applies paths relative to repo root.
IMPORTANT: This ZIP is based on kepler-ios-main 8.zip; if you made newer modifications to the eight same files, resolve conflicts before overlaying.
