import SwiftUI

/// Browse the existing published catalogue plus cached supplier fares before
/// the traveler supplies exact dates. No per-card supplier calls.
struct IumrahFlightBrowseCatalog: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    let direction: Int
    let refreshSignal: Int
    @ObservedObject var model: IumrahFlightBrowseModel
    let onChoose: (LocalJourneyFlight) -> Void
    @State private var filters = IumrahFlightFilterState()
    @State private var visibleCount = 30
    private var identity: String { "\(journey.trip.originCode):\(refreshSignal)" }
    private var directionFlights: [LocalJourneyFlight] {
        model.flights.filter { direction == 0 ? $0.origin == journey.trip.originCode : $0.destination == journey.trip.originCode }
    }
    private var filtered: [LocalJourneyFlight] {
        directionFlights.filter { filters.accepts(stops: $0.stops, airline: $0.airlineCode, departure: $0.departureAt) }.sorted { a, b in
            if filters.sort == 1, a.displayedPrice != b.displayedPrice { return (a.displayedPrice ?? .infinity) < (b.displayedPrice ?? .infinity) }
            if filters.sort == 2, a.durationMinutes != b.durationMinutes { return (a.durationMinutes > 0 ? a.durationMinutes : Int.max) < (b.durationMinutes > 0 ? b.durationMinutes : Int.max) }
            return a.departureAt == b.departureAt ? a.id < b.id : a.departureAt < b.departureAt
        }
    }
    private var calendarFlights: [LocalJourneyFlight] {
        directionFlights.filter { filters.accepts(stops: $0.stops, airline: $0.airlineCode, departure: $0.departureAt, includeDay: false) }
    }
    var body: some View {
        LazyVStack(spacing: 14) {
            IumrahFlightSearchControls(filters: $filters,
                airlines: Array(Set(directionFlights.map(\.airlineCode))).sorted(),
                days: IumrahFlightSearchControls.priceDays(calendarFlights.map { ($0.departureAt, $0.displayedPrice) }),
                onSelectDay: { day in
                    filters.day = day
                    Task { await model.loadDay(day, trip: journey.trip, direction: direction, language: settings.language) }
                })
            if model.loading { ProgressView().frame(maxWidth: .infinity).padding(18) }
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button(NuiteeCopy.text("Повторить", "Qayta urinish", "Retry", settings.language)) { Task { await model.load(trip: journey.trip, language: settings.language) } }
            } else if !model.loading && filtered.isEmpty {
                Text(NuiteeCopy.text("Пока нет рейсов на выбранном направлении", "Bu yo‘nalishda reyslar hali yo‘q", "No flights available for this direction", settings.language))
                    .foregroundStyle(.secondary).padding(.vertical, 24)
            }
            ForEach(Array(filtered.prefix(visibleCount))) { flight in
                let presentation = presentation(for: flight)
                VStack(spacing: 7) {
                    NavigationLink {
                        IumrahOTAFlightDetailPage(
                            flight: presentation,
                            language: settings.language,
                            actionTitle: chooseTitle,
                            onChoose: { onChoose(flight) },
                            dismissAfterChoose: false
                        )
                    } label: {
                        IumrahOTAFlightCard(flight: presentation, language: settings.language)
                    }
                    .buttonStyle(.plain)

                    HStack {
                        Text(presentation.source == .cachedSearch ? indicativePriceNote : publishedNote)
                            .font(IumrahType.regular(11, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Button {
                            onChoose(flight)
                            IumrahHaptics.selection()
                        } label: {
                            Text(chooseTitle)
                                .font(IumrahType.bold(12, relativeTo: .caption))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(Color.iumrahRoyalViolet.opacity(0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.iumrahRoyalViolet)
                    }
                    .padding(.horizontal, 7)
                }
                .onAppear { if flight.id == filtered.prefix(visibleCount).last?.id { visibleCount += 30 } }
            }
        }
        .task(id: identity) { await model.load(trip: journey.trip, language: settings.language) }
        .onChange(of: direction) { _, _ in visibleCount = 30; filters = IumrahFlightFilterState() }
    }
    private var chooseTitle: String {
        switch settings.language {
        case .russian: return "Подобрать"
        case .uzbek: return "Tanlash"
        case .uzbekCyrillic: return "Танлаш"
        default: return "Choose"
        }
    }
    private var indicativePriceNote: String {
        switch settings.language {
        case .russian: return "Кэш · цена требует проверки"
        case .uzbek: return "Kesh · narxni tekshiring"
        case .uzbekCyrillic: return "Кеш · нархни текширинг"
        default: return "Cached · reconfirm fare"
        }
    }
    private var publishedNote: String {
        switch settings.language {
        case .russian: return "Опубликованный рейс"
        case .uzbek: return "E’lon qilingan reys"
        case .uzbekCyrillic: return "Эълон қилинган рейс"
        default: return "Published flight"
        }
    }

    private func presentation(for flight: LocalJourneyFlight) -> IumrahOTAFlightSnapshot {
        let published = flight.id.hasPrefix("published:")
        let verifiedDirectLeg: [IumrahOTAFlightLeg]
        if published, flight.stops == 0, let arrival = flight.arrivalAt, !arrival.isEmpty {
            verifiedDirectLeg = [IumrahOTAFlightLeg(origin: flight.origin, destination: flight.destination,
                departureAt: flight.departureAt, arrivalAt: arrival,
                airlineCode: flight.airlineCode, flightNumber: flight.flightNumber)]
        } else {
            verifiedDirectLeg = []
        }
        return IumrahOTAFlightSnapshot(id: flight.id, airline: flight.airline,
            airlineCode: flight.airlineCode, flightNumber: flight.flightNumber,
            origin: flight.origin, destination: flight.destination,
            departureAt: flight.departureAt, arrivalAt: flight.arrivalAt,
            durationMinutes: flight.durationMinutes, stops: flight.stops,
            priceUSD: flight.displayedPrice,
            source: published ? .published : .cachedSearch,
            cabin: nil, segments: verifiedDirectLeg)
    }

    private var outboundTitle: String {
        switch settings.language { case .russian: return "Туда"; case .uzbek: return "Borish"; case .uzbekCyrillic: return "Бориш"; default: return "Outbound" }
    }
    private var returnTitle: String {
        switch settings.language { case .russian: return "Обратно"; case .uzbek: return "Qaytish"; case .uzbekCyrillic: return "Қайтиш"; default: return "Return" }
    }
}

@MainActor
final class IumrahFlightBrowseModel: ObservableObject {
    @Published private(set) var flights: [LocalJourneyFlight] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var requestID = UUID()
    func load(trip: TripDraft, language: AppSettingsStore.Language) async {
        let token = UUID(); requestID = token
        loading = true; error = nil; flights = []
        let origin = trip.originCode.uppercased()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let day = IumrahFlightDiscoveryStore.dayFormatter.string(from: tomorrow)
        var result: [LocalJourneyFlight] = []
        var failures = 0
        do {
            let items = try await CuratedFlightRecommendationService.shared.load(trip: trip, from: tomorrow, days: 365)
            for item in items {
                for leg in [item.outbound, item.inbound].compactMap({ $0 }) where String(leg.departureAt.prefix(10)) >= day {
                    result.append(LocalJourneyFlight(id: "published:\(item.id):\(leg.origin):\(leg.departureAt)",
                        origin: leg.origin, destination: leg.destination, airline: leg.airline,
                        flightNumber: leg.flightNumber, airlineCode: leg.airlineCode,
                        durationMinutes: leg.durationMinutes, stops: leg.stops, departureAt: leg.departureAt,
                        arrivalAt: leg.arrivalAt, displayedPrice: nil))
                }
            }
        } catch { failures += 1 }
        guard requestID == token, !Task.isCancelled else { return }
        flights = sortedUnique(result)
        // Both Saudi airports, both directions. Cached monthly feeds include
        // tomorrow onward; published rows above cover the full available year.
        let months = Set([tomorrow, Calendar.current.date(byAdding: .month, value: 1, to: tomorrow) ?? tomorrow]
            .map { IumrahFlightDiscoveryStore.monthFormatter.string(from: $0) })
        for airport in ["JED", "MED"] {
            for route in [(origin, airport), (airport, origin)] {
                for month in months.sorted() {
                    guard requestID == token, !Task.isCancelled else { return }
                    do {
                        let response = try await AviasalesFlightDiscoveryService().offers(origin: route.0, destination: route.1,
                            departure: month, direct: false, limit: 200)
                        for offer in response.offers where offer.origin == route.0 && offer.destination == route.1
                            && String(offer.departureAt.prefix(10)) >= day {
                            result.append(LocalJourneyFlight(id: "feed:\(offer.id)", origin: offer.origin,
                                destination: offer.destination, airline: offer.airlineName, flightNumber: offer.flightNumber,
                                airlineCode: offer.airlineCode, durationMinutes: offer.durationMinutes, stops: offer.transfers,
                                departureAt: offer.departureAt, arrivalAt: offer.arrivalAt ?? FlightDiscoveryItineraryValidator.verified(offer.outboundSegments, origin: offer.origin, destination: offer.destination, transfers: offer.transfers)?.last?.arrivalAt, displayedPrice: offer.price > 0 ? offer.price : nil))
                        }
                    } catch { failures += 1 }
                    guard requestID == token, !Task.isCancelled else { return }
                    flights = sortedUnique(result)
                }
            }
        }
        if failures > 0 && result.isEmpty {
            error = NuiteeCopy.text("Не удалось загрузить рейсы. Нажмите «Повторить».", "Reyslar yuklanmadi. «Qayta urinish» tugmasini bosing.", "Could not load flights. Tap Retry.", language)
        }
        if requestID == token { loading = false }
    }
    func loadDay(_ day: String, trip: TripDraft, direction: Int, language: AppSettingsStore.Language) async {
        let token = UUID(); requestID = token
        loading = true; error = nil
        defer { if requestID == token { loading = false } }
        var result = flights
        var failures = 0
        let origin = trip.originCode.uppercased()
        for airport in ["JED", "MED"] {
            guard requestID == token, !Task.isCancelled else { return }
            let from = direction == 0 ? origin : airport
            let to = direction == 0 ? airport : origin
            do {
                let response = try await AviasalesFlightDiscoveryService().offers(origin: from, destination: to, departure: day, direct: false, limit: 200)
                for offer in response.offers where !offer.isRoundTrip && offer.origin == from && offer.destination == to {
                    result.append(LocalJourneyFlight(id: "feed:\(offer.id)", origin: offer.origin, destination: offer.destination,
                        airline: offer.airlineName, flightNumber: offer.flightNumber, airlineCode: offer.airlineCode,
                        durationMinutes: offer.durationMinutes, stops: offer.transfers, departureAt: offer.departureAt,
                        arrivalAt: offer.arrivalAt ?? FlightDiscoveryItineraryValidator.verified(offer.outboundSegments, origin: offer.origin, destination: offer.destination, transfers: offer.transfers)?.last?.arrivalAt,
                        displayedPrice: offer.price > 0 ? offer.price : nil))
                }
            } catch { failures += 1 }
        }
        guard requestID == token, !Task.isCancelled else { return }
        flights = sortedUnique(result)
        if failures == 2 {
            error = NuiteeCopy.text("Не удалось загрузить рейсы на эту дату.", "Bu sana uchun reyslar yuklanmadi.", "Could not load flights for this date.", language)
        }
    }
    private func sortedUnique(_ values: [LocalJourneyFlight]) -> [LocalJourneyFlight] {
        var unique: [String: LocalJourneyFlight] = [:]
        for flight in values {
            let key = "\(flight.origin):\(flight.destination):\(flight.flightNumber):\(flight.departureAt.prefix(10))"
            if unique[key] == nil || (unique[key]?.displayedPrice == nil && flight.displayedPrice != nil) { unique[key] = flight }
        }
        return unique.values.sorted { $0.departureAt < $1.departureAt }
    }
}
