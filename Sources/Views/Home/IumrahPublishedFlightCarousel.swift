import SwiftUI

/// Staff-published D1 catalogue only. Never calls the live flight discovery API.
@MainActor final class IumrahPublishedCarouselCatalog: ObservableObject {
    static let shared = IumrahPublishedCarouselCatalog()
    @Published private(set) var rows: [String: [CuratedFlightRecommendation]] = [:]
    @Published private(set) var failures: Set<String> = []
    private var fetched: [String: Date] = [:]
    private var inFlight: [String: Task<Void, Never>] = [:]
    func load(_ trip: TripDraft, force: Bool = false) async {
        let key = trip.originCode.uppercased()
        if let running = inFlight[key] { await running.value; return }
        if !force, let date = fetched[key], Date().timeIntervalSince(date) < 300 { return }
        let task = Task { @MainActor in
            defer { inFlight[key] = nil }
            do {
                let result = try await CuratedFlightRecommendationService.shared.load(trip: trip, from: Date(), days: 365, force: force)
                if rows[key] != result { rows[key] = result }
                fetched[key] = Date(); failures.remove(key)
            } catch { failures.insert(key) }
        }
        inFlight[key] = task
        await task.value
    }
    func flights(_ trip: TripDraft, direction: Int, selected: LocalJourneyFlight?, other: LocalJourneyFlight?) -> [LocalJourneyFlight] {
        let origin = trip.originCode.uppercased()
        let saudi = direction == 0 ? trip.outboundDestinationCode : trip.returnOriginCode
        let cabin = trip.effectiveFlightFilters.cabinClass.rawValue.lowercased()
        let today = Calendar.current.startOfDay(for: Date())
        var items: [LocalJourneyFlight] = []
        for row in rows[origin] ?? [] where row.nonstop && row.cabinClass.lowercased().replacingOccurrences(of: " ", with: "_") == cabin {
            for leg in [row.outbound, row.inbound].compactMap({ $0 }) where leg.stops == 0 && leg.cabinClass.lowercased().replacingOccurrences(of: " ", with: "_") == cabin {
                guard direction == 0 ? (leg.origin == origin && leg.destination == saudi) : (leg.origin == saudi && leg.destination == origin) else { continue }
                guard let date = Self.day(leg.departureAt, leg.origin), date >= today, let price = row.fareUsdPerTraveler, price.isFinite, price > 0 else { continue }
                let flight = LocalJourneyFlight(id: "published:\(row.id):\(leg.origin):\(leg.departureAt)", origin: leg.origin, destination: leg.destination, airline: leg.airline, flightNumber: leg.flightNumber, airlineCode: leg.airlineCode, durationMinutes: leg.durationMinutes, stops: leg.stops, departureAt: leg.departureAt, arrivalAt: leg.arrivalAt, displayedPrice: price, publishedID: row.id, publishedIsPair: row.inbound != nil, publishedCabin: leg.cabinClass)
                if direction == 1, let other, !Self.compatible(other, flight, scope: trip.scope) { continue }
                items.append(flight)
            }
        }
        // Preserve canonical pair IDs; only deduplicate truly identical publications.
        var seen = Set<String>()
        return items.sorted { a,b in
            return a.departureAt == b.departureAt ? a.id < b.id : a.departureAt < b.departureAt
        }.filter { seen.insert($0.id).inserted }
    }
    static func day(_ value: String, _ airport: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(IumrahFlightClock.local(value, airport: airport).prefix(10)))
    }
    static func compatible(_ outbound: LocalJourneyFlight, _ inbound: LocalJourneyFlight, scope: JourneyScope) -> Bool {
        guard outbound.origin == inbound.destination, let raw = outbound.arrivalAt,
              let arrival = day(raw, outbound.destination), let returning = day(inbound.departureAt, inbound.origin), returning > arrival else { return false }
        if scope == .makkahAndMadinah && (Calendar.current.dateComponents([.day], from: arrival, to: returning).day ?? 0) < 2 { return false }
        if scope == .makkahOnly && (outbound.destination != "JED" || inbound.origin != "JED") { return false }
        if outbound.publishedIsPair == true || inbound.publishedIsPair == true { return outbound.publishedIsPair == true && inbound.publishedIsPair == true && outbound.publishedID == inbound.publishedID }
        return outbound.publishedID != inbound.publishedID
    }
}

