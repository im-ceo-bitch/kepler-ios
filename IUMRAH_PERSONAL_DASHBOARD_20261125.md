# iumrah — Personal Dashboard / Home + Account

Cumulative client patch based on `kepler-ios-main 5.zip` (a5d7efd2f83954625777247aa9df1a7c8056d069). Includes previous Personal Guides client changes and animated Friends card. Install this archive instead of the earlier client patches; the earlier Business/backend guide patch is still required if it was not deployed.

## Home
- Existing black header, brand row, hero and flight search source preserved. No rebranding or changes to shared primary header component. The new guide navigation from the previous patch is included.
- Existing published flights, notifications, recent activity, available packages, package inclusions, benefits, Why iumrah carousel, mission and slogan retained. Active booking appears before marketing; saved journeys, official planner, manual flight-first selection, Smart, destinations, six service shortcuts, personal guide showcase and Care added to the root.
- Real signed-in Balance and Rewards data. Friends promotion remains available without login; issuing a referral link requires an eligible authenticated account under existing server rules.
- Native pull refresh on Home; shared account cache also refreshes on the active tab approximately every 60 seconds. No new API endpoints.

## Account
- Original black `IumrahPrimaryTabHeader` reused with a profile footer; opens existing IumrahUserDataView with booking/account data. Signed-in balance, Friends and Rewards tiles, live world-dot ID card with existing fullscreen destination. Large eSIM and Care shortcuts. All previous account groups, settings, policies, security and sign-out/delete routes retained. Guest profile/booking policy unchanged.
- Emerald Balance, blue Friends, gold Rewards, graphite ID, violet/blue service accents. Large Dynamic Type uses one-column benefits layout. New copy is RU/EN/UZ/UZ-Cyrl, other languages fall back to English as in existing flight copy helper.

## Motion
- Native SwiftUI Canvas ripples; sequential three $100 promotional tickets, blue/silver shading, 3D entry, reverse exit and repeat. Not earned credits or issued coupons.
- Numeric text transitions, native metallic sheen, real bundled world-dot map, subtle content entry and press/haptic feedback. Decorative timeline honors scene, inactive tab, view appearance, Reduce Motion, and performance profile. Actual device smoothness/visibility requires Xcode/device verification.

## Data and security
- Shared account-owned in-memory rewards cache coalesces concurrent requests; invalidates on bearer token changes; no demo values and no fabricated tiers. Retains last verified balance on transient failure with explicit stale label; clears on authorization rejection. Existing Rewards/Friends detail pages use same server request and feed shared cache. Tier segment indicates current verified tier, not invented percentage to next level. Balance uses USD.
- No change to rewards eligibility, pricing, payments, auth policy, signing, Bundle ID, workflows or backend in this dashboard patch.

## Verification
- `swiftc -frontend -parse` on all 15 cumulative changed Swift files: PASS.
- `python3 Tests/iumrah_dashboard_cache_smoke.py`: PASS (actual cache methods compiled against mock service; guest, request coalescing, TTL, verified zero, transient error, 401, account change, logout).
- Static comparison: Home hero/search unchanged, shared primary header unchanged, original root Home sections and Account group rows retained; guide route present.
- Xcode SDK unavailable in this Linux environment: no iOS typecheck, build, simulator, on-device visual QA or live backend integration run. TestFlight validation still required.
