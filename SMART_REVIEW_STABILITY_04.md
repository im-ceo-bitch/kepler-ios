# Smart Configurator / Trip Summary stability 04

Cumulative iOS update against `kepler-ios-main 5.zip` + Trip Summary stages 01–03. No Business or backend changes. Existing `iumrah-beta-update-*.zip` workflow extracts this archive at repository root.

## Evidence and mitigation
- Screenshots show 29 November JED departure as 16:40 in the flight card and 14:40 in the local-time row. The shared card formatted departure in the device timezone; it now uses origin airport timezone and interface locale. Assembly previews are synchronized with the final sealed quote.
- The same hotel was repeated once per room. Smart now shows one compact city/hotel card, the room allocations, nights, rates, and verified city total (estimated room totals while searching). Starting room count is ceil(adults/5); if compatible supplier rooms are not found, Smart retries with additional rooms within the existing automatic allocation range. Children are checked by supplier, not counted toward the adult-only minimum. Existing initial Smart passenger age and party-size fare restrictions remain unchanged; supplier-compatible rates and seats are still mandatory.
- Review destination retains the exact validated JourneyStore and explicitly supplies environment stores. Review opening requires a sealed server quote, both flights, confirmed adequate transfer, matching room counts, hotel identities, dates, adult/child occupancy and positive USD rates. Failed/expired state is not treated as a confirmed package.
- SwiftUI runtime generic-type boundaries across navigation, sheets, Smart step views, review sections and card content; lazy review sections. This mitigates the same class of excessive nested SwiftUI metadata observed in the earlier Booking-tab crash, but the current crash stack is not available and exact root cause is unconfirmed.
- Defensive guard for malformed mixed itinerary identifiers, invalid room ranges, and nonfinite/out-of-range hotel star values. No change to authoritative pricing, refund policy, or backend endpoints.

## Verification
- Swift syntax parsing for all seven modified Swift files: passed.
- `bash scripts/test_smart_review_stability.sh`: 10 static checks + 5 executable Foundation/model checks passed.
- `test_smart_package_editing.sh`, `test_final_package_mixed_booking_v11.sh`, `test_guest_care.sh`, `test_business_offer_adoption_v9.sh`, `test_booking_creation_notifications.sh`, `test_seamless_booking.sh`, `test_nuitee_page_compatibility.sh`: passed locally. These are contract and targeted runtime tests, not UI tests.

## Required device QA
Build in Xcode/TestFlight and repeat Smart TAS→MED / JED→TAS on iPhone 11 and iPhone 13 mini. Verify two and three adults, single/multiple room fallback, date rollover, open review, scroll all sections, expand price/calendar, edit and return, save and book. If the app still exits, export the new `.ips` crash report and build number (and dSYM if available). No simulator/device or full SwiftUI type-check/archive was available here. Do not interpret this mitigation as verified on-device resolution.