struct IumrahPublishedFlightCarousel: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var catalog = IumrahPublishedCarouselCatalog.shared
    let trip: TripDraft
    let direction: Int
    var selected: LocalJourneyFlight?
    var other: LocalJourneyFlight?
    var showTitle = true
    let onSelect: (LocalJourneyFlight) -> Void
    let onOpen: (LocalJourneyFlight) -> Void
    private func t(_ r: String,_ e: String,_ u: String,_ c: String) -> String { IumrahFlightCopy.text(settings.language,r,e,u,c) }
    var body: some View {
        let flights = catalog.flights(trip, direction: direction, selected: selected, other: other)
        VStack(alignment: .leading, spacing: 12) {
            if showTitle { Text(t("Прямые рейсы", "Direct flights", "To‘g‘ri reyslar", "Тўғри рейслар")).font(.system(.title2, design: .rounded, weight: .bold)) }
            if flights.isEmpty {
                if catalog.failures.contains(trip.originCode.uppercased()) {
                    Button(t("Обновить рейсы", "Refresh flights", "Reyslarni yangilash", "Рейсларни янгилаш")) { Task { await catalog.load(trip, force: true) } }.buttonStyle(.bordered)
                } else if catalog.rows[trip.originCode.uppercased()] != nil {
                    Text(t("Нет опубликованных рейсов по этому направлению", "No published flights for this route", "Bu yo‘nalishda e’lon qilingan reyslar yo‘q", "Бу йўналишда эълон қилинган рейслар йўқ")).font(.footnote).foregroundStyle(.secondary)
                } else { Text(t("Получаем расписание рейсов", "Getting flight schedules", "Reyslar jadvali olinmoqda", "Рейслар жадвали олинмоқда")).font(.footnote).foregroundStyle(.secondary) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(flights) { flight in
                            IumrahFlightResultCard(airline: flight.airline, airlineCode: flight.airlineCode, flightNumber: flight.flightNumber, origin: flight.origin, destination: flight.destination, departureAt: flight.departureAt, arrivalAt: flight.arrivalAt, duration: flight.durationMinutes, stops: flight.stops, price: flight.displayedPrice, isAviasales: false, isRoundTripFare: flight.publishedIsPair == true, selected: selected?.id == flight.id, selectionAccent: .green, onSelect: { onSelect(flight) }, action: { onOpen(flight) })
                                .frame(width: 290)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned)
            }
        }.task(id: trip.originCode.uppercased()) { await catalog.load(trip) }
    }
}

