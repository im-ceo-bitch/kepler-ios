import Foundation

struct LocalJourneyFlight: Codable, Identifiable {
    let id: String
    let origin: String
    let destination: String
    let airline: String
    let flightNumber: String
    let airlineCode: String
    let durationMinutes: Int
    let stops: Int
    let departureAt: String
    let arrivalAt: String?
    /// USD per traveler, exactly as shown in discovery; nil is never zero.
    let displayedPrice: Double?
}

struct LocalJourneyRoom: Codable, Identifiable {
    let id: String
    let city: String
    let hotel: NuiteeHotel
    let rate: NuiteeRoomRate
    let checkin: Date
    let checkout: Date
    let adults: Int
    let childrenAges: [Int]
}

/// A request, never a priced room. No amount or offer ID exists until confirmed.
struct LocalJourneyPendingHotel: Codable, Identifiable {
    let id: String
    let city: String
    let hotel: NuiteeHotel
    let checkin: Date
    let checkout: Date
    let adults: Int
    let childrenAges: [Int]
    let requestedAt: Date
}

struct LocalJourneyPriceLine: Identifiable {
    let id: String
    let title: String
    let amount: Decimal
}

extension JourneyStore {
    var localRoomsComplete: Bool {
        let cities = trip.scope == .makkahAndMadinah ? ["makkah", "madinah"] : ["makkah"]
        return cities.allSatisfy { city in
            (0..<trip.rooms).allSatisfy { localJourneyRooms["\(city):\($0)"] != nil || localPendingHotels["\(city):\($0)"] != nil }
        }
    }

    var localPriceLines: [LocalJourneyPriceLine]? {
        guard localJourneyFlights.count == 2, localRoomsComplete,
              localJourneyFlights.allSatisfy({ ($0.displayedPrice ?? 0) > 0 }) else { return nil }
        // Data API flight amounts are adult-unit quotes. It is unsafe to
        // multiply by children/infants: their fare class and ticketing terms
        // are different. In that case no fabricated aggregate is displayed.
        guard trip.children == 0, trip.infants == 0, trip.adults > 0 else { return nil }
        let people = Decimal(trip.adults)
        var lines = localJourneyFlights.enumerated().map { index, flight in
            LocalJourneyPriceLine(id: "flight:\(index)", title: "\(flight.origin) → \(flight.destination)",
                                  amount: Decimal(flight.displayedPrice!) * people)
        }
        for room in localJourneyRooms.values.sorted(by: { $0.id < $1.id }) {
            guard room.rate.currency == "USD", room.rate.price.isFinite, room.rate.price > 0 else { return nil }
            lines.append(.init(id: room.id, title: room.hotel.name + " · " + room.rate.roomName, amount: Decimal(room.rate.price)))
        }
        // Existing service costs, markup and fee are preserved from pricing.ts v9.
        let both = trip.scope == .makkahAndMadinah
        lines.append(.init(id: "visa", title: "Визы", amount: 120 * people))
        lines.append(.init(id: "transfer", title: "Трансфер", amount: 300))
        lines.append(.init(id: "guide", title: "Сопровождение", amount: both ? 300 : 100))
        lines.append(.init(id: "ziyarat", title: "Зияраты", amount: both ? 200 : 100))
        let stay = TripStayPlanner.breakdown(for: trip)
        let diners = Decimal(trip.adults + trip.children)
        var meals: Decimal = 0
        if trip.packageTier == .economy || trip.packageTier == .standard {
            meals = 15 * Decimal(stay.totalDays) * diners
        } else {
            let unit: Decimal = trip.packageTier == .luxury ? 50 : 30
            if isMealEnabled(.lunch, city: .makkah) { meals += unit * Decimal(stay.makkahNights) * diners }
            if isMealEnabled(.dinner, city: .makkah) { meals += unit * Decimal(stay.makkahNights) * diners }
            if both && isMealEnabled(.dinner, city: .madinah) { meals += unit * Decimal(stay.madinahNights) * diners }
        }
        lines.append(.init(id: "meals", title: "Питание и обслуживание", amount: meals))
        let subtotal = lines.reduce(Decimal.zero) { $0 + $1.amount }
        let marked = subtotal * (trip.packageTier == .luxury ? Decimal(string: "1.35")! : Decimal(string: "1.25")!)
        let selling = marked / Decimal(string: "0.98")!
        let perPerson = NSDecimalNumber(decimal: selling / people / 5).doubleValue.rounded() * 5
        let rounded = Decimal(max(5, perPerson)) * people
        lines.append(.init(id: "organization", title: "Организация, комиссия и округление", amount: rounded - subtotal))
        let upgrade = (selectedTransferVehicle ?? recommendedTransferVehicle()).publicUpgradeUsd(for: trip.scope)
        if upgrade > 0 { lines.append(.init(id: "vehicle", title: "Класс трансфера", amount: upgrade)) }
        if both && haramainTrainSelected { lines.append(.init(id: "train", title: "Haramain", amount: haramainTrainAddOnUsd)) }
        return lines
    }

    func rebuildLocalJourneyQuote() {
        guard let lines = localPriceLines else { quote = nil; return }
        let total = lines.reduce(Decimal.zero) { $0 + $1.amount }
        quote = PackageQuote(totalPackagePrice: total, pricePerPerson: total / Decimal(trip.travelerCount),
                             currency: "USD", isEstimated: true, quoteId: "local-\(UUID().uuidString)")
    }
}

struct LocalJourneyRequestSnapshot: Codable {
    let version: Int
    let trip: TripDraft
    let flights: [LocalJourneyFlight]
    let rooms: [LocalJourneyRoom]
    var pendingHotels: [LocalJourneyPendingHotel]? = nil
    let transfer: String
    let trainTickets: Int
    let trainClass: String
    let estimatedTotalUSD: Decimal?
}

/// Supplier revalidation used by Hotels, Transfer and Review pull-to-refresh.
/// A missing/expired/failed exact offer is removed rather than silently
/// presenting a stale rate as today's amount.
@MainActor
extension JourneyStore {
    func refreshLocalJourneyRoomRates() async {
        guard usesLocalJourney else { return }
        let snapshot = localJourneyRooms
        let service = NuiteeHotelService()
        for (key, room) in snapshot.sorted(by: { $0.key < $1.key }) {
            guard !Task.isCancelled else { return }
            do {
                let response = try await service.rates(
                    hotelID: room.hotel.id, checkin: room.checkin, checkout: room.checkout,
                    adults: room.adults, childrenAges: room.childrenAges)
                guard !response.sandbox, let current = response.rates.first(where: {
                    $0.offerId == room.rate.offerId && $0.roomId == room.rate.roomId
                }), current.currency.uppercased() == "USD", current.price.isFinite,
                    current.price > 0 else {
                    localJourneyRooms.removeValue(forKey: key)
                    continue
                }
                // Never overwrite a newly edited choice with a previous request.
                guard localJourneyRooms[key]?.rate.offerId == room.rate.offerId else { continue }
                localJourneyRooms[key] = LocalJourneyRoom(
                    id: room.id, city: room.city, hotel: room.hotel, rate: current,
                    checkin: room.checkin, checkout: room.checkout, adults: room.adults,
                    childrenAges: room.childrenAges)
            } catch {
                // A provider error is not proof of availability or of price.
                if localJourneyRooms[key]?.rate.offerId == room.rate.offerId {
                    localJourneyRooms.removeValue(forKey: key)
                }
            }
        }
        rebuildLocalJourneyQuote()
    }
}
