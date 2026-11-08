import SwiftUI

/// Per-component, on-device estimate. Server supplier secrets never enter the
/// app. A missing fare is an unknown amount (nil), not $0.
struct IumrahLocalComponentEstimate {
    let outbound: Double?
    let inbound: Double?
    let hotelTotal: Double?
    let transferUpgrade: Double
    let trainAddOn: Double
    let adults: Int
    let estimatedPackageTotal: Double?
    let includedServiceCost: Double?

    var flightTotal: Double? {
        guard let outbound, let inbound else { return nil }
        return (outbound + inbound) * Double(adults)
    }
    var selectedComponentsTotal: Double? {
        guard let flightTotal, let hotelTotal else { return nil }
        return flightTotal + hotelTotal + transferUpgrade + trainAddOn
    }

    @MainActor
    static func calculate(_ journey: JourneyStore) -> Self {
        // Data API fares are indicative PER ADULT. Their child/infant policy is
        // unavailable; do not invent passenger-specific fares or full totals.
        let adultsOnly = journey.trip.children == 0 && journey.trip.infants == 0
        let outbound = adultsOnly ? journey.stagedAviasalesOffers[.outbound]?.price : nil
        let inbound = adultsOnly ? journey.stagedAviasalesOffers[.inbound]?.price : nil
        let stays = NuiteeStaySelectionStore.shared.selections()
        let windows = TripStayPlanner.windows(for: journey.trip)
        var totalHotel: Double? = nil
        if journey.trip.rooms == 1, let makkah = stays["makkah"],
           matches(makkah, window: windows.makkah, adults: journey.trip.adults, city: "makkah"),
           makkah.totalUSD > 0 {
            if let medWindow = windows.madinah {
                if let med = stays["madinah"],
                   matches(med, window: medWindow, adults: journey.trip.adults, city: "madinah"), med.totalUSD > 0 {
                    totalHotel = makkah.totalUSD + med.totalUSD
                }
            } else {
                totalHotel = makkah.totalUSD
            }
        }
        let upgrade = NSDecimalNumber(decimal:
            (journey.selectedTransferVehicle ?? .carnival).publicUpgradeUsd(for: journey.trip.scope)).doubleValue
        let train = journey.haramainTrainSelected
            ? NSDecimalNumber(decimal: journey.haramainFareClass.publicSeatPriceUsd).doubleValue
                * Double(journey.trip.adults + journey.trip.children)
            : 0
        let validOutbound = outbound.flatMap { $0 > 0 ? $0 : nil }
        let validInbound = inbound.flatMap { $0 > 0 ? $0 : nil }
        let guestCount = journey.trip.travelerCount
        let includedServices: Double
        let nights = TripStayPlanner.breakdown(for: journey.trip)
        let paidSeats = journey.trip.adults + journey.trip.children
        let visa = Double(guestCount) * 120
        let accompaniment = journey.trip.scope == .makkahAndMadinah ? 300.0 : 100.0
        let ziyarat = journey.trip.scope == .makkahAndMadinah ? 200.0 : 100.0
        let meals: Double
        if journey.trip.packageTier == .economy || journey.trip.packageTier == .standard {
            meals = 15 * Double(nights.totalDays) * Double(paidSeats)
        } else {
            let unit = journey.trip.packageTier == .comfort ? 30.0 : 50.0
            let chosen = journey.trip.effectiveMealSelection
            meals = unit * Double(paidSeats) * (
                Double((chosen.makkahLunch ? 1 : 0) + (chosen.makkahDinner ? 1 : 0)) * Double(nights.makkahNights)
                + (journey.trip.scope == .makkahAndMadinah && chosen.madinahDinner
                   ? Double(nights.madinahNights) : 0)
            )
        }
        includedServices = visa + meals + 300 + accompaniment + ziyarat
        let estimated: Double?
        if let validOutbound, let validInbound, let totalHotel, guestCount > 0 {
            // Port of the public-facing arithmetic of PackageEngine/src/pricing.ts,
            // using the ACTUAL selected per-adult Data API fares and entire-stay
            // Nuitee room totals. Does not create a trusted payable quote/proof.
            let flights = Double(journey.trip.adults) * (validOutbound + validInbound)
            let supplierInputs = flights + totalHotel + includedServices
            let markup = journey.trip.packageTier == .luxury ? 0.35 : 0.25
            let preFee = supplierInputs * (1 + markup)
            let beforeRounding = preFee / (1 - 0.02)
            let roundedPerTraveler = max(5, (beforeRounding / Double(guestCount) / 5).rounded() * 5)
            estimated = roundedPerTraveler * Double(guestCount) + upgrade + train
        } else {
            estimated = nil
        }
        return .init(outbound: validOutbound, inbound: validInbound,
                     hotelTotal: totalHotel, transferUpgrade: upgrade,
                     trainAddOn: train, adults: journey.trip.adults,
                     estimatedPackageTotal: estimated,
                     includedServiceCost: includedServices)
    }

