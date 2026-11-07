Iumrah Beta patch — 2026-11-07

Updated files:
- Sources/Views/Home/HomeDashboardView.swift
- Sources/Views/Airports/AirportSelectorButton.swift
- Sources/Views/Trip/FlightDateCalendarView.swift

Included changes:
1) Home hero/header
- black header should visually stretch during pull-down instead of exposing a pale/white area
- menu and notifications buttons swapped
- logo increased by ~30%
- search card slightly compacted

2) Date modal
- simplified flow: choose outbound first, then return
- top stage switcher: Outbound / Return
- dates without published flights are unavailable in published-only mode
- after choosing both dates, a range ribbon appears across the calendar
- neutral monochrome styling instead of green-heavy treatment

3) Airport selector
- supports monochrome home-card mode and adjustable corner radius
