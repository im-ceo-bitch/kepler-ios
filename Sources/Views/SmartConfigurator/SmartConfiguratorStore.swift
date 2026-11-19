import Foundation
import Combine

struct SmartConfiguratorPreferences: Codable, Hashable {
    var origin = "TAS"
    var airport: Airport?
    var month: Date = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    var duration = 7
    var scope: JourneyScope = .makkahAndMadinah
    var firstCity: SaudiArrivalAirport = .madinah
    var adults = 2
    var childAges: [Int] = []
    var tier: PackageTier = .standard
    var children: Int { childAges.filter { $0 >= 2 }.count }
    var infants: Int { childAges.filter { $0 < 2 }.count }
    var monthKey: String { Self.key(month, format: "yyyy-MM") }
    static func key(_ date: Date, format: String = "yyyy-MM-dd") -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = format
        return f.string(from: date)
    }
    static func date(_ value: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; return f.date(from: value)
    }
    func draft(out: Date, back: Date) -> TripDraft {
        var trip = TripDraft()
        trip.origin = origin; trip.originAirport = airport; trip.scope = scope
        trip.arrivalAirport = scope == .makkahOnly ? .jeddah : firstCity
        trip.departureDate = out; trip.returnDate = back; trip.flexibility = .exact
        trip.adults = adults; trip.children = children; trip.infants = infants
        trip.rooms = max(1, (adults + 4) / 5)
        trip.hotelStars = tier.primaryHotelStars; trip.packageTier = tier
        return trip
    }
}

private struct SmartPlanRequest: Encodable {
    let origin: String; let month: String; let durationDays: Int; let both: Bool; let firstCity: String; let source: String
}
private struct SmartDataPair: Decodable {
    let outbound: FlightDiscoveryOffer; let inbound: FlightDiscoveryOffer
    let departureDay: String; let returnDay: String
}
private struct SmartPublishedPair: Decodable {
    let completeID: String?; let outboundID: String?; let returnID: String?
    let departureDay: String; let returnDay: String
    var selection: CuratedPublishedFlightSelection { .init(completeID: completeID, outboundID: outboundID, returnID: returnID) }
}
private struct SmartPlan: Decodable { let ok: Bool; let published: [SmartPublishedPair]; let dataPairs: [SmartDataPair] }

@MainActor
final class SmartConfiguratorStore: ObservableObject {
    enum Progress: Int, CaseIterable { case flights, hotels, transfer, price, ready }
    @Published var preferences = SmartConfiguratorPreferences()
    @Published private(set) var progress: Progress = .flights
    @Published private(set) var result: JourneyStore?
    @Published private(set) var error: String?
    @Published private(set) var busy = false
    @Published private(set) var connecting = false
    @Published private(set) var flightPreview: [FlightOffer] = []
    @Published private(set) var roomPreview: [LocalJourneyRoom] = []
    @Published private(set) var transferPreview: String?
    @Published private(set) var hotelSearchCity: String?
    @Published private(set) var replacingCity: String?
    @Published private(set) var replacementError: String?
    @Published private(set) var hotelsChangedWithFlights = false
    private var excludedHotels: [String: Set<String>] = [:]


