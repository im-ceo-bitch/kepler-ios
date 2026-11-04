# iumrah Orbit — native SwiftUI integration (4 November 2026)

## Integrated

- `Sources/Views/Components/IumrahOrbitIconRing.swift`: reusable iOS 17+ SF Symbols / Canvas / TimelineView orbit. Modes: `showcase`, `progress(completed:active:)`, `assembling`.
- Onboarding: last page uses a large orbit (only animates while its page is active).
- Home: Configurator product card uses a compact orbit. The detailed system connections diagram remains intact.
- Guest Account: orbit card with functional Sign In / Register buttons selecting and scrolling to the existing login form. Identity unlock and account methods remain available.
- Generator: 5-stage strip uses circular, status-aware SF Symbol indicators. Stage selection is read from the existing `TripProgressStage`.
- Final Package: after a valid package quote exists, a one-shot merge animates services represented by the actual JourneyStore selections. It is strictly visual; the existing confirmation and booking API paths are untouched.

## Apply with existing GitHub unpacker

Upload `iumrah-beta-update-orbit.zip` to **repository root on `main`**. Its exact name matches the existing `.github/workflows/apply-beta-update.yml` trigger (`iumrah-beta-update-*.zip`). Files are relative to repository root with no `kepler-ios-main/` prefix. Don't use the full repository ZIP as a patch.

## Test checklist (Xcode 26/macOS required)

1. Generate the project from `project.yml` using the repository's existing XcodeGen procedure.
2. Perform an unsigned **build-only** for the `iUmra` iOS scheme (preferably through existing CI), then TestFlight.
3. Check last onboarding page on small and large iPhones, and the Configurator Home tile.
4. On guest Account, test that Sign In and Register reveal the correct existing form and that identity unlocking still works.
5. Walk through generator stages and verify the current stage indicator and the final assembling animation. Verify booking is created **only after** existing confirmation succeeds.
6. Check VoiceOver, Reduce Motion and foreground/background behavior.

## Verification executed here

- Parsed all Swift source files with `swiftc -frontend -parse` on Linux.
- Inspected `project.yml` source inclusion and repository patch unpacker compatibility.
- Validated patch paths and archive CRC/integrity.

An Apple SDK/Xcode compile, simulator run and TestFlight build are **not** available in this environment, so this patch must pass your real Xcode build-only CI gate before release.