@MainActor final class IumrahHomePublishedSelection: ObservableObject {
    @Published var outbound: LocalJourneyFlight?
    @Published var inbound: LocalJourneyFlight?
    var complete: Bool { outbound != nil && inbound != nil }
    func clear() { outbound = nil; inbound = nil }
    func reconcile(_ trip: TripDraft) {
        if let f = outbound, f.origin != trip.originCode || f.destination != trip.outboundDestinationCode || f.publishedCabin?.lowercased().replacingOccurrences(of: " ", with: "_") != trip.effectiveFlightFilters.cabinClass.rawValue.lowercased() || IumrahPublishedCarouselCatalog.day(f.departureAt, f.origin).map({ !Calendar.current.isDate($0, inSameDayAs: trip.departureDate) }) != false { clear(); return }
        if let f = inbound, f.destination != trip.originCode || f.origin != trip.returnOriginCode || f.publishedCabin?.lowercased().replacingOccurrences(of: " ", with: "_") != trip.effectiveFlightFilters.cabinClass.rawValue.lowercased() || IumrahPublishedCarouselCatalog.day(f.departureAt, f.origin).map({ !Calendar.current.isDate($0, inSameDayAs: trip.returnDate) }) != false { inbound = nil }
    }
    @discardableResult func choose(_ flight: LocalJourneyFlight, direction: Int, journey: JourneyStore) -> Bool {
        guard let day = IumrahPublishedCarouselCatalog.day(flight.departureAt, flight.origin), day >= Calendar.current.startOfDay(for: Date()), flight.publishedID != nil, flight.stops == 0 else { return false }
        if direction == 0 {
            guard flight.origin == journey.trip.originCode, flight.destination == journey.trip.outboundDestinationCode else { return false }
            if let inbound, !IumrahPublishedCarouselCatalog.compatible(flight, inbound, scope: journey.trip.scope) { self.inbound = nil }
            outbound = flight
            journey.trip.departureDate = day
            if journey.trip.returnDate <= day { journey.trip.returnDate = Calendar.current.date(byAdding: .day, value: 7, to: day) ?? day }
        } else {
            guard flight.destination == journey.trip.originCode, flight.origin == journey.trip.returnOriginCode else { return false }
            if let outbound, !IumrahPublishedCarouselCatalog.compatible(outbound, flight, scope: journey.trip.scope) { return false }
            guard day > journey.trip.departureDate else { return false }
            inbound = flight; journey.trip.returnDate = day
        }
        IumrahHaptics.selection(); return true
    }
    func commit(_ journey: JourneyStore) -> Bool {
        guard let a = outbound, let b = inbound, let aID = a.publishedID, let bID = b.publishedID,
              IumrahPublishedCarouselCatalog.compatible(a,b,scope: journey.trip.scope),
              let departure = IumrahPublishedCarouselCatalog.day(a.departureAt,a.origin), let raw = a.arrivalAt,
              let arrival = IumrahPublishedCarouselCatalog.day(raw,a.destination), let back = IumrahPublishedCarouselCatalog.day(b.departureAt,b.origin), journey.trip.canContinue else { return false }
        if journey.localJourneyFlights.map(\.id) == [a.id,b.id] && journey.hasCompleteStagedFlightSelection { return true }
        journey.resetAfterTripChange(); journey.clearStagedUmrahFlights()
        journey.trip.departureDate = departure; journey.trip.returnDate = back; journey.trip.saudiArrivalDate = arrival
        journey.trip.flightTripType = .roundTrip; journey.trip.flexibility = .exact
        journey.trip.selectedReturnAirport = SaudiArrivalAirport(rawValue: b.origin)
        journey.packageFlightPath = .publishedDirect
        func stage(_ f: LocalJourneyFlight, _ kind: StagedUmrahFlightKind, pair: LocalJourneyFlight? = nil) {
            journey.stageUmrahFlight(.init(id: f.id, kind: kind, origin: f.origin, destination: f.destination, airline: f.airline, flightNumber: f.flightNumber, departureAt: f.departureAt, returnAt: pair?.departureAt, returnAirline: pair?.airline, returnFlightNumber: pair?.flightNumber, source: "iumrah"))
        }
        if a.publishedIsPair == true { journey.selectedPublishedCompleteID = aID; stage(a,.roundTrip,pair:b) }
        else { journey.selectedPublishedOutboundID = aID; journey.selectedPublishedReturnID = bID; stage(a,.outbound); stage(b,.inbound) }
        journey.prepareFlightFirstHotelStage(); journey.usesLocalJourney = true; journey.localJourneyFlights = [a,b]
        return true
    }
}

