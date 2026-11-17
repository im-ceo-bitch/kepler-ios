# Official hotel pagination — iOS V6

Cumulative V1–V5 plus shared official/manual hotel paging. The current official flight-first entry navigates to `NuiteeJourneyHotelsView`; Smart editing also uses it. Both now use the same `NuiteeCatalogModel` as the manual Hotels tab. One page requests 12 hotels. The existing page button appends results by stable hotel ID, prevents concurrent clicks, preserves previous rows if a page fails, and stops when no advancing cursor remains. Returning from details preserves loaded pages for an unchanged search. City, dates, occupancy and star filter determine search identity. The legacy PrimaryHotel path and manual family catalogue also reveal 12 at a time with the existing button, not automatic onAppear expansion. No prices are invented or availability inferred from catalogue data.

Older full-catalogue API responses are sliced in memory (bounded, per-service cache; first page refreshes). Modern server pagination is accepted, including total-only and cursor-only responses. A failed page can be retried. This cannot add hotels not returned by the live backend.

Includes V5 booking creation notification intent (see BOOKING-CREATION-NOTIFICATIONS-20261117.md). The client supplies verified contact and optional APNs token, and safely routes a booking-created push. Remote delivery and idempotent server outbox still require the live Worker changes. No workflows, Business, Android, web or deployed server modified.

Tests: actual Swift page model smoke test including 35 hotels in 12/12/11 batches, deduplication, older/current response formats, plus booking notification encoding, guest Care, seamless booking, Smart and performance regression scripts. No Xcode/device or production API verification in this environment.
