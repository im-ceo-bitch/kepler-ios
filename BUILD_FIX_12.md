# Build fix 12

Xcode archive 242 failed in IumrahFlightBrowseCatalog.swift:153. Remove duplicate date-specific cache guard from load(trip:language:force:); retain the guard in loadDay(_:trip:direction:language:). No other Swift source changes relative to update 11.

Validation: semantic typecheck of the actual flight browse model and extracted real models with mock UI/network dependencies; parse all 346 Swift source files; Smart static integration 14/14; mixed flight gate executable checks 18/18. Full Xcode archive not available on Linux.

The update 11 checksum manifest is historical; use BUILD_FIX_12.sha256 to verify this cumulative archive.