// Home discovery is deliberately independent of the current trip filters.
// The original route-scoped carousel remains available to all configurators.
@MainActor final class IumrahAllPublishedFlightStore: ObservableObject {
    static let shared = IumrahAllPublishedFlightStore()
    @Published private(set) var flights: [LocalJourneyFlight] = []
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var complete = false
    private var fetched: Date?
    private var request: Task<Void, Never>?

    func load(force: Bool = false) async {
        if let request { await request.value; return }
        if !force, let fetched, Date().timeIntervalSince(fetched) < 300 { return }
        let task = Task { @MainActor in
            loading = true
            defer { loading = false; request = nil }
            do {
                let board = try await HotelStorefrontService().flightBoard(allPublished: true)
                guard board.ok else { throw APIError.invalidResponse }
                flights = Self.flatten(board.options)
                complete = board.catalogComplete == true
                loaded = true; failed = false; fetched = Date()
            } catch {
                failed = true
            }
        }
        request = task
        await task.value
    }

    static func flatten(_ options: [StorefrontFlightOption]) -> [LocalJourneyFlight] {
        var seen = Set<String>()
        return options.flatMap { option -> [LocalJourneyFlight] in
            let price: Double? = option.currency.uppercased() == "USD" && option.perTravelerFare.isFinite && option.perTravelerFare > 0 ? option.perTravelerFare : nil
            return [Optional(option.outbound), option.inbound].compactMap { leg -> LocalJourneyFlight? in
                guard let leg, leg.stops == 0 else { return nil }
                return LocalJourneyFlight(id: "published:\(option.id):\(leg.origin):\(leg.departureAt)", origin: leg.origin, destination: leg.destination, airline: leg.airline, flightNumber: leg.flightNumber, airlineCode: leg.airlineCode, durationMinutes: leg.durationMinutes, stops: leg.stops, departureAt: leg.departureAt, arrivalAt: leg.arrivalAt, displayedPrice: price, publishedID: option.id, publishedIsPair: option.inbound != nil, publishedCabin: leg.cabinClass)
            }
        }.sorted { a, b in
            a.departureAt == b.departureAt ? a.id < b.id : a.departureAt < b.departureAt
        }.filter { seen.insert($0.id).inserted }
    }
}

struct IumrahAllPublishedFlightBoard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var journey: JourneyStore
    @ObservedObject private var store = IumrahAllPublishedFlightStore.shared
    @ObservedObject var selection: IumrahHomePublishedSelection
    let horizontal: Bool
    let onOpen: (LocalJourneyFlight) -> Void

    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if store.loading && !store.loaded { ProgressView().frame(maxWidth: .infinity).padding(18) }
            if store.failed || (store.loaded && !store.complete) {
                Text(store.failed ? t("Не удалось обновить рейсы", "Could not refresh flights", "Reyslar yangilanmadi", "Рейслар янгиланмади") : t("Полный каталог пока недоступен", "Complete catalogue not available yet", "To‘liq katalog hozircha mavjud emas", "Тўлиқ каталог ҳозирча мавжуд эмас"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(t("Обновить рейсы", "Refresh flights", "Reyslarni yangilash", "Рейсларни янгилаш")) { Task { await store.load(force: true) } }.buttonStyle(.bordered)
            }
            if store.loaded && store.complete && !store.failed && store.flights.isEmpty {
                Text(t("Нет опубликованных рейсов", "No published flights", "E’lon qilingan reyslar yo‘q", "Эълон қилинган рейслар йўқ")).font(.footnote).foregroundStyle(.secondary)
            }
            if !store.flights.isEmpty {
                if horizontal {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(store.flights) { flight in card(flight).frame(width: 290) }
                        }.scrollTargetLayout()
                    }.scrollTargetBehavior(.viewAligned)
                } else {
                    LazyVStack(spacing: 12) { ForEach(store.flights) { flight in card(flight) } }
                }
            }
        }.task { await store.load() }
            .accessibilityIdentifier(horizontal ? "iumrah.home.directFlights" : "iumrah.home.allDirectFlights")
    }

    private func card(_ flight: LocalJourneyFlight) -> some View {
        IumrahFlightResultCard(airline: flight.airline, airlineCode: flight.airlineCode, flightNumber: flight.flightNumber, origin: flight.origin, destination: flight.destination, departureAt: flight.departureAt, arrivalAt: flight.arrivalAt, duration: flight.durationMinutes, stops: flight.stops, price: flight.displayedPrice, isAviasales: false, isRoundTripFare: flight.publishedIsPair == true, selected: selection.outbound?.id == flight.id || selection.inbound?.id == flight.id, selectionAccent: .green, onSelect: selection.canChoose(flight, trip: journey.trip) ? { _ = selection.choose(flight, direction: flight.origin == journey.trip.originCode ? 0 : 1, journey: journey) } : nil, action: { onOpen(flight) })
    }
}

