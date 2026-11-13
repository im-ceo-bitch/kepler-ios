import Foundation
import SwiftUI

/// The manually assembled package is independent of the guided journey.
/// No local package price, fare markup, or booking proof is generated here.
@MainActor
final class IumrahManualJourneyStore: ObservableObject {
    @Published var outbound: LocalJourneyFlight?
    @Published var inbound: LocalJourneyFlight?
    @Published var rooms: [String: LocalJourneyRoom] = [:]
    @Published var transfer: TransferVehicleKind?
    @Published var scope: JourneyScope = .makkahAndMadinah
    @Published var adults = 2
    @Published var cabin: FlightCabinClass = .economy

    var componentCount: Int { (outbound == nil ? 0 : 1) + (inbound == nil ? 0 : 1) + rooms.count + (transfer == nil ? 0 : 1) }
    var cities: [String] { scope == .makkahOnly ? ["makkah"] : ["makkah", "madinah"] }
    var revisionKey: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let values = (try? encoder.encode(rooms))?.base64EncodedString() ?? ""
        let flights = (try? encoder.encode([outbound, inbound]))?.base64EncodedString() ?? ""
        return [flights, values, transfer?.rawValue ?? "", scope.rawValue, String(adults), cabin.rawValue].joined(separator: "|")
    }
    func select(_ flight: LocalJourneyFlight) {
        if ["JED", "MED"].contains(flight.destination) { outbound = flight }
        else if ["JED", "MED"].contains(flight.origin) { inbound = flight }
    }
    func select(_ room: LocalJourneyRoom) {
        rooms[room.city] = room
        if room.city == "madinah" { scope = .makkahAndMadinah }
    }
    func changeScope(_ value: JourneyScope) {
        scope = value
        if value == .makkahOnly { rooms.removeValue(forKey: "madinah") }
    }
    private func day(_ raw: String?, airport: String) -> Date? {
        guard let parts = IumrahPremiumFlightLeg.localParts(raw, code: airport) else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: parts.day)
    }
    var trip: TripDraft? {
        guard let outbound, let inbound,
              outbound.origin == inbound.destination,
              let first = SaudiArrivalAirport(rawValue: outbound.destination),
              let last = SaudiArrivalAirport(rawValue: inbound.origin),
              let departure = day(outbound.departureAt, airport: outbound.origin),
              let arrival = day(outbound.arrivalAt, airport: outbound.destination),
              let returning = day(inbound.departureAt, airport: inbound.origin),
              returning > arrival, arrival >= departure,
              departure >= Calendar.current.startOfDay(for: Date()),
              scope != .makkahOnly || (first == .jeddah && last == .jeddah),
              scope != .makkahAndMadinah || (Calendar.current.dateComponents([.day], from: arrival, to: returning).day ?? 0) >= 2 else { return nil }
        var draft = TripDraft()
        draft.origin = outbound.origin; draft.originAirport = nil
        draft.departureDate = departure; draft.saudiArrivalDate = arrival; draft.returnDate = returning
        draft.arrivalAirport = first; draft.selectedReturnAirport = last
        draft.scope = scope; draft.adults = adults; draft.rooms = 1; draft.children = 0; draft.infants = 0
        draft.flightTripType = .roundTrip
        var filters = draft.effectiveFlightFilters; filters.cabinClass = cabin; draft.flightFilters = filters
        return draft
    }
    func expectedWindow(_ city: String) -> TripStayWindow? {
        guard let trip else { return nil }
        let windows = TripStayPlanner.windows(for: trip)
        return city == "madinah" ? windows.madinah : windows.makkah
    }
    func validRoom(_ city: String) -> Bool {
        guard let room = rooms[city], let window = expectedWindow(city) else { return false }
        let cal = Calendar.current
        return room.adults == adults && room.childrenAges.isEmpty && room.rate.currency == "USD" && room.rate.price.isFinite && room.rate.price > 0 &&
            cal.isDate(room.checkin, inSameDayAs: window.checkIn) && cal.isDate(room.checkout, inSameDayAs: window.checkOut)
    }
    var sourceCompatible: Bool {
        guard let a = outbound, let b = inbound else { return false }
        for flight in [a, b] {
            if let publishedCabin = flight.publishedCabin,
               publishedCabin.lowercased().replacingOccurrences(of: " ", with: "_") != cabin.rawValue { return false }
        }
        if let x = a.publishedID, let y = b.publishedID {
            return a.publishedIsPair == true || b.publishedIsPair == true ? x == y && a.publishedIsPair == true && b.publishedIsPair == true : x != y
        }
        if let x = a.discoveryOffer, let y = b.discoveryOffer { return !x.isRoundTrip && !y.isRoundTrip && cabin == .economy }
        if a.publishedID != nil && a.publishedIsPair != true && b.discoveryOffer?.isRoundTrip == false { return cabin == .economy }
        if b.publishedID != nil && b.publishedIsPair != true && a.discoveryOffer?.isRoundTrip == false { return cabin == .economy }
        return false
    }
    var complete: Bool {
        guard trip != nil, sourceCompatible, let transfer, transfer.passengerCapacity >= adults,
              (1...6).contains(adults) else { return false }
        return cities.allSatisfy { validRoom($0) }
    }
    private func identity(_ flight: LocalJourneyFlight) -> String? {
        if let id = flight.publishedID, flight.publishedIsPair != true { return "curated:" + id }
        guard let offer = flight.discoveryOffer, !offer.isRoundTrip else { return nil }
        return ["aviasales", "ow", offer.origin.uppercased(), offer.destination.uppercased(), String(offer.departureAt.prefix(10)), "-", offer.airlineCode.uppercased(), offer.flightNumber.uppercased().filter { $0.isLetter || $0.isNumber }, "-", "-"].joined(separator: ":")
    }
    private func staged(_ flight: LocalJourneyFlight, _ kind: StagedUmrahFlightKind) -> StagedUmrahFlight {
        .init(id: flight.id, kind: kind, origin: flight.origin, destination: flight.destination, airline: flight.airline,
              flightNumber: flight.flightNumber, departureAt: flight.departureAt, returnAt: nil, returnAirline: nil,
              returnFlightNumber: nil, source: flight.publishedID == nil ? "Aviasales" : "iumrah")
    }
    /// Assemble the exact same server request as the guided flow, with the same
    /// trusted provider IDs. The separate store is only used for this review.
    func makeQuoteJourney() -> JourneyStore? {
        guard complete, let draft = trip, let a = outbound, let b = inbound, let transfer else { return nil }
        let result = JourneyStore()
        result.trip = draft
        result.stageUmrahFlight(staged(a, .outbound)); result.stageUmrahFlight(staged(b, .inbound))
        if let x = a.publishedID, let y = b.publishedID {
            result.packageFlightPath = .publishedDirect
            if a.publishedIsPair == true { result.selectedPublishedCompleteID = x }
            else { result.selectedPublishedOutboundID = x; result.selectedPublishedReturnID = y }
        } else if let x = a.discoveryOffer, let y = b.discoveryOffer {
            result.stageAviasalesOffer(x, kind: .outbound); result.stageAviasalesOffer(y, kind: .inbound)
        } else {
            guard let x = identity(a), let y = identity(b) else { return nil }
            result.mixedFlightIdentity = "mixed:" + x + "~" + y
        }
        result.usesLocalJourney = true
        result.localJourneyFlights = [a, b]
        result.localJourneyRooms = Dictionary(uniqueKeysWithValues: cities.compactMap { city in rooms[city].map { ($0.id, $0) } })
        result.chooseTransferVehicle(transfer); result.confirmTransferSelection()
        return result
    }
}
