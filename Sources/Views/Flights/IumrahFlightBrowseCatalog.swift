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
    @State private var visibleCount = 30
    private var identity: String { "\(journey.trip.originCode):\(refreshSignal)" }
    private var filtered: [LocalJourneyFlight] {
        model.flights.filter { direction == 0 ? $0.origin == journey.trip.originCode : $0.destination == journey.trip.originCode }
    }
    var body: some View {
        LazyVStack(spacing: 14) {
            if model.loading { ProgressView().frame(maxWidth: .infinity).padding(18) }
            if let error = model.error, model.flights.isEmpty {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button(NuiteeCopy.text("Повторить", "Qayta urinish", "Retry", settings.language)) { Task { await model.load(trip: journey.trip, language: settings.language) } }
            } else if !model.loading && filtered.isEmpty {
                Text(NuiteeCopy.text("Пока нет рейсов на выбранном направлении", "Bu yo‘nalishda reyslar hali yo‘q", "No flights available for this direction", settings.language))
                    .foregroundStyle(.secondary).padding(.vertical, 24)
            }
            ForEach(Array(filtered.prefix(visibleCount))) { flight in
                Group {
                    VStack(alignment: .leading, spacing: 10) {
                        PackageFlightLegDetailCard(leg: StorefrontFlightLeg(airline: flight.airline,
                            flightNumber: flight.flightNumber, airlineCode: flight.airlineCode,
                            origin: flight.origin, destination: flight.destination,
                            departureAt: flight.departureAt, arrivalAt: flight.arrivalAt ?? "",
                            durationMinutes: flight.durationMinutes, stops: flight.stops,
                            cabinClass: journey.trip.effectiveFlightFilters.cabinClass.rawValue),
                            direction: direction == 0 ? outboundTitle : returnTitle, language: settings.language,
                            actionTitle: NuiteeCopy.text("Выбрать", "Tanlash", "Select", settings.language), onChange: { onChoose(flight) })
                        if let price = flight.displayedPrice {
                            Text(NuiteeHotelService.usd(price)).font(.headline).padding(.horizontal, 16)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onAppear { if flight.id == filtered.prefix(visibleCount).last?.id { visibleCount += 30 } }
            }
        }
        .task(id: identity) { await model.load(trip: journey.trip, language: settings.language) }
        .onChange(of: direction) { _, _ in visibleCount = 30 }
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
                                departureAt: offer.departureAt, arrivalAt: nil, displayedPrice: offer.price > 0 ? offer.price : nil))
                        }
                    } catch { failures += 1 }
                    guard requestID == token, !Task.isCancelled else { return }
                    flights = sortedUnique(result)
                }
            }
        }
        if failures > 0 && result.isEmpty {
            error = NuiteeCopy.text("Не удалось загрузить рейсы. Потяните экран вниз, чтобы повторить.", "Reyslar yuklanmadi. Yangilash uchun ekranni pastga torting.", "Could not load flights. Pull down to retry.", language)
        }
        if requestID == token { loading = false }
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