    var reviewReady: Bool {
        guard !busy, replacingCity == nil, let result else { return false }
        return Self.validReview(result)
    }
    var roomCities: [String] {
        var seen = Set<String>()
        return roomPreview.map(\.city).filter { seen.insert($0).inserted }
    }
    func hotelTotal(city: String) -> Decimal? {
        guard let quote = result?.quote, let price = quote.tripSummary,
              price.totalUsd == quote.totalPackagePrice else { return nil }
        return price.components.first { $0.code == (city == "madinah" ? "madinah_hotel" : "makkah_hotel") }?.amountUsd
    }
    private static func validReview(_ journey: JourneyStore) -> Bool {
        guard journey.hasFinalGeneratorQuote, let quote = journey.quote,
              quote.bookingAllowed == true, quote.tripSummary?.reconciles(with: quote.totalPackagePrice) == true, journey.trip.rooms > 0,
              journey.trip.adults > 0, journey.trip.travelerCount > 0,
              journey.localRoomsComplete, journey.selectedOutbound != nil,
              journey.selectedInbound != nil, journey.transferSelectionConfirmed,
              let vehicle = journey.selectedTransferVehicle, vehicle.passengerCapacity >= journey.trip.travelerCount else { return false }
        let cities = journey.trip.scope == .makkahAndMadinah ? ["makkah", "madinah"] : ["makkah"]
        let windows = TripStayPlanner.windows(for: journey.trip)
        guard journey.localJourneyRooms.count == cities.count * journey.trip.rooms else { return false }
        return cities.allSatisfy { city in
            let rooms = journey.localJourneyRooms.values.filter { $0.city == city }
            guard let window = city == "makkah" ? windows.makkah : windows.madinah else { return false }
            return rooms.count == journey.trip.rooms && Set(rooms.map { $0.hotel.id }).count == 1 &&
                rooms.reduce(0) { $0 + $1.adults } == journey.trip.adults &&
                rooms.reduce(0) { $0 + $1.childrenAges.count } == journey.trip.children + journey.trip.infants &&
                rooms.allSatisfy { $0.checkin == window.checkIn && $0.checkout == window.checkOut &&
                    $0.checkin < $0.checkout && $0.adults > 0 && $0.rate.currency.uppercased() == "USD" &&
                    $0.rate.price.isFinite && $0.rate.price > 0 && !$0.rate.offerId.isEmpty }
        }
    }

    private enum Failure: LocalizedError {
        case noFlights, partyFare, hotel, room, quote, hotelNetwork
        var errorDescription: String? {
            switch self {
            case .noFlights: return "SMART_NO_MATCHING_FLIGHTS"
            case .partyFare: return "SMART_AVIASALES_PARTY_FARE_UNAVAILABLE"
            case .hotel: return "SMART_HOTEL_UNAVAILABLE"
            case .room: return "SMART_ROOM_UNAVAILABLE"
            case .quote: return "SMART_QUOTE_UNAVAILABLE"
            case .hotelNetwork: return "SMART_HOTEL_NETWORK_UNAVAILABLE"
            }
        }
    }

    func clear() {
        result = nil; error = nil; connecting = false; progress = .flights
        flightPreview = []; roomPreview = []; transferPreview = nil
        hotelSearchCity = nil; replacementError = nil; hotelsChangedWithFlights = false; excludedHotels = [:]
    }

