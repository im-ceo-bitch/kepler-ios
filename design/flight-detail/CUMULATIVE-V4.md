# Cumulative flight update V4 (iOS + Package Engine)

Base: kepler-ios-main 9. Upload this single archive to the root of the existing repository. It combines Native Hemisphere, Premium Flight Detail, Monochrome Hero V2 and Flight Selection V3, in that order. Newer versions win on overlapping paths. Earlier individual archives are not needed and must not be applied after this archive.

Includes the AeroDataBox backend endpoint and its tests, the native hemisphere component, and the latest iOS flight selection interface and centered price graph with haptics. No workflows, Cron configuration, or D1 migration files are included.

Deploy iumrah Package Engine first, then TestFlight. Configure AERODATABOX_RAPIDAPI_KEY and AERODATABOX_DAILY_REQUEST_LIMIT on the existing Worker to enable enrichment; without these the UI uses base flight data. No separate D1 migration is required for this patch.

Historical V2/V3 documentation describes the old standalone archives; this V4 contains their server dependency already.

This is a patch against the supplied base, not a full repository backup. If overlapping source files have since changed independently, review diffs before applying. Xcode compilation, on-device visual/haptic behavior, real API requests and Cloudflare deployment require verification.
