# iumrah Package Engine — Cloudflare Cron quota fix (2026-11-12)

Log `logs_116909205361.zip`: Cloudflare API error 10072. The Worker upload and route changes succeeded; cron configuration failed because the free account allows five triggers total. Subsequent secret installation and health check were skipped by GitHub Actions.

## Changes

- Production Wrangler config registers one trigger (`*/5 * * * *`) instead of four.
- The Worker dispatches four existing maintenance tasks using the UTC scheduled event timestamp. Booking emails every 5 minutes, hotel catalogue hourly at :25 (previously :23), full hotel/price refresh daily at 03:00, flight cache cleanup daily at 00:20 (previously 00:17).
- Obsolete cron events are ignored during configuration propagation; errors in one job do not block other due jobs and are reported as failures.
- No D1 schema, API routes, secrets, GitHub workflows, iOS UI or pricing changes.

## Deployment

1. Upload this ZIP to the root of `kepler-ios` and let Apply iumrah Beta ZIP update finish.
2. Run the existing `Deploy iumrah Package Engine` workflow again (it runs the schema steps and installs secrets itself). No separate D1 migration is needed.
3. If Cloudflare still reports 10072, all five cron slots may belong to other Workers. In the Cloudflare dashboard inspect Workers & Pages -> each Worker -> Settings -> Triggers/Cron Triggers. Free one unused slot or consolidate existing schedules after identifying their purpose. Do not remove active schedules blindly. This patch cannot change other Workers' configuration.
4. Check that the workflow proceeds beyond `Deploy Package Engine routes` through secret installation and its final health check. Confirm the Worker has exactly one cron trigger. Cloudflare configuration propagation can take time.

## Verification

Against the uploaded repository with the previous 2026-11-11 patch applied: TypeScript typecheck passed; 148 contract tests and 52 runtime tests passed (including three new schedule tests). Production deployment and Cloudflare account's remaining trigger quota cannot be verified locally.