struct IumrahAllPublishedFlightsPage: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject var selection: IumrahHomePublishedSelection
    @State private var detail: LocalJourneyFlight?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                IumrahHomeSectionHeader(title: IumrahFlightCopy.text(settings.language, "Прямые рейсы", "Direct flights", "To‘g‘ridan-to‘g‘ri reyslar", "Тўғридан-тўғри рейслар"))
                IumrahAllPublishedFlightBoard(selection: selection, horizontal: false, onOpen: { detail = $0 })
            }.padding(.horizontal, IumrahDesign.pagePadding).padding(.bottom, 40)
        }.background(Color.iumrahPageBackground)
            .refreshable { await IumrahAllPublishedFlightStore.shared.load(force: true) }
            .iumrahInternalNavigation()
            .navigationDestination(item: $detail) { flight in IumrahHomePublishedFlightDetail(flight: flight, selection: selection) }
    }
}

struct IumrahHomePublishedFlightDetail: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var journey: JourneyStore
    @ObservedObject var selection: IumrahHomePublishedSelection
    let flight: LocalJourneyFlight
    init(flight: LocalJourneyFlight, selection: IumrahHomePublishedSelection) { self.flight = flight; self.selection = selection }
    var body: some View {
        IumrahManualFlightDetail(flight: flight, onConfirm: {
            guard selection.canChoose(flight, trip: journey.trip) else { return false }
            return selection.choose(flight, direction: flight.origin == journey.trip.originCode ? 0 : 1, journey: journey)
        }, selectedOverride: selection.outbound?.id == flight.id || selection.inbound?.id == flight.id,
        selectionUnavailableMessage: selection.canChoose(flight, trip: journey.trip) ? nil : IumrahFlightCopy.text(settings.language, "Для этого рейса настройте подходящий маршрут, даты и класс в конфигураторе.", "Configure a matching route, dates and cabin for this flight.", "Bu reys uchun mos yo‘nalish, sana va klassni tanlang.", "Бу рейс учун мос йўналиш, сана ва классни танланг."))
    }
}

extension IumrahHomePublishedSelection {
    func canChoose(_ flight: LocalJourneyFlight, trip: TripDraft) -> Bool {
        guard flight.publishedID != nil, flight.stops == 0, let price = flight.displayedPrice, price.isFinite, price > 0,
              let day = IumrahPublishedCarouselCatalog.day(flight.departureAt, flight.origin), day >= Calendar.current.startOfDay(for: Date()),
              flight.publishedCabin?.lowercased().replacingOccurrences(of: " ", with: "_") == trip.effectiveFlightFilters.cabinClass.rawValue.lowercased() else { return false }
        if flight.origin == trip.originCode && flight.destination == trip.outboundDestinationCode { return true }
        guard flight.destination == trip.originCode, flight.origin == trip.returnOriginCode, day > trip.departureDate else { return false }
        if let outbound { return IumrahPublishedCarouselCatalog.compatible(outbound, flight, scope: trip.scope) }
        return true
    }
}