    static func date(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    static func matches(_ stay: NuiteeSelectedStay, window: TripStayWindow, adults: Int,
                        city: String? = nil) -> Bool {
        let normalized = stay.city.lowercased()
        let isMed = normalized.contains("mad") || normalized.contains("med") || normalized.contains("المدينة")
        let cityMatches = city == nil || (city == "madinah" ? isMed : !isMed)
        return cityMatches && stay.provider == "nuitee" && stay.checkin == date(window.checkIn) &&
            stay.checkout == date(window.checkOut) && stay.adults == adults &&
            !stay.hotelId.isEmpty && !stay.offerId.isEmpty && !stay.roomId.isEmpty
    }
    static func price(_ amount: Double?) -> String {
        amount.map { NuiteeHotelService.usd($0) } ?? "—"
    }
}

/// Supplier rate refresh invalidates offers that disappeared; never silently
/// keep an old amount under the same room title.
@MainActor
final class IumrahNuiteePriceRevision: ObservableObject {
    @Published var loading = false
    @Published var warning: String?
    @Published var generation = 0
    private let service = NuiteeHotelService()

    func refresh(journey: JourneyStore) async {
        guard !loading else { return }
        loading = true
        defer { loading = false; generation += 1 }
        warning = nil
        let windows = TripStayPlanner.windows(for: journey.trip)
        let selected = NuiteeStaySelectionStore.shared.selections()
        for (key, window) in [("makkah", windows.makkah), ("madinah", windows.madinah)] {
            guard let window, let stay = selected[key],
                  IumrahLocalComponentEstimate.matches(stay, window: window, adults: journey.trip.adults, city: key) else { continue }
            do {
                let response = try await service.rates(hotelID: stay.hotelId,
                   checkin: window.checkIn, checkout: window.checkOut, adults: journey.trip.adults)
                guard let rate = response.rates.first(where: {
                    $0.offerId == stay.offerId && $0.roomId == stay.roomId &&
                    $0.currency.uppercased() == "USD" && $0.price > 0
                }) else {
                    NuiteeStaySelectionStore.shared.remove(city: key)
                    warning = "Выбранный тариф в \(stay.hotelName) больше недоступен. Выберите другой номер."
                    continue
                }
                NuiteeStaySelectionStore.shared.save(NuiteeSelectedStay(
                    provider: "nuitee", hotelId: stay.hotelId, hotelName: stay.hotelName,
                    city: stay.city, checkin: stay.checkin, checkout: stay.checkout,
                    adults: stay.adults, offerId: rate.offerId, roomId: rate.roomId,
                    roomName: rate.roomName, totalUSD: rate.price, mealPlan: rate.mealPlan,
                    cancellationTag: rate.cancellationTag, selectedAt: Date()
                ))
                if response.sandbox {
                    warning = "Nuitee sandbox: цены предварительные, онлайн-бронирование недоступно."
                }
            } catch {
                warning = "Не удалось перепроверить тариф Nuitee: \(error.localizedDescription)"
            }
        }
    }
}

/// Single supplier-backed hotel step for the new Flight First journey.
struct IumrahNuiteeJourneyHotelsView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var revision = IumrahNuiteePriceRevision()
    @State private var heroVisible = true
    @State private var cityIndex = 0
    @State private var refreshSignal = 0
    @State private var selected: [String: NuiteeSelectedStay] = [:]
    @State private var nextStep = false
    @State private var error: String?

