# V22 — Flight confirmation and hotel detail
Cumulative iOS V20 + V21 (including native navigation V20.1) + V22. Apply to kepler-ios. Deploy Business V22 first, then TestFlight.
- Manual flights: pending selection, explicit bottom CTA, temporary confirmation, return flight / package navigation.
- Guided flights: explicit confirmation, return selection, transfer before hotel selection.
- Hotel stay summary, green signature border, uniform review carousel and review detail sheet with original/translated text.
- Meal selection: <=3 stars optional bundled meals (Makkah breakfast/lunch/dinner, Madinah breakfast/dinner); >=4 stars breakfast included, lunch and dinner individually optional. Supplier inclusions retained. All rates and quote verification stay on server.
- Existing cache, pagination and navigation changes retained. No workflow changes.
Validation: 317 Swift files parsed, 12 daily cache smoke tests passed. Full Xcode build and device testing not performed in this environment. Translation provider availability is verified at runtime; original text remains available.
