import SwiftUI

/// Review of the selected journey. The Flight First card kit is shared with the
/// storefront; quote verification and booking still belong to the existing stores.
struct FinalPackageView: View {
    var familyFlow = false
    @EnvironmentObject private var journey: JourneyStore
    var body: some View {
        if journey.usesLocalJourney { LocalJourneyReviewView() }
        else { LegacyFinalPackageView(familyFlow: familyFlow) }
    }
}

struct LegacyFinalPackageView: View {
    var familyFlow = false
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var push = PushNotificationManager.shared
    @State private var isProfileSheetPresented = false
    @State private var isSubmitting = false
    @State private var isCalculatingPrice = false
    @State private var createdSession: StoredBookingSession?
    @State private var showCreatedBooking = false
    @State private var pendingBookingSession: StoredBookingSession?
    @State private var errorMessage: String?
    @State private var infoSheet: StorefrontPackageInfoSheet?
    @State private var showTransferDetails = false
    @State private var showTransferSelection = false
    @State private var localHotelForDetails: LocalJourneyRoom?
    @State private var hotelForDetails: HotelSummary?

    private var needsMadinah: Bool { journey.trip.scope == .makkahAndMadinah }
    private var roomsComplete: Bool {
        if journey.usesLocalJourney { return journey.localRoomsComplete }
        return (journey.selectedRoom != nil || journey.selectedRoomCategory != nil) &&
        (!needsMadinah || journey.selectedMadinahRoom != nil || journey.selectedMadinahRoomCategory != nil)
    }
    private var canBook: Bool {
        journey.hasFinalGeneratorQuote && journey.quote?.bookingAllowed != false && !isCalculatingPrice &&
        journey.transferSelectionConfirmed && roomsComplete &&
        journey.selectedHotel != nil &&
        journey.selectedOutbound?.isVerifiedForBooking == true &&
        (!journey.trip.isRoundTripFlight || journey.selectedInbound?.isVerifiedForBooking == true) &&
        (!needsMadinah || journey.selectedMadinahHotel != nil)
    }
    private var quoteInputKey: String {
        if journey.usesLocalJourney { return journey.localBookingInputKey }
        return [journey.selectedHotel?.id ?? "", journey.selectedMadinahHotel?.id ?? "",
         journey.selectedRoom?.id ?? "", journey.selectedMadinahRoom?.id ?? "",
         journey.selectedRoomCategory?.displayName ?? "", journey.selectedMadinahRoomCategory?.displayName ?? "",
         String(journey.trip.hashValue), journey.selectedTransferVehicle?.rawValue ?? "",
         String(journey.haramainTrainSelected), String(journey.haramainTicketCount),
         journey.haramainFareClass.rawValue].joined(separator: "|")
    }
    private var totalText: String {
        guard journey.hasFinalGeneratorQuote, !isCalculatingPrice, let quote = journey.quote else {
            return isCalculatingPrice ? tr("Расчёт…", "Calculating…", "Hisoblanmoqda…", "Ҳисобланмоқда…") : "—"
        }
        return money(quote.totalPackagePrice, quote.currency)
    }
    private var partyText: String {
        tr("\(journey.trip.adults) взр. · \(journey.trip.children) дет. · \(journey.trip.infants) млад. · \(journey.trip.rooms) ном.",
           "\(journey.trip.adults) adults · \(journey.trip.children) children · \(journey.trip.infants) infants · \(journey.trip.rooms) rooms",
           "\(journey.trip.adults) katta · \(journey.trip.children) bola · \(journey.trip.infants) chaqaloq · \(journey.trip.rooms) xona",
           "\(journey.trip.adults) катта · \(journey.trip.children) бола · \(journey.trip.infants) чақалоқ · \(journey.trip.rooms) хона")
    }