    private var cityKeys: [String] {
        journey.trip.scope == .makkahOnly ? ["makkah"] :
          (journey.trip.arrivalAirport == .madinah ? ["madinah", "makkah"] : ["makkah", "madinah"])
    }
    private var cityKey: String { cityKeys[min(cityIndex, cityKeys.count - 1)] }
    private var cityTitle: String { cityKey == "makkah" ? "Мекка" : "Медина" }
    private var window: TripStayWindow {
        let dates = TripStayPlanner.windows(for: journey.trip)
        return cityKey == "makkah" ? dates.makkah : (dates.madinah ?? dates.makkah)
    }
    private var citySelected: Bool {
        guard let stay = selected[cityKey] else { return false }
        return IumrahLocalComponentEstimate.matches(stay, window: window, adults: journey.trip.adults, city: cityKey)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                IumrahJourneyHeader(showsNotifications: true) {
                    IumrahJourneyDisclosureCard(
                        title: "Отели · \(cityIndex + 1) из \(cityKeys.count)",
                        total: cityTitle,
                        subtitle: "\(window.checkIn.formatted(date: .abbreviated, time: .omitted)) – \(window.checkOut.formatted(date: .abbreviated, time: .omitted))",
                        priceCaption: "Nuitee"
                    ) {
                        Label("\(journey.trip.adults) взрослых · \(journey.trip.rooms) номер", systemImage: "person.2")
                        Text("Маршрут и даты соответствуют выбранным авиабилетам.").font(.footnote)
                    }
                }
                .background { GeometryReader { geometry in
                    Color.clear.preference(key: IumrahScrollingHeroBottomKey.self,
                        value: geometry.frame(in: .named("nuiteeHotelsScroll")).maxY)
                } }
                VStack(alignment: .leading, spacing: 18) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if let warning = revision.warning {
                        Label(warning, systemImage: "arrow.clockwise.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if journey.trip.rooms != 1 || journey.trip.children > 0 || journey.trip.infants > 0 {
                        Text("Текущий Nuitee V1 поддерживает один номер с взрослыми. Для семей с детьми или несколькими номерами необходим запрос с подтверждённым составом гостей.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    NuiteeHotelsCatalogView(
                        refreshSignal: refreshSignal,
                        guidedCity: cityKey,
                        guidedCheckin: window.checkIn,
                        guidedNights: window.nights,
                        guidedAdults: journey.trip.adults,
                        onStaySelected: { stay in
                            guard IumrahLocalComponentEstimate.matches(stay, window: window,
                                adults: journey.trip.adults, city: cityKey), stay.totalUSD > 0 else {
                                error = "Тариф не совпадает с датами вашей поездки. Измените параметры отеля."
                                return
                            }
                            selected[cityKey] = stay
                            error = nil
                        }
                    )
                    .id(cityKey)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 110)
            }
        }
        .coordinateSpace(name: "nuiteeHotelsScroll")
        .onPreferenceChange(IumrahScrollingHeroBottomKey.self) { bottom in
            heroVisible = bottom > 35
        }
        .background {
            (heroVisible ? Color.iumrahHeaderBackground : Color.iumrahPageBackground)
                .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button(cityIndex < cityKeys.count - 1 ? "Следующий город" : "Выбрать трансфер") {
                if cityIndex < cityKeys.count - 1 { cityIndex += 1 }
                else { nextStep = true }
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
            .disabled(!citySelected || journey.trip.rooms != 1 ||
                      journey.trip.children > 0 || journey.trip.infants > 0)
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationDestination(isPresented: $nextStep) { IumrahNuiteeJourneyTransferView() }
        .refreshable {
            await revision.refresh(journey: journey)
            selected = NuiteeStaySelectionStore.shared.selections()
            refreshSignal += 1
        }
        .onAppear { selected = NuiteeStaySelectionStore.shared.selections() }
    }
}

struct IumrahNuiteeJourneyTransferView: View {
    @EnvironmentObject private var journey: JourneyStore
    @StateObject private var revision = IumrahNuiteePriceRevision()
    @State private var heroVisible = true
    @State private var showReview = false
    private var estimate: IumrahLocalComponentEstimate {
        _ = revision.generation
        return IumrahLocalComponentEstimate.calculate(journey)
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                IumrahJourneyHeader(showsNotifications: true) {
                    IumrahJourneyDisclosureCard(title: "Ваша поездка",
                        total: IumrahLocalComponentEstimate.price(estimate.estimatedPackageTotal),
                        subtitle: "\(journey.trip.travelerCount) чел. · \(journey.trip.departureDate.formatted(date: .abbreviated, time: .omitted)) – \(journey.trip.returnDate.formatted(date: .abbreviated, time: .omitted))",
                        priceCaption: "Оценка пакета") {
                        IumrahTransferRouteDetails()
                    }
                }
                .background { GeometryReader { geometry in
                    Color.clear.preference(key: IumrahScrollingHeroBottomKey.self,
                        value: geometry.frame(in: .named("nuiteeTransferScroll")).maxY)
                } }
                VStack(alignment: .leading, spacing: 20) {
                    Text("Трансфер").font(.title2.bold())
                    ForEach(TransferVehicleKind.allCases) { vehicle in
                        Button {
                            journey.selectedTransferVehicle = vehicle
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: vehicle == .yukon ? "car.side" : "car.side")
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(vehicle.modelName).font(.headline)
                                    Text("До \(vehicle.passengerCapacity) пассажиров")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if vehicle == .yukon && journey.trip.scope == .makkahAndMadinah {
                                    Text("+$750").font(.subheadline.weight(.semibold))
                                }
                                Image(systemName: (journey.selectedTransferVehicle ?? .carnival) == vehicle
                                      ? "checkmark.circle.fill" : "circle")
                            }
                            .foregroundStyle(Color.iumrahInk)
                            .padding(18)
                            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                    }
                    if journey.trip.scope == .makkahAndMadinah {
                        Toggle("Haramain · добавить поезд", isOn: $journey.haramainTrainSelected)
                            .tint(Color(red: 0.24, green: 0.54, blue: 0.40))
                        if journey.haramainTrainSelected {
                            Picker("Класс поезда", selection: $journey.haramainFareClass) {
                                Text("Эконом").tag(HaramainFareClass.economy)
                                Text("Бизнес").tag(HaramainFareClass.business)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Text("Тариф трансфера в базовом пакете и остальные услуги будут подтверждены отдельно. Здесь показаны только известные цены и доплаты.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let warning = revision.warning { Text(warning).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(20).padding(.bottom, 80)
            }
        }
        .coordinateSpace(name: "nuiteeTransferScroll")
        .onPreferenceChange(IumrahScrollingHeroBottomKey.self) { bottom in
            heroVisible = bottom > 35
        }
        .background {
            (heroVisible ? Color.iumrahHeaderBackground : Color.iumrahPageBackground)
                .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button("К итогам поездки") { showReview = true }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationDestination(isPresented: $showReview) { IumrahNuiteeJourneyReviewView() }
        .refreshable { await revision.refresh(journey: journey) }
    }
}

struct IumrahNuiteeJourneyReviewView: View {
    @EnvironmentObject private var journey: JourneyStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var revision = IumrahNuiteePriceRevision()
    @State private var heroVisible = true
    private var estimate: IumrahLocalComponentEstimate {
        _ = revision.generation
        return IumrahLocalComponentEstimate.calculate(journey)
    }
    private var stays: [String: NuiteeSelectedStay] {
        _ = revision.generation
        return NuiteeStaySelectionStore.shared.selections()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                IumrahJourneyHeader(showsNotifications: true) {
                    IumrahJourneyDisclosureCard(title: "Итог поездки",
                        total: IumrahLocalComponentEstimate.price(estimate.estimatedPackageTotal),
                        subtitle: "Авиабилеты · Nuitee отели · Трансфер",
                        priceCaption: "Предварительно") {
                        IumrahTransferRouteDetails()
                    }
                }
                .background { GeometryReader { geometry in
                    Color.clear.preference(key: IumrahScrollingHeroBottomKey.self,
                        value: geometry.frame(in: .named("nuiteeReviewScroll")).maxY)
                } }
                VStack(alignment: .leading, spacing: 18) {
                    Text("Выбранные компоненты").font(.title2.bold())
                    priceRow("Перелёт туда", estimate.outbound.map { $0 * Double(estimate.adults) })
                    priceRow("Обратный перелёт", estimate.inbound.map { $0 * Double(estimate.adults) })
                    let windows = TripStayPlanner.windows(for: journey.trip)
                    if let stay = stays["makkah"],
                       IumrahLocalComponentEstimate.matches(stay, window: windows.makkah, adults: journey.trip.adults, city: "makkah") {
                        priceRow(stay.hotelName + " · " + stay.roomName, stay.totalUSD)
                    }
                    if let medWindow = windows.madinah, let stay = stays["madinah"],
                       IumrahLocalComponentEstimate.matches(stay, window: medWindow, adults: journey.trip.adults, city: "madinah") {
                        priceRow(stay.hotelName + " · " + stay.roomName, stay.totalUSD)
                    }
                    priceRow("Виза · сопровождение · базовый трансфер · зияраты · питание",
                             estimate.includedServiceCost)
                    priceRow("Повышение класса трансфера", estimate.transferUpgrade)
                    if journey.haramainTrainSelected { priceRow("Haramain", estimate.trainAddOn) }
                    Divider()
                    HStack {
                        Text("Оценка стоимости пакета").font(.headline)
                        Spacer()
                        Text(IumrahLocalComponentEstimate.price(estimate.estimatedPackageTotal))
                            .font(.title3.weight(.bold)).monospacedDigit()
                    }
                    Text("Локальный расчёт включает сервисные компоненты, наценку, округление и платёжную комиссию по действующей формуле iumrah. Это НЕ подтверждённая цена и не оферта: тарифы Data API предварительные, Nuitee требует повторной проверки, а наличие услуг и возможные сборы уточняются до оплаты. Бронирование и оплата на этом шаге недоступны.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let warning = revision.warning {
                        Label(warning, systemImage: "exclamationmark.circle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                .padding(20).padding(.bottom, 90)
            }
        }
        .coordinateSpace(name: "nuiteeReviewScroll")
        .onPreferenceChange(IumrahScrollingHeroBottomKey.self) { bottom in
            heroVisible = bottom > 35
        }
        .background {
            (heroVisible ? Color.iumrahHeaderBackground : Color.iumrahPageBackground)
                .ignoresSafeArea(edges: .top)
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            Button("Изменить трансфер") { dismiss() }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .refreshable { await revision.refresh(journey: journey) }
    }
    private func priceRow(_ title: String, _ price: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.subheadline)
            Spacer(minLength: 2)
            Text(IumrahLocalComponentEstimate.price(price))
                .font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }
}
