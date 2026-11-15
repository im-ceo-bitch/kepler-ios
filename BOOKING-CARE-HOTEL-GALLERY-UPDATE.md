# iumrah iOS — Booking, Care & Hotel Gallery

Cumulative over Smart V2 / Orbit Ecosystem; base: kepler-ios-main 5.zip.

- Booking header: status, documents, Umrah package, schedule. Package uses existing booking components; no duplicate status/schedule cards.
- Care chat UI and requests gated by authenticated account and active booking. Telegram and phone remain available. Logout clears local booking/contact/chat cache; login reloads account trips. No server deletion.
- Passport icon fallbacks, document styling, full-screen language selector with Orbit.
- Three-photo hotel and room collages when photos exist; room photo count and gallery, real room album filters, in-card Add to Umrah package CTA.
- Telegram card uses existing unified backend native link endpoint.

No new backend deployment is required by these changes. Existing Smart V2 backend must already be deployed.

Validation: swiftc -frontend -parse on all 331 Sources Swift files; ZIP CRC and file comparisons. This is not an Xcode typecheck/build or device test.

Device QA: verify 4 tabs and package navigation; upload passport and check payment/document states; logout and switch account, verify no stale trips or chat, login restores trips; Telegram linking; 1/2/3+ photos, room gallery and hotel album selection; add room to package; switch languages. Verify real supplier photos and Telegram service in production.