    var body: some View {
        Group {
            if let createdSession {
                IumrahBookingCelebrationView(session: createdSession,
                    onOpenBooking: { showCreatedBooking = true },
                    onHome: {
                        chrome.shouldStartTripBuilder = false
                        journey.resetAfterTripChange()
                        chrome.navigate(to: .home)
                    })
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        IumrahJourneyHeader(showsNotifications: true) { packageSummary }
                        VStack(alignment: .leading, spacing: 18) {
                            IumrahPageHelpCard(journey.hasFinalGeneratorQuote ? "legacy.final" : "legacy.recalculate")
                            if !journey.hasFinalGeneratorQuote { pricingStatus }
                            Text(tr("Авиабилеты", "Flights", "Aviachiptalar", "Авиачипталар")).font(.title2.bold())
                            if let outbound = journey.selectedOutbound {
                                PackageFlightLegDetailCard(leg: flightLeg(outbound), direction: tr("Туда", "Outbound", "Borish", "Бориш"), language: settings.language)
                            }
                            if journey.trip.isRoundTripFlight, let inbound = journey.selectedInbound {
                                PackageFlightLegDetailCard(leg: flightLeg(inbound), direction: tr("Обратно", "Return", "Qaytish", "Қайтиш"), language: settings.language)
                            }
                            Text(tr("Отели и номера", "Hotels and rooms", "Mehmonxonalar va xonalar", "Меҳмонхоналар ва хоналар")).font(.title2.bold())
                            if journey.usesLocalJourney {
                                ForEach(journey.localJourneyRooms.values.sorted { $0.checkin == $1.checkin ? $0.id < $1.id : $0.checkin < $1.checkin }) { room in
                                    localHotelCard(room)
                                }
                            } else {
                                if let hotel = journey.selectedHotel { hotelCard(hotel, role: .makkah) }
                                if needsMadinah, let hotel = journey.selectedMadinahHotel { hotelCard(hotel, role: .madinah) }
                            }
                            Text(tr("В вашем пакете", "Your package includes", "Paketingizga kiradi", "Пакетингизга киради")).font(.title2.bold())
                            serviceKit
                            servicesList
                            IumrahRefundPolicyCard(component: .package, compact: false)
                            PackagePurchaseTrustCard(language: settings.language) { infoSheet = .trust }
                            IumrahManualPaymentNotice()
                            if let errorMessage {
                                Text(errorMessage).font(.footnote).foregroundStyle(.red)
                            }
                        }
                        .padding(IumrahDesign.pagePadding)
                        .padding(.bottom, 20)
                    }
                    .background(IumrahNoVerticalBounce())
                }
                .modifier(IumrahJourneyRefresh { await recalculatePrice() })
                .background(Color.iumrahPageBackground)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if createdSession == nil { bookingBar }
        }
        .task(id: quoteInputKey) {
            guard createdSession == nil else { return }
            if !journey.hasFinalGeneratorQuote || journey.quote?.bookingAllowed == false { await recalculatePrice() }
        }
        .task { await push.refreshAndRegisterIfAllowed() }
        .navigationDestination(isPresented: $isProfileSheetPresented) {
            IumrahBookingConfirmationView(createBooking: { profile in
                try await createBooking(profile: profile)
            }).environmentObject(settings)
        }
        .navigationDestination(isPresented: $showCreatedBooking) {
            if let createdSession { BookingDetailView(bookingID: createdSession.id) }
        }
        .navigationDestination(isPresented: $showTransferSelection) { TransferSelectionView(familyFlow: familyFlow) }
        .navigationDestination(item: $hotelForDetails) { hotel in
            HotelDetailView(hotel: hotel, selectionFlow: true,
                selectionRole: hotel.id == journey.selectedMadinahHotel?.id ? .madinah : .makkah)
        }
        .sheet(item: $localHotelForDetails) { room in
            NavigationStack {
                NuiteeHotelDetailView(hotel: room.hotel, checkin: room.checkin,
                    nights: TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights,
                    adults: room.adults, sandbox: journey.quote?.bookingAllowed == false,
                    childrenAges: room.childrenAges, onSelectRate: { rate in
                        journey.localJourneyRooms[room.id] = LocalJourneyRoom(id: room.id, city: room.city,
                            hotel: room.hotel, rate: rate, checkin: room.checkin, checkout: room.checkout,
                            adults: room.adults, childrenAges: room.childrenAges,
                            meals: journey.localJourneyRooms[room.id]?.meals)
                        journey.quote = nil
                        localHotelForDetails = nil
                    }, onSelectMeals: { meals in
                        journey.localJourneyRooms[room.id]?.meals = meals
                    }, selectedMeals: room.meals ?? HotelMealChoices())
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button(tr("Закрыть", "Close", "Yopish", "Ёпиш")) { localHotelForDetails = nil }
                    } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $infoSheet) { kind in
            StorefrontPackageInformationSheet(kind: kind, language: settings.language)
                .modifier(IumrahJourneySheetStyle())
        }
        .sheet(isPresented: $showTransferDetails) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let vehicle = journey.selectedTransferVehicle {
                            Image(vehicle.assetName).resizable().scaledToFit().frame(height: 180)
                            Text(vehicle.modelName).font(.title2.bold())
                        }
                        IumrahTransferRouteDetails()
                        IumrahRefundPolicyCard(component: .transfer, compact: false)
                    }.padding(18)
                }
                .background(Color.iumrahPageBackground)
                .navigationTitle(tr("Трансфер", "Transfer", "Transfer", "Трансфер"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("Готово", "Done", "Tayyor", "Тайёр")) { showTransferDetails = false }
                } }
            }.modifier(IumrahJourneySheetStyle())
        }
    }

    private var packageSummary: some View {
        IumrahJourneyDisclosureCard(
            title: tr("Ваша умра", "Your Umrah", "Sizning Umrangiz", "Сизнинг Умрангиз"),
            total: totalText, subtitle: partyText,
            priceCaption: tr("Итого за всех", "Total for everyone", "Hamma uchun jami", "Ҳамма учун жами")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(journey.trip.packageTier.title(settings.language)).font(.headline)
                Label(journey.trip.scope.title(settings.language), systemImage: "map")
                Label(dateRange(journey.trip.departureDate, journey.trip.returnDate), systemImage: "calendar")
                if let outbound = journey.selectedOutbound {
                    Label(outbound.origin + " → " + outbound.destination + " · " + outbound.flightNumbersSummary, systemImage: "airplane.departure")
                }
                if let inbound = journey.selectedInbound, journey.trip.isRoundTripFlight {
                    Label(inbound.origin + " → " + inbound.destination + " · " + inbound.flightNumbersSummary, systemImage: "airplane.arrival")
                }
                if let hotel = journey.selectedHotel {
                    Label(hotel.name + " · " + roomName(.makkah), systemImage: "bed.double")
                }
                if needsMadinah, let hotel = journey.selectedMadinahHotel {
                    Label(hotel.name + " · " + roomName(.madinah), systemImage: "bed.double")
                }
                if let vehicle = journey.selectedTransferVehicle { Label(vehicle.modelName, systemImage: "car.side") }
                if needsMadinah && journey.haramainTrainSelected { Label(trainText, systemImage: "tram") }
                if let quote = journey.quote, journey.hasFinalGeneratorQuote, !isCalculatingPrice {
                    Divider()
                    Text(money(quote.pricePerPerson, quote.currency) + " · " + tr("на человека", "per traveler", "kishi uchun", "киши учун"))
                        .font(.subheadline.weight(.semibold))
                }
            }
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hotelCard(_ hotel: HotelSummary, role: HotelSelectionRole) -> some View {
        let windows = TripStayPlanner.windows(for: journey.trip)
        let window = role == .makkah ? windows.makkah : windows.madinah ?? windows.makkah
        return VStack(alignment: .leading, spacing: 8) {
            Label(dateRange(window.checkIn, window.checkOut), systemImage: "calendar")
                .font(.caption).foregroundStyle(.secondary)
            PackageHotelDetailCard(
                hotel: StorefrontPackageHotel(id: hotel.id, name: hotel.name, city: hotel.city,
                    stars: hotel.stars, coverImageURL: hotel.coverImageURL, nights: window.nights),
                selectedRoomName: roomName(role), chooseRoomText: chooseRoomTitle,
                language: settings.language, onOpen: { hotelForDetails = hotel })
        }
    }
    private var chooseRoomTitle: String { tr("Выбрать номер", "Choose room", "Xona tanlash", "Хона танлаш") }
    private func roomName(_ role: HotelSelectionRole) -> String {
        if role == .makkah { return journey.selectedRoom?.name ?? journey.selectedRoomCategory?.displayName ?? chooseRoomTitle }
        return journey.selectedMadinahRoom?.name ?? journey.selectedMadinahRoomCategory?.displayName ?? chooseRoomTitle
    }

    private func localHotelCard(_ room: LocalJourneyRoom) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: room.hotel.coverImageURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFill()
                } placeholder: { Color.secondary.opacity(0.12) }
                .frame(width: 86, height: 100).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) {
                    Text(room.hotel.name).font(.headline)
                    Text(String(repeating: "★", count: max(0, min(5, room.hotel.roundedStars))) + " · " + L10n.city(room.city == "madinah" ? "Madinah" : "Makkah", settings.language))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(room.rate.roomName).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            IumrahHotelStaySummary(checkin: room.checkin, checkout: room.checkout,
                nights: TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights)
            Button(tr("Изменить номер", "Change room", "Xonani o‘zgartirish", "Хонани ўзгартириш")) { localHotelForDetails = room }
                .buttonStyle(IumrahSecondaryButtonStyle())
            Divider()
            IumrahHotelMealsEditor(selection: Binding(
                get: { journey.localJourneyRooms[room.id]?.meals ?? HotelMealChoices() },
                set: { value in
                    journey.localJourneyRooms[room.id]?.meals = value
                    journey.invalidateLocalJourneyQuote()
                }), stars: room.hotel.roundedStars, city: room.city, included: room.rate.supplierMeals)
        }
        .padding(18)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28))
    }
    private var bookingBlockedReason: String? {
        if isCalculatingPrice { return tr("Обновляем стоимость…", "Updating price…", "Narx yangilanmoqda…", "Нарх янгиланмоқда…") }
        if !roomsComplete { return chooseRoomTitle }
        if !journey.hasFinalGeneratorQuote || journey.quote?.bookingAllowed == false {
            return tr("Для продолжения обновите расчёт поездки.", "Refresh the trip price to continue.", "Davom etish uchun safar narxini yangilang.", "Давом этиш учун сафар нархини янгиланг.")
        }
        if !journey.transferSelectionConfirmed { return tr("Подтвердите выбранный трансфер.", "Confirm your transfer.", "Transferni tasdiqlang.", "Трансферни тасдиқланг.") }
        if !canBook { return tr("Проверьте выбранные рейсы и отели перед бронированием.", "Review your flights and hotels before booking.", "Bron qilishdan oldin reyslar va mehmonxonalarni tekshiring.", "Брон қилишдан олдин рейслар ва меҳмонхоналарни текширинг.") }
        return nil
    }

    private var serviceKit: some View {
        VStack(spacing: 0) { serviceTiles }
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }
    @ViewBuilder private var serviceTiles: some View {
        serviceTile("iumrah Guide", icon: "person.crop.circle.badge.checkmark", role: .care) { infoSheet = .guide }
        serviceTile("iumrah Care", icon: "heart", role: .care) { infoSheet = .care }
        serviceTile("iumrah Transfer", icon: "car.side", role: .transfer) { showTransferDetails = true }
    }
    private func serviceTile(_ title: String, icon: String, role: IumrahIconRole, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IumrahIconBadge(systemName: icon, role: role, size: 36, symbolSize: 16, cornerRadius: 11)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.iumrahInk)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var servicesList: some View {
        VStack(spacing: 0) {
            Button { infoSheet = .visa } label: {
                serviceRow(tr("Виза", "Visa", "Viza", "Виза"), icon: "doc.text", detail: tr("Подробнее", "Details", "Batafsil", "Батафсил"))
            }.buttonStyle(.plain)
            Divider()
            serviceRow(tr("Питание", "Meals", "Ovqatlanish", "Овқатланиш"), icon: "fork.knife", detail: mealsText)
            Divider()
            serviceRow(tr("Зияраты в Мекке", "Makkah ziyarat", "Makka ziyoratlari", "Макка зиёратлари"), icon: "mappin.and.ellipse", detail: ziyaratDetail)
            if needsMadinah {
                Divider()
                serviceRow(tr("Зияраты в Медине", "Madinah ziyarat", "Madina ziyoratlari", "Мадина зиёратлари"), icon: "mappin.and.ellipse", detail: ziyaratDetail)
            }
            if needsMadinah && journey.haramainTrainSelected {
                Divider()
                serviceRow("Haramain", icon: "tram", detail: trainText)
            }
            Divider()
            serviceRow("iumrah Mobile eSIM", icon: "simcard", detail: FlowCopy.text(.included, settings.language))
        }
        .padding(.horizontal, 16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }
    private func serviceRow(_ title: String, icon: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Color.iumrahJourneyGreen)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 14).foregroundStyle(Color.iumrahInk)
    }
    private var ziyaratDetail: String {
        let included = FlowCopy.text(.included, settings.language)
        return journey.trip.packageTier == .economy || journey.trip.packageTier == .standard ? included + " · $0" : included
    }
    private var trainText: String {
        "\(journey.haramainTicketCount) · " + (journey.haramainFareClass == .business ? tr("Бизнес", "Business", "Biznes", "Бизнес") : tr("Стандарт", "Standard", "Standart", "Стандарт"))
    }
    private var mealsText: String {
        let makkah = mealCount(.makkah)
        let madinah = mealCount(.madinah)
        let unit = tr("приёмов пищи/день", "meals/day", "mahal/kun", "маҳал/кун")
        let first = L10n.city("Makkah", settings.language) + " · \(makkah) " + unit
        return needsMadinah ? first + "\n" + L10n.city("Madinah", settings.language) + " · \(madinah) " + unit : first
    }
    private func mealCount(_ city: HotelMealCity) -> Int {
        if journey.usesLocalJourney, let room = journey.localJourneyRooms.values.first(where: { $0.city == city.rawValue }) {
            let included = room.rate.supplierMeals
            let selected = room.meals ?? HotelMealChoices()
            return [included.breakfast || room.hotel.roundedStars >= 4 || selected.breakfast,
                city == .makkah && (included.lunch || selected.lunch), included.dinner || selected.dinner].filter { $0 }.count
        }
        return [HotelMealKind.breakfast, .lunch, .dinner].filter { journey.isMealEnabled($0, city: city) }.count
    }

    private var pricingStatus: some View {
        HStack(spacing: 12) {
            if isCalculatingPrice { ProgressView() }
            Text(isCalculatingPrice
                 ? tr("Обновляем стоимость выбранной поездки…", "Updating your trip price…", "Safar narxi yangilanmoqda…", "Сафар нархи янгиланмоқда…")
                 : tr("Стоимость пока не подтверждена. Повторите расчёт.", "The price is not confirmed yet. Retry pricing.", "Narx hali tasdiqlanmagan. Qayta hisoblang.", "Нарх ҳали тасдиқланмаган. Қайта ҳисобланг."))
                .font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).iumrahCard()
    }
    private var bookingBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(tr("Итого за всех", "Total for everyone", "Hamma uchun jami", "Ҳамма учун жами")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(totalText).font(.title3.bold()).monospacedDigit()
            }
            if let reason = bookingBlockedReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            if !journey.transferSelectionConfirmed {
                Button(tr("Подтвердить трансфер", "Confirm transfer", "Transferni tasdiqlash", "Трансферни тасдиқлаш")) {
                    showTransferSelection = true
                }.buttonStyle(IumrahPrimaryButtonStyle())
            } else if journey.hasFinalGeneratorQuote && journey.quote?.bookingAllowed != false {
                Button {
                    guard canBook else { return }
                    isProfileSheetPresented = true
                } label: {
                    HStack {
                        Text(tr("Забронировать поездку", "Book this trip", "Safarni bron qilish", "Сафарни брон қилиш"))
                    }.frame(minHeight: 52)
                }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .disabled(!canBook || isSubmitting)
                .opacity(canBook && !isSubmitting ? 1 : 0.45)
            } else {
                Button(tr("Повторить расчёт", "Retry pricing", "Qayta hisoblash", "Қайта ҳисоблаш")) {
                    Task { await recalculatePrice() }
                }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(isCalculatingPrice)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(.regularMaterial)
    }
    @MainActor private func recalculatePrice() async {
        let trace = IumrahPerformanceTrace.begin("Final package quote")
        defer { IumrahPerformanceTrace.end("Final package quote", trace) }
        guard !isCalculatingPrice else { return }
        isCalculatingPrice = true
        defer { isCalculatingPrice = false }
        await journey.buildQuote(forceHotelRefresh: false)
        guard !Task.isCancelled else { return }
        errorMessage = journey.hasFinalGeneratorQuote ? nil : journey.errorMessage.map { ConfiguratorBookingCopy.message($0, language: settings.language) }
    }
    private func flightLeg(_ offer: FlightOffer) -> StorefrontFlightLeg {
        let formatter = ISO8601DateFormatter()
        return StorefrontFlightLeg(airline: offer.airlinesSummary, flightNumber: offer.flightNumbersSummary,
            airlineCode: offer.primaryAirlineCode ?? "", origin: offer.origin, destination: offer.destination,
            departureAt: formatter.string(from: offer.departureAt), arrivalAt: formatter.string(from: offer.arrivalAt),
            durationMinutes: offer.durationMinutes, stops: offer.stops,
            cabinClass: offer.cabinClass ?? journey.trip.effectiveFlightFilters.cabinClass.rawValue)
    }
    private func dateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }
    private func money(_ amount: Decimal, _ currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(currency) \(amount)"
    }
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        default: return en
        }
    }
    @MainActor
    private func createBooking(profile: BookingPilgrimProfile) async throws -> StoredBookingSession {
        if let pendingBookingSession { return pendingBookingSession }
        guard !isSubmitting, canBook,
              let hotel = journey.selectedHotel,
              let outbound = journey.selectedOutbound,
              var quote = journey.quote else { throw BookingStoreError.authoritativeQuoteRequired }
        let inbound = journey.selectedInbound
        guard outbound.isVerifiedForBooking,
              (!journey.trip.isRoundTripFlight || inbound?.isVerifiedForBooking == true) else {
            errorMessage = tr("Выберите актуальные авиабилеты", "Select current flights", "Joriy reyslarni tanlang", "Жорий рейсларни танланг")
            IumrahHaptics.error()
            throw BookingStoreError.authoritativeQuoteRequired
        }
        if needsMadinah && journey.selectedMadinahHotel == nil {
            throw BookingStoreError.authoritativeQuoteRequired
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            if journey.usesLocalJourney {
                let acceptedTotal = quote.totalPackagePrice
                let acceptedInput = journey.localBookingInputKey
                await journey.buildQuote()
                guard let fresh = journey.quote, journey.hasFinalGeneratorQuote,
                      fresh.bookingAllowed == true, acceptedInput == journey.localBookingInputKey else {
                    throw BookingStoreError.authoritativeQuoteRequired
                }
                guard fresh.totalPackagePrice == acceptedTotal else {
                    throw ConfiguratorBookingError.priceChanged(tr("Цена изменилась. Вернитесь к итогу поездки и проверьте новую сумму.", "The price changed. Return to the trip review and check the new total.", "Narx o‘zgardi. Safar yakuniga qaytib, yangi summani tekshiring.", "Нарх ўзгарди. Сафар якунига қайтиб, янги суммани текширинг."))
                }
                quote = fresh
            }
            let session = try await bookings.create(
                trip: journey.trip,
                hotel: hotel,
                madinahHotel: journey.selectedMadinahHotel,
                room: journey.selectedRoom,
                roomCategory: journey.selectedRoomCategory,
                madinahRoom: journey.selectedMadinahRoom,
                madinahRoomCategory: journey.selectedMadinahRoomCategory,
                intercityTransport: needsMadinah ? (journey.haramainTrainSelected ? .haramainTrain : .road) : nil,
                transferVehicle: journey.selectedTransferVehicle ?? journey.recommendedTransferVehicle(),
                outbound: outbound,
                inbound: inbound,
                quote: quote,
                language: settings.language,
                pilgrimProfile: profile,
                nuiteeRooms: journey.usesLocalJourney ? journey.localBookingRooms : nil
            )
            pendingBookingSession = session
            if let deviceToken = push.deviceToken {
                await bookings.syncPushSubscriptions(deviceToken: deviceToken, locale: settings.language.rawValue)
            }
            IumrahHaptics.success()
            return session
        } catch {
            errorMessage = L10n.error(error, settings.language)
            IumrahHaptics.error()
            throw error
        }
    }

}

private enum ConfiguratorBookingError: LocalizedError {
    case priceChanged(String)
    var errorDescription: String? { if case .priceChanged(let message) = self { return message }; return nil }
}