    func assemble() async {
        guard !busy else { return }
        clear(); busy = true
        defer { busy = false; hotelSearchCity = nil }
        let p = preferences
        do {
            let plan: SmartPlan = try await APIClient.shared.post("/api/package/smart/plan", body: SmartPlanRequest(origin: p.origin, month: p.monthKey, durationDays: p.duration, both: p.scope == .makkahAndMadinah, firstCity: p.firstCity.rawValue, source: "published"), timeoutInterval: 25)
            guard plan.ok else { throw APIError.invalidResponse }
            try Task.checkCancellation()
            var matched: JourneyStore?
            // Server orders the published, direct candidates by duration deviation.
            for pair in plan.published {
                try Task.checkCancellation()
                guard let out = SmartConfiguratorPreferences.date(pair.departureDay), let back = SmartConfiguratorPreferences.date(pair.returnDay) else { continue }
                let draft = p.draft(out: out, back: back)
                let resolved: (outbound: FlightOffer, inbound: FlightOffer)
                do { resolved = try await CuratedFlightRecommendationService.shared.resolvePublishedSelection(trip: draft, selection: pair.selection) }
                catch let error as APIError {
                    switch error {
                    case .server(let status, _) where [400, 404, 409, 422].contains(status): continue
                    case .status(let status) where [400, 404, 409, 422].contains(status): continue
                    default: throw error
                    }
                }
                guard Self.valid(resolved.outbound, resolved.inbound, p: p), resolved.outbound.stops == 0, resolved.inbound.stops == 0 else { continue }
                let journey = JourneyStore(); journey.usesLocalJourney = true; journey.trip = draft; journey.packageFlightPath = .publishedDirect
                journey.selectedPublishedCompleteID = pair.completeID; journey.selectedPublishedOutboundID = pair.outboundID; journey.selectedPublishedReturnID = pair.returnID
                journey.chooseOutboundFlight(resolved.outbound); journey.chooseInboundFlight(resolved.inbound)
                matched = journey; break
            }
            if matched == nil {
                // Cached Data API only. The existing engine cannot price child/infant
                // fares from Aviasales with Nuitee; never substitute adult prices.
                guard p.childAges.isEmpty else { throw Failure.partyFare }
                let data: SmartPlan = try await APIClient.shared.post("/api/package/smart/plan", body: SmartPlanRequest(origin: p.origin, month: p.monthKey, durationDays: p.duration, both: p.scope == .makkahAndMadinah, firstCity: p.firstCity.rawValue, source: "data"), timeoutInterval: 90)
                guard data.ok else { throw APIError.invalidResponse }
                for pair in data.dataPairs {
                    try Task.checkCancellation()
                    guard let out = SmartConfiguratorPreferences.date(pair.departureDay), let back = SmartConfiguratorPreferences.date(pair.returnDay) else { continue }
                    let journey = JourneyStore(); journey.usesLocalJourney = true; journey.trip = p.draft(out: out, back: back)
                    journey.stageAviasalesOffer(pair.outbound, kind: .outbound)
                    journey.stageAviasalesOffer(pair.inbound, kind: .inbound)
                    guard let offers = journey.makeAviasalesFlightPair(), let inbound = offers.inbound,
                          Self.valid(offers.outbound, inbound, p: p) else { continue }
                    for (offer, kind) in [(pair.outbound, StagedUmrahFlightKind.outbound), (pair.inbound, StagedUmrahFlightKind.inbound)] {
                        journey.stageUmrahFlight(.init(id: offer.id, kind: kind, origin: offer.origin, destination: offer.destination, airline: offer.airlineName, flightNumber: [offer.airlineCode, offer.flightNumber].joined(separator: " "), departureAt: offer.departureAt, returnAt: nil, returnAirline: nil, returnFlightNumber: nil, source: "Aviasales"))
                    }
                    journey.chooseOutboundFlight(offers.outbound); journey.chooseInboundFlight(inbound)
                    matched = journey; break
                }
            }
            try Task.checkCancellation()
            guard let journey = matched else { throw Failure.noFlights }
            journey.tripSummaryChildAges = p.childAges
            connecting = (journey.selectedOutbound?.stops ?? 0) > 0 || (journey.selectedInbound?.stops ?? 0) > 0
            progress = .hotels
            journey.usesLocalJourney = true
            guard let outbound = journey.selectedOutbound, let inbound = journey.selectedInbound else { throw Failure.noFlights }
            journey.trip.selectedReturnAirport = inbound.origin == "MED" ? .madinah : .jeddah
            let iso = ISO8601DateFormatter()
            journey.localJourneyFlights = [outbound, inbound].map { flight in
                LocalJourneyFlight(id: flight.id, origin: flight.origin, destination: flight.destination,
                    airline: flight.airline, flightNumber: flight.flightNumber, airlineCode: flight.airlineCode ?? "",
                    durationMinutes: flight.durationMinutes, stops: flight.stops,
                    departureAt: iso.string(from: flight.departureAt), arrivalAt: iso.string(from: flight.arrivalAt), displayedPrice: nil)
            }
            flightPreview = [outbound, inbound]
            let windows = TripStayPlanner.windows(for: journey.trip)
            let stays: [(String, TripStayWindow)] = {
                var values = [("makkah", windows.makkah)]
                if let madinah = windows.madinah { values.append(("madinah", madinah)) }
                return values.sorted { $0.1.checkIn < $1.1.checkIn }
            }()
            // Start with the adult-only occupancy rule; if no compatible supplier
            // room exists, retry with an additional room and show the real allocation.
            let minimum = journey.trip.rooms
            let fallback = min(p.adults, max(minimum, (p.adults + p.children + p.infants + 1) / 2))
            var selectedRooms: [String: LocalJourneyRoom]?
            for count in minimum...fallback {
                var candidate: [String: LocalJourneyRoom] = [:]
                roomPreview = []
                do {
                    for (city, window) in stays {
                        hotelSearchCity = city
                        let selected = try await selectRooms(city: city, window: window, p: p, count: count)
                        candidate.merge(selected) { _, new in new }
                        roomPreview = Self.sortedRooms(candidate)
                    }
                    journey.trip.rooms = count
                    selectedRooms = candidate
                    break
                } catch Failure.room {
                    try Task.checkCancellation()
                    if count == fallback { throw Failure.room }
                }
            }
            hotelSearchCity = nil
            guard let rooms = selectedRooms else { throw Failure.room }
            journey.localJourneyRooms = rooms
            try Task.checkCancellation()
            progress = .transfer
            journey.chooseTransferVehicle(journey.recommendedTransferVehicle())
            journey.confirmTransferSelection()
            transferPreview = journey.selectedTransferVehicle?.modelName
            progress = .price
            await journey.buildQuote()
            try Task.checkCancellation()
            guard Self.validReview(journey) else { throw APIError.server(409, journey.errorMessage ?? "SMART_QUOTE_UNAVAILABLE") }
            result = journey; progress = .ready
            syncReview()
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func syncReview() {
        guard let result else { return }
        preferences.adults = result.trip.adults
        if result.tripSummaryChildAges.count == result.trip.children + result.trip.infants { preferences.childAges = result.tripSummaryChildAges }
        roomPreview = Self.sortedRooms(result.localJourneyRooms)
        flightPreview = [result.selectedOutbound, result.selectedInbound].compactMap { $0 }
        transferPreview = result.selectedTransferVehicle?.modelName
    }

    enum EditKind: Hashable { case flights, hotel(String), transfer }

    func makeEditJourney() -> JourneyStore? {
        guard let previous = result, !busy else { return nil }
        let next = JourneyStore()
        next.usesLocalJourney = true
        next.trip = previous.trip
        next.tripSummaryChildAges = previous.tripSummaryChildAges
        next.flightSearchFlexDays = previous.flightSearchFlexDays
        next.packageFlightPath = previous.packageFlightPath
        next.selectedPublishedCompleteID = previous.selectedPublishedCompleteID
        next.selectedPublishedOutboundID = previous.selectedPublishedOutboundID
        next.selectedPublishedReturnID = previous.selectedPublishedReturnID
        next.stagedUmrahFlights = previous.stagedUmrahFlights
        next.stagedAviasalesOffers = previous.stagedAviasalesOffers
        next.mixedFlightIdentity = previous.mixedFlightIdentity
        next.localJourneyFlights = previous.localJourneyFlights
        next.localJourneyRooms = previous.localJourneyRooms
        next.selectedOutbound = previous.selectedOutbound
        next.selectedInbound = previous.selectedInbound
        copyTransfer(from: previous, to: next)
        return next
    }

    private func copyTransfer(from previous: JourneyStore, to next: JourneyStore) {
        next.selectedTransferVehicle = previous.selectedTransferVehicle
        next.haramainTrainSelected = previous.haramainTrainSelected
        next.haramainFareClass = previous.haramainFareClass
        next.haramainAdultTickets = previous.haramainAdultTickets
        next.haramainChildTickets = previous.haramainChildTickets
        next.confirmTransferSelection()
    }

    /// Never mutate the last confirmed package until the replacement is priced.
    func applyEdit(_ next: JourneyStore, kind: EditKind) async {
        guard !busy, let previous = result else { return }
        busy = true; replacementError = nil
        var replacedHotel = false
        defer { busy = false; hotelSearchCity = nil }
        do {
            guard next.trip.adults == previous.trip.adults,
                  next.trip.children == previous.trip.children,
                  next.trip.infants == previous.trip.infants,
                  next.trip.rooms == previous.trip.rooms,
                  next.trip.scope == previous.trip.scope else { throw Failure.room }
            if kind == .flights {
                copyTransfer(from: previous, to: next)
                let windows = TripStayPlanner.windows(for: next.trip)
                var stays = [("makkah", windows.makkah)]
                if let madinah = windows.madinah { stays.append(("madinah", madinah)) }
                for (city, window) in stays {
                    let old = previous.localJourneyRooms.filter { $0.value.city == city }
                    if old.count == next.trip.rooms && old.values.allSatisfy({ $0.checkin == window.checkIn && $0.checkout == window.checkOut }) {
                        next.localJourneyRooms.merge(old) { _, new in new }
                    } else {
                        hotelSearchCity = city
                        var p = preferences
                        if let stars = old.values.first?.hotel.roundedStars {
                            p.tier = stars <= 2 ? .economy : stars == 3 ? .standard : stars == 4 ? .comfort : .luxury
                        }
                        let rooms: [String: LocalJourneyRoom]
                        if let refreshed = try await refreshPreviousRooms(old, window: window, count: next.trip.rooms) {
                            rooms = refreshed
                        } else {
                            rooms = try await selectRooms(city: city, window: window, p: p, count: next.trip.rooms)
                            replacedHotel = true
                        }
                        next.localJourneyRooms.merge(rooms) { _, new in new }
                    }
                }
            }
            guard next.localRoomsComplete,
                  let vehicle = next.selectedTransferVehicle,
                  vehicle.passengerCapacity >= next.trip.travelerCount else { throw Failure.room }
            next.confirmTransferSelection()
            await next.buildQuote()
            try Task.checkCancellation()
            guard Self.validReview(next) else { throw APIError.server(409, next.errorMessage ?? "SMART_QUOTE_UNAVAILABLE") }
            result = next
            hotelsChangedWithFlights = kind == .flights && replacedHotel
            connecting = (next.selectedOutbound?.stops ?? 0) > 0 || (next.selectedInbound?.stops ?? 0) > 0
            syncReview()
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { replacementError = error.localizedDescription } }
    }

    private func refreshPreviousRooms(_ old: [String: LocalJourneyRoom], window: TripStayWindow, count: Int) async throws -> [String: LocalJourneyRoom]? {
        guard old.count == count, window.checkOut > window.checkIn else { return nil }
        let service = NuiteeHotelService()
        var refreshed: [String: LocalJourneyRoom] = [:]
        for (key, room) in old.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            let response = try await service.rates(hotelID: room.hotel.id, checkin: window.checkIn, checkout: window.checkOut,
                adults: room.adults, childrenAges: room.childrenAges, smartTimeout: true)
            guard response.ok, response.checkin == NuiteeHotelService.dateText(window.checkIn),
                                  response.checkout == NuiteeHotelService.dateText(window.checkOut), response.adults == room.adults,
                                  let rate = response.rates.filter({
                $0.roomId == room.rate.roomId && $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 && !$0.offerId.isEmpty
            }).min(by: { $0.price < $1.price }) else { return nil }
            refreshed[key] = .init(id: room.id, city: room.city, hotel: room.hotel, rate: rate,
                checkin: window.checkIn, checkout: window.checkOut, adults: room.adults, childrenAges: room.childrenAges, meals: room.meals)
        }
        return refreshed
    }

    private static func sortedRooms(_ rooms: [String: LocalJourneyRoom]) -> [LocalJourneyRoom] {
        rooms.values.sorted { $0.checkin == $1.checkin ? $0.id < $1.id : $0.checkin < $1.checkin }
    }

    /// A replacement is transactional: the old verified package remains bookable
    /// unless the new hotel and the new server quote both succeed.
    func replaceHotel(city: String) async {
        guard !busy, replacingCity == nil, let previous = result,
              let current = previous.localJourneyRooms["\(city):0"] else { return }
        replacingCity = city; replacementError = nil
        defer { replacingCity = nil }
        do {
            var excluded = excludedHotels[city, default: []]
            excluded.insert(current.hotel.id)
            let rooms = try await selectRooms(city: city, window: .init(checkIn: current.checkin, checkOut: current.checkout), p: preferences, count: previous.trip.rooms, excluding: excluded)
            try Task.checkCancellation()
            let next = JourneyStore()
            next.usesLocalJourney = true; next.trip = previous.trip
            next.tripSummaryChildAges = previous.tripSummaryChildAges
            next.mixedFlightIdentity = previous.mixedFlightIdentity
            next.packageFlightPath = previous.packageFlightPath
            next.selectedPublishedCompleteID = previous.selectedPublishedCompleteID
            next.selectedPublishedOutboundID = previous.selectedPublishedOutboundID
            next.selectedPublishedReturnID = previous.selectedPublishedReturnID
            next.stagedAviasalesOffers = previous.stagedAviasalesOffers
            next.stagedUmrahFlights = previous.stagedUmrahFlights
            next.localJourneyFlights = previous.localJourneyFlights
            next.selectedOutbound = previous.selectedOutbound; next.selectedInbound = previous.selectedInbound
            next.localJourneyRooms = previous.localJourneyRooms.filter { $0.value.city != city }
            next.localJourneyRooms.merge(rooms) { _, new in new }
            next.selectedTransferVehicle = previous.selectedTransferVehicle
            next.haramainTrainSelected = previous.haramainTrainSelected
            next.haramainFareClass = previous.haramainFareClass
            next.haramainAdultTickets = previous.haramainAdultTickets
            next.haramainChildTickets = previous.haramainChildTickets
            next.confirmTransferSelection()
            await next.buildQuote()
            try Task.checkCancellation()
            guard Self.validReview(next) else { throw APIError.server(409, next.errorMessage ?? "SMART_QUOTE_UNAVAILABLE") }
            excludedHotels[city] = excluded
            roomPreview = Self.sortedRooms(next.localJourneyRooms)
            result = next
            syncReview()
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { replacementError = error.localizedDescription } }
    }

    private func selectRooms(city: String, window: TripStayWindow, p: SmartConfiguratorPreferences, count: Int, excluding: Set<String> = []) async throws -> [String: LocalJourneyRoom] {
        guard count > 0, count <= p.adults, window.checkOut > window.checkIn else { throw Failure.room }
        let service = NuiteeHotelService()
        let adults = (0..<count).map { p.adults / count + ($0 < p.adults % count ? 1 : 0) }
        var ages = Array(repeating: [Int](), count: count)
        for (i, age) in p.childAges.enumerated() { ages[i % count].append(age) }
        func price(_ hotel: NuiteeHotel) -> Double {
            hotel.minimumRate.flatMap { $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 ? $0.price : nil } ?? .infinity
        }
        let largestRoom = adults.indices.max { a, b in
            adults[a] + ages[a].count < adults[b] + ages[b].count
        } ?? 0
        var hadRequestError = false
        var consecutiveErrors = 0
        // Use the complete city snapshot, then choose the commercial category locally.
        // Price only eligible candidates; never hide inventory behind a 12-item UI page.
        let catalog: NuiteeHotelListEnvelope
        do { catalog = try await service.hotels(city: city, checkin: window.checkIn, checkout: window.checkOut, adults: adults[largestRoom], catalogOnly: true) }
        catch { try Task.checkCancellation(); throw Failure.hotelNetwork }
        guard catalog.ok else { throw Failure.hotelNetwork }
        let eligible = catalog.hotels.filter { hotel in
            let category = hotel.roundedStars == 0 ? 3 : hotel.roundedStars
            return !excluding.contains(hotel.id) && p.tier.selectableHotelStars.contains(category)
        }
        for start in stride(from: 0, to: eligible.count, by: 40) {
            try Task.checkCancellation()
            let batch = Array(eligible[start..<min(start + 40, eligible.count)])
            var candidates = batch
            do {
                let page = try await service.pricePage(city: city, checkin: window.checkIn, checkout: window.checkOut,
                    adults: adults[largestRoom], hotelIDs: batch.map(\.id), childrenAges: ages[largestRoom])
                let indexed = page.hotels.reduce(into: [String: NuiteeHotelService.PriceRow]()) { $0[$1.id] = $1 }
                candidates = batch.map { hotel in var item = hotel; item.minimumRate = indexed[hotel.id]?.minimumRate; item.rateStatus = indexed[hotel.id]?.rateStatus; return item }
                if page.rateError != nil { hadRequestError = true }
                if page.rateError == "NUITEE_RATE_LIMIT" { throw Failure.hotelNetwork }
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                if NuiteeHotelService.isRateLimited(error) { throw Failure.hotelNetwork }
                hadRequestError = true
            }
            // The Smart recommendation may stop at the first compatible positive
            // quote; the interactive hotel picker always exposes the full catalogue.
            candidates.sort { a,b in
                let pa=price(a), pb=price(b)
                return pa == pb ? (a.rating ?? 0) > (b.rating ?? 0) : pa < pb
            }
            for hotel in candidates {
                try Task.checkCancellation()
                if hotel.rateStatus == "no_availability" { continue }
                var rooms: [String: LocalJourneyRoom] = [:]
                var ratesByOccupancy: [String: NuiteeRatesEnvelope] = [:]
                do {
                    for i in 0..<count {
                        try Task.checkCancellation()
                        let occupancy = "\(adults[i]):\(ages[i])"
                        let response: NuiteeRatesEnvelope
                        if let cached = ratesByOccupancy[occupancy] { response = cached }
                        else {
                            response = try await service.rates(hotelID: hotel.id, checkin: window.checkIn, checkout: window.checkOut, adults: adults[i], childrenAges: ages[i], smartTimeout: true)
                            ratesByOccupancy[occupancy] = response
                        }
                        guard response.ok, response.checkin == NuiteeHotelService.dateText(window.checkIn),
                              response.checkout == NuiteeHotelService.dateText(window.checkOut), response.adults == adults[i],
                              let rate = response.rates.filter({ $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 && !$0.offerId.isEmpty }).min(by: { $0.price < $1.price }) else { break }
                        let key = "\(city):\(i)"
                        rooms[key] = .init(id: key, city: city, hotel: hotel, rate: rate, checkin: window.checkIn, checkout: window.checkOut, adults: adults[i], childrenAges: ages[i])
                    }
                    consecutiveErrors = 0
                    if rooms.count == count { return rooms }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try Task.checkCancellation()
                    hadRequestError = true; consecutiveErrors += 1
                    if NuiteeHotelService.isRateLimited(error) || consecutiveErrors >= 3 { throw Failure.hotelNetwork }
                }
            }
        }
        if hadRequestError { throw Failure.hotelNetwork }
        throw Failure.room
    }

    private static func valid(_ out: FlightOffer, _ back: FlightOffer, p: SmartConfiguratorPreferences) -> Bool {
        func localDay(_ date: Date, _ code: String) -> String {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
            f.timeZone = FlightReferenceCatalog.timeZone(for: code) ?? TimeZone(secondsFromGMT: 0)
            return f.string(from: date)
        }
        let first = p.scope == .makkahOnly ? "JED" : p.firstCity.rawValue
        let last = p.scope == .makkahAndMadinah && p.firstCity == .jeddah ? "MED" : "JED"
        let departure = localDay(out.departureAt, out.origin), arrival = localDay(out.arrivalAt, out.destination), returned = localDay(back.departureAt, back.origin)
        guard out.isVerifiedForBooking, back.isVerifiedForBooking, out.origin == p.origin, out.destination == first, back.origin == last, back.destination == p.origin,
              departure.hasPrefix(p.monthKey), out.departureAt > Date(), back.departureAt > out.arrivalAt,
              let d = SmartConfiguratorPreferences.date(departure), let r = SmartConfiguratorPreferences.date(returned), let a = SmartConfiguratorPreferences.date(arrival) else { return false }
        let days = (Calendar.current.dateComponents([.day], from: d, to: r).day ?? 0) + 1
        let nights = Calendar.current.dateComponents([.day], from: a, to: r).day ?? 0
        return abs(days - p.duration) <= 4 && nights >= (p.scope == .makkahAndMadinah ? 2 : 1)
    }
}
