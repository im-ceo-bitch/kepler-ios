# Hotel occupancy preservation and date-positioned Home carousels — 2026-11-27

Cumulative over 2026-11-26 contextual-flight-carousels; based on supplied kepler-ios-main 5.zip. No Business, backend, workflows or signing edits.

- Guest edits preserve hotel, mapped room identity, meals and dates; add rooms at 6 guests. New occupancy must be priced with a fresh supplier offer. Unconfirmed room selections stay visible but cannot be submitted as validated prices. Retry or choose another rate of the same hotel if necessary. Existing supplier constraints and server quote sealing remain intact.
- Current catalogue price is visible in the detail screen during loading/transient failure for the same stay, labelled as not confirmed; no fabricated room offer. Decode failure on localized rates can retry the cached English representation.
- Home direct flight lists remain complete. Relevant route/cabin is chronological, scroll anchor selects the first flight on/after the chosen outbound or return day. Earlier available flights remain to the left. Other routes/classes retained. Return anchor respects minimum stay after selected outbound arrival.
- Verified with Linux Swift parser and extracted production Swift methods with fixtures; no iOS SDK/Xcode, live supplier or production deployment tested. Actual supplier capacity and tariffs cannot be overridden by the UI planning rule. If a family has fewer adults than required rooms, existing one-adult-per-room rule requires assistance. Manual room selection before final review is not redesigned.
