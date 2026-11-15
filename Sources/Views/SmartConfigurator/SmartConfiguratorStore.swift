import Foundation
import Combine

struct SmartConfiguratorPreferences: Hashable {
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
        trip.rooms = min(adults, max(1, (adults + children + infants + 1) / 2))
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
    private var excludedHotels: [String: Set<String>] = [:]


    private enum Failure: LocalizedError {
        case noFlights, partyFare, hotel, room, quote, hotelNetwork, sandboxHotel
        var errorDescription: String? {
            switch self {
            case .noFlights: return "SMART_NO_MATCHING_FLIGHTS"
            case .partyFare: return "SMART_AVIASALES_PARTY_FARE_UNAVAILABLE"
            case .hotel: return "SMART_HOTEL_UNAVAILABLE"
            case .room: return "SMART_ROOM_UNAVAILABLE"
            case .quote: return "SMART_QUOTE_UNAVAILABLE"
            case .hotelNetwork: return "SMART_HOTEL_NETWORK_UNAVAILABLE"
            case .sandboxHotel: return "SMART_HOTEL_SANDBOX"
            }
        }
    }

    func clear() {
        result = nil; error = nil; connecting = false; progress = .flights
        flightPreview = []; roomPreview = []; transferPreview = nil
        hotelSearchCity = nil; replacementError = nil; excludedHotels = [:]
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
            var rooms: [String: LocalJourneyRoom] = [:]
            for (city, window) in stays {
                hotelSearchCity = city
                let selected = try await selectRooms(city: city, window: window, p: p, count: journey.trip.rooms)
                rooms.merge(selected) { _, new in new }
                roomPreview = Self.sortedRooms(rooms)
            }
            hotelSearchCity = nil
            journey.localJourneyRooms = rooms
            try Task.checkCancellation()
            progress = .transfer
            journey.chooseTransferVehicle(journey.recommendedTransferVehicle())
            journey.confirmTransferSelection()
            transferPreview = journey.selectedTransferVehicle?.modelName
            progress = .price
            await journey.buildQuote()
            try Task.checkCancellation()
            guard journey.hasFinalGeneratorQuote, journey.quote?.bookingAllowed == true else { throw Failure.quote }
            result = journey; progress = .ready
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }

    func syncReview() {
        guard let result else { return }
        roomPreview = Self.sortedRooms(result.localJourneyRooms)
        flightPreview = [result.selectedOutbound, result.selectedInbound].compactMap { $0 }
        transferPreview = result.selectedTransferVehicle?.modelName
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
            guard next.hasFinalGeneratorQuote, next.quote?.bookingAllowed == true else { throw Failure.quote }
            excludedHotels[city] = excluded
            roomPreview = Self.sortedRooms(next.localJourneyRooms)
            result = next
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { replacementError = error.localizedDescription } }
    }

    private func selectRooms(city: String, window: TripStayWindow, p: SmartConfiguratorPreferences, count: Int, excluding: Set<String> = []) async throws -> [String: LocalJourneyRoom] {
        guard count > 0, count <= p.adults, window.checkOut > window.checkIn else { throw Failure.room }
        let service = NuiteeHotelService()
        let adults = (0..<count).map { p.adults / count + ($0 < p.adults % count ? 1 : 0) }
        var ages = Array(repeating: [Int](), count: count)
        for (i, age) in p.childAges.enumerated() { ages[i % count].append(age) }
        let catalog = try await service.hotels(city: city, checkin: window.checkIn, checkout: window.checkOut, adults: adults.max() ?? 1, smartTimeout: true)
        guard !catalog.sandbox else { throw Failure.sandboxHotel }
        guard catalog.ok else { throw Failure.hotelNetwork }
        func price(_ hotel: NuiteeHotel) -> Double {
            hotel.minimumRate.flatMap { $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 ? $0.price : nil } ?? .infinity
        }
        // Strict Smart-only star filter. Catalog minimum rates are hints, not bookable offers.
        let eligible = catalog.hotels.filter { hotel in
            guard let stars = hotel.stars, stars.isFinite, (0...5).contains(stars) else { return false }
            return !excluding.contains(hotel.id) && p.tier.selectableHotelStars.contains(hotel.roundedStars)
        }.sorted { a, b in
            let pa = price(a), pb = price(b)
            return pa == pb ? (a.rating ?? 0) > (b.rating ?? 0) : pa < pb
        }
        var hadRequestError = false
        var consecutiveErrors = 0
        // Bound supplier work; priced candidates first, then verify actual room offers.
        for hotel in eligible.prefix(12) {
            try Task.checkCancellation()
            var rooms: [String: LocalJourneyRoom] = [:]
            do {
                for i in 0..<count {
                    try Task.checkCancellation()
                    let response = try await service.rates(hotelID: hotel.id, checkin: window.checkIn, checkout: window.checkOut, adults: adults[i], childrenAges: ages[i], smartTimeout: true)
                    guard response.ok, !response.sandbox, let rate = response.rates.filter({ $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 && !$0.offerId.isEmpty && !$0.roomId.isEmpty }).min(by: { $0.price < $1.price }) else { break }
                    let key = "\(city):\(i)"
                    rooms[key] = .init(id: key, city: city, hotel: hotel, rate: rate, checkin: window.checkIn, checkout: window.checkOut, adults: adults[i], childrenAges: ages[i])
                }
                consecutiveErrors = 0
                if rooms.count == count { return rooms }
            } catch is CancellationError { throw CancellationError() }
            catch {
                try Task.checkCancellation()
                hadRequestError = true; consecutiveErrors += 1
                if consecutiveErrors >= 3 { break }
            }
        }
        if hadRequestError || catalog.rateError != nil { throw Failure.hotelNetwork }
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
