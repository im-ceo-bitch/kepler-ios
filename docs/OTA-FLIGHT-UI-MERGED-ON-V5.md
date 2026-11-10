# iumrah iOS — OTA Flight UI merged with V5 (2026-11-10)

Apply ONLY after ui-flights-v5. This is an incremental patch: it does NOT contain or replace other V5 code.

Changes: 3 SwiftUI files (2 merged existing files, 1 new shared component).
Preserved: V5 date/airline/nonstop filters, sorting, price calendar, loadDay, confirmed arrival values and estimated arrival fallback, help panel, configurator source compatibility and selection, hotel/booking flow.

No backend, workflows, models, API or SQL modifications.

Build iOS via the existing TestFlight workflow and manually inspect both light/dark modes. The Linux Swift parser is not an Xcode build.
