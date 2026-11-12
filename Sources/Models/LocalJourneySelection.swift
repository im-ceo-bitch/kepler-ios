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
    var meals: HotelMealChoices? = nil
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
            (0..<trip.rooms).allSatisfy { localJourneyRooms["\(city):\($0)"] != nil }
        }
    }

    var localPriceLines: [LocalJourneyPriceLine]? {
        guard hasFinalGeneratorQuote, let quote else { return nil }
        return [.init(id: "server-total", title: "iumrah", amount: quote.totalPackagePrice)]
    }

    /// Selection changes invalidate the server quote. The phone never prices a package.
    func invalidateLocalJourneyQuote() {
        quote = nil
    }

    var localBookingRooms: [BookingNuiteeRoomSelection] {
        localJourneyRooms.values.sorted { $0.id < $1.id }.map(\.bookingSelection)
    }
    var localBookingInputKey: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let rooms = (try? encoder.encode(localBookingRooms)).flatMap { String(data:$0,encoding:.utf8) } ?? ""
        let flightKey = localJourneyFlights.map { $0.id + ":" + $0.departureAt }.joined(separator: "|")
        return flightKey + "|" + (mixedFlightIdentity ?? "") + "|" + rooms + "|" + String(trip.hashValue) + "|" + (selectedTransferVehicle?.rawValue ?? "") + "|" + String(haramainTrainSelected) + "|" + String(haramainTicketCount) + "|" + haramainFareClass.rawValue
    }
    var localPackageTier: PackageTier? {
        let stars = localJourneyRooms.values.map { $0.hotel.roundedStars }
        guard !stars.isEmpty, stars.allSatisfy({ (1...5).contains($0) }), let highest = stars.max() else { return nil }
        return highest <= 2 ? .economy : highest <= 4 ? .standard : .luxury
    }

}

extension LocalJourneyRoom {
    var bookingSelection: BookingNuiteeRoomSelection {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let included = rate.supplierMeals
        let chosen = meals ?? HotelMealChoices()
        let effective = HotelMealChoices(breakfast: included.breakfast || hotel.roundedStars >= 4 || chosen.breakfast,
            lunch: city == "makkah" && (included.lunch || chosen.lunch), dinner: included.dinner || chosen.dinner)
        return .init(id:id, city:city, hotelId:hotel.id, offerId:rate.offerId, roomId:rate.roomId,
                     checkin:f.string(from:checkin), checkout:f.string(from:checkout), adults:adults, children:childrenAges, meals:effective)
    }
    var bookingHotel: HotelSummary {
        HotelSummary(id:hotel.id, name:hotel.name, city:city == "madinah" ? "Madinah" : "Makkah",
            stars:hotel.roundedStars, rating:nil, reviewCount:nil, status:"available", coverImageURL:hotel.coverImageURL,
            imageCount:hotel.previewImages?.count ?? 0, roomCount:1, price:nil, updatedAt:"")
    }
    var bookingRoom: HotelRoom {
        HotelRoom(id:rate.roomId, name:rate.roomName, maxGuests:adults + childrenAges.count,
            sizeM2:nil, beds:nil, view:nil, description:rate.mealPlan, amenities:[])
    }
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
                guard let current = response.rates.first(where: {
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
                    childrenAges: room.childrenAges, meals: room.meals)
            } catch {
                // A provider error is not proof of availability or of price.
                if localJourneyRooms[key]?.rate.offerId == room.rate.offerId {
                    localJourneyRooms.removeValue(forKey: key)
                }
            }
        }
        invalidateLocalJourneyQuote()
    }
}


enum ConfiguratorBookingCopy {
    static func message(_ code: String, language: AppSettingsStore.Language) -> String {
        let values: [String]
        if code.contains("AVIASALES_IDENTITY_INVALID") || code.contains("AVIASALES_ROUTE_MISMATCH") {
            values = ["Не удалось проверить выбранный маршрут на сервере. Выберите рейсы заново. Если ошибка повторится, обратитесь в поддержку.", "The server could not verify the selected route. Select the flights again. If this continues, contact support.", "Server tanlangan yo‘nalishni tekshira olmadi. Reyslarni qayta tanlang. Xato takrorlansa, yordam xizmatiga murojaat qiling.", "Сервер танланган йўналишни текшира олмади. Рейсларни қайта танланг. Хато такрорланса, ёрдам хизматига мурожаат қилинг."]
        } else if code.contains("AVIASALES_PARTY_FARE_UNAVAILABLE") {
            values = ["Для этого рейса API не подтвердил тарифы детей и младенцев. Выберите опубликованный рейс с тарифом для вашего состава поездки.", "The API has not confirmed child and infant fares for this flight. Choose a published flight priced for your party.", "API bu reys uchun bolalar va chaqaloqlar tariflarini tasdiqlamadi. Guruhingiz uchun tarifi bor e’lon qilingan reysni tanlang.", "API бу рейс учун болалар ва чақалоқлар тарифларини тасдиқламади. Гуруҳингиз учун тарифи бор эълон қилинган рейсни танланг."]
        } else if code.contains("NUITEE_SELECTED_RATE_EXPIRED") || code.contains("NUITEE_RATE_TERMS_CHANGED") {
            values = ["Тариф или условия номера изменились. Вернитесь к выбору отеля и выберите актуальный номер.", "The room rate or terms changed. Return to hotels and select a current room offer.", "Xona tarifi yoki shartlari o‘zgardi. Mehmonxonalarga qaytib, amaldagi xonani tanlang.", "Хона тарифи ёки шартлари ўзгарди. Меҳмонхоналарга қайтиб, амалдаги хонани танланг."]
        } else if code.contains("NUITEE_") || code.contains("HOTEL_STARS_REQUIRED") {
            values = ["Не удалось подтвердить выбранные номера. Проверьте даты и гостей, затем повторите расчёт или выберите номера заново.", "Could not confirm the selected rooms. Check dates and guests, then retry pricing or select rooms again.", "Tanlangan xonalar tasdiqlanmadi. Sanalar va mehmonlarni tekshirib, narxni qayta hisoblang yoki xonalarni qayta tanlang.", "Танланган хоналар тасдиқланмади. Саналар ва меҳмонларни текшириб, нархни қайта ҳисобланг ёки хоналарни қайта танланг."]
        } else { return code }
        switch language { case .russian: return values[0]; case .uzbek: return values[2]; case .uzbekCyrillic: return values[3]; default: return values[1] }
    }
}

struct HotelMealChoices: Codable, Hashable {
    var breakfast = false
    var lunch = false
    var dinner = false
}
extension NuiteeRoomRate {
    var supplierMeals: HotelMealChoices {
        if let includedMeals { return includedMeals }
        let board = mealPlan.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if ["room only", "no meals", "without meals", "breakfast not included", "without breakfast", "no breakfast"].contains(where: { board.contains($0) }) { return HotelMealChoices() }
        let full = ["fb", "ai"].contains(board) || board.contains("full board") || board.contains("all inclusive")
        let half = board == "hb" || board.contains("half board")
        return HotelMealChoices(breakfast: full || half || board == "bb" || board.contains("breakfast"),
            lunch: full, dinner: full || half || board.contains("dinner"))
    }
}
