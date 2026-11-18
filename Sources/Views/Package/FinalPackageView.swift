import SwiftUI
import UIKit

/// Review of the selected journey. The Flight First card kit is shared with the
/// storefront; quote verification and booking still belong to the existing stores.
struct FinalPackageView: View {
    var familyFlow = false
    var restoration: SavedPackageEntry? = nil
    @EnvironmentObject private var journey: JourneyStore
    var body: some View {
        LegacyFinalPackageView(familyFlow: familyFlow, restoration: restoration)
    }
}

struct LegacyFinalPackageView: View {
    var familyFlow = false
    var restoration: SavedPackageEntry? = nil
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
    @State private var expandedSummary: Set<String> = []
    @State private var daySelection: String?
    @State private var editSession: TripSummaryEditSession?
    @State private var approvedRoomRequest: PackageThread.RoomRequest?
    @State private var guestDraft: TripSummaryGuestDraft?
    @State private var adultExceptionRequested = false
    @State private var quoteGeneration = UUID()
    @State private var previousTotal: Decimal?
    @State private var acceptedChangeTotal: Decimal?
    @State private var savingPackage = false
    @State private var savedPackage: TripSummarySavedReceipt?
    @State private var savedQuoteID: String?
    @State private var showPackageSupport = false
    @State private var showSharePreview = false
    @State private var shareImageURL: URL?
    @State private var ownerCredential: TripSummaryOwnerCredential?

    private var needsMadinah: Bool { journey.trip.scope == .makkahAndMadinah }
    private var roomsComplete: Bool {
        if journey.usesLocalJourney { return journey.localRoomsComplete }
        let occupancy = (journey.trip.travelerCount + max(1, journey.trip.rooms) - 1) / max(1, journey.trip.rooms)
        func fits(_ room: HotelRoom?, _ category: IumrahRoomCategoryOption?) -> Bool {
            guard room != nil || category != nil else { return false }
            if let capacity = room?.maxGuests ?? category?.maxGuests { return capacity >= occupancy }
            return true // Unknown capacity remains subject to supplier verification.
        }
        return fits(journey.selectedRoom, journey.selectedRoomCategory) &&
        (!needsMadinah || fits(journey.selectedMadinahRoom, journey.selectedMadinahRoomCategory))
    }
    private var canBook: Bool {
        journey.hasFinalGeneratorQuote && journey.quote?.bookingAllowed != false && !isCalculatingPrice && guestDraft == nil && !adultExceptionRequested && priceChangeAccepted && (journey.trip.adults <= journey.trip.rooms * 5 || journey.quote?.roomPolicy?.requiresAdultException == false) &&
        journey.transferSelectionConfirmed && (journey.selectedTransferVehicle?.passengerCapacity ?? 0) >= journey.trip.travelerCount && roomsComplete &&
        journey.selectedHotel != nil &&
        flightSelectionReady &&
        (!needsMadinah || journey.selectedMadinahHotel != nil)
    }
    private var flightSelectionReady: Bool {
        FinalPackageFlightGate.ready(outbound: journey.selectedOutbound,
            inbound: journey.selectedInbound, roundTrip: journey.trip.isRoundTripFlight,
            usesLocalJourney: journey.usesLocalJourney, mixedIdentity: journey.mixedFlightIdentity,
            localFlightIDs: journey.localJourneyFlights.map(\.id), quote: journey.quote)
    }
    private var quoteInputKey: String {
        if journey.usesLocalJourney { return journey.localBookingInputKey + "|review:\(journey.tripSummaryRevision)" }
        return [String(journey.tripSummaryRevision), journey.selectedOutbound?.id ?? "", journey.selectedInbound?.id ?? "", journey.selectedHotel?.id ?? "", journey.selectedMadinahHotel?.id ?? "",
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
        return IumrahPackageDisplayPrices.money(quote.totalPackagePrice, currency: quote.currency, language: settings.language)
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
                    onOpenBooking: { chrome.shouldStartTripBuilder = false; chrome.shouldStartFlightFirstBuilder = false; chrome.openBooking(id: createdSession.id) },
                    onHome: {
                        chrome.shouldStartTripBuilder = false
                        journey.resetAfterTripChange()
                        chrome.navigate(to: .home)
                    })
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        IumrahJourneyHeader(showsNotifications: true) { summaryHero }
                        VStack(alignment: .leading, spacing: 16) {
                            guestCard
                            if !journey.hasFinalGeneratorQuote { pricingStatus }
                            if let previousTotal, let quote = journey.quote, previousTotal != quote.totalPackagePrice, !priceChangeAccepted {
                                priceChangeCard(previousTotal, quote: quote)
                            }
                            compactFlights
                            compactHotels
                            compactServices
                            supportCard
                            priceBreakdownCard
                            itineraryCard
                            conditionsCard
                            summaryTotalCard
                            summaryActions
                            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
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
            if createdSession == nil { compactBookingBar }
        }
        .onAppear {
            if savedPackage == nil, let restoration {
                savedPackage = restoration.receipt; ownerCredential = restoration.credential
                if let total = restoration.receipt.package?.totalUsd { previousTotal = Decimal(total); acceptedChangeTotal = Decimal(total) }
            }
        }
        .task(id: quoteInputKey) {
            guard createdSession == nil else { return }
            if !journey.hasFinalGeneratorQuote || journey.quote?.bookingAllowed == false { await recalculatePrice() }
        }
        .task { await push.refreshAndRegisterIfAllowed(); await refreshRoomApproval() }
        .sheet(item: $editSession) { session in
            summaryEditor(session)
        }
        .sheet(isPresented: $showPackageSupport, onDismiss: { Task { await refreshRoomApproval() } }) { packageSupportSheet }
        .sheet(isPresented: $showSharePreview) { savedShareSheet }

        .navigationDestination(isPresented: $isProfileSheetPresented) {
            IumrahBookingConfirmationView(quote: journey.quote, createBooking: { profile, notificationIntent in
                try await createBooking(profile: profile, notificationIntent: notificationIntent)
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
                        journey.invalidateTripSummaryQuote()
                        localHotelForDetails = nil
                    }, onSelectMeals: { meals in
                        journey.localJourneyRooms[room.id]?.meals = meals
                        journey.invalidateTripSummaryQuote()
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
            priceCaption: journey.usesLocalJourney ? tr("Предварительно за всех", "Estimated total", "Taxminiy jami", "Тахминий жами") : tr("Итого за всех", "Total for everyone", "Hamma uchun jami", "Ҳамма учун жами")
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
                    Text(IumrahPackageDisplayPrices.money(quote.pricePerPerson, currency: quote.currency, language: settings.language) + " · " + tr("на одного паломника", "per pilgrim", "bir ziyoratchi uchun", "бир зиёратчи учун"))
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
            if let catalog = hotel.price, catalog.isUsableForPackage, let nightly = catalog.nightlyUSD {
                IumrahPackageUnitPriceLine(amount: Decimal(nightly), currency: "USD",
                    caption: tr("Тариф каталога · за номер / ночь", "Catalog rate · per room / night", "Katalog tarifi · xona / tun", "Каталог тарифи · хона / тун"), language: settings.language)
            }
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
                    Text(IumrahHotelRoomTitle.display(rate: room.rate.roomName, fallback: IumrahFlightCopy.text(settings.language, "Номер", "Room", "Xona", "Хона"))).font(.subheadline)
                }
                Spacer(minLength: 0)
            }
            IumrahHotelStaySummary(checkin: room.checkin, checkout: room.checkout,
                nights: TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights)
            if let nightly = IumrahPackageDisplayPrices.nightly(room) {
                IumrahPackageUnitPriceLine(amount: nightly, currency: room.rate.currency,
                    caption: tr("Ориентировочно за номер / ночь", "Estimated per room / night", "Xona / tun uchun taxminan", "Хона / тун учун тахминан"), language: settings.language)
            }
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
        return included
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
                Text(journey.usesLocalJourney ? tr("Предварительно за всех", "Estimated total", "Taxminiy jami", "Тахминий жами") : tr("Итого за всех", "Total for everyone", "Hamma uchun jami", "Ҳамма учун жами")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(totalText).font(.title3.bold()).monospacedDigit()
            }
            if let quote = journey.quote, journey.hasFinalGeneratorQuote, !isCalculatingPrice {
                HStack {
                    Text(tr("На одного паломника", "Per pilgrim", "Bir ziyoratchi uchun", "Бир зиёратчи учун")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(IumrahPackageDisplayPrices.money(quote.pricePerPerson, currency: quote.currency, language: settings.language))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            if journey.usesLocalJourney {
                Text(tr("Наличие и окончательная стоимость подтверждаются перед оплатой.", "Availability and final price will be confirmed before payment.", "Mavjudlik va yakuniy narx to‘lovdan oldin tasdiqlanadi.", "Мавжудлик ва якуний нарх тўловдан олдин тасдиқланади.")).font(.caption).foregroundStyle(.secondary)
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
                        Text(tr("Забронировать пакет", "Book package", "Paketni bron qilish", "Пакетни брон қилиш"))
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
        let generation = UUID()
        quoteGeneration = generation
        isCalculatingPrice = true
        defer { if quoteGeneration == generation { isCalculatingPrice = false } }
        await journey.buildQuote(forceHotelRefresh: false)
        guard !Task.isCancelled, quoteGeneration == generation else { return }
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
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    @MainActor
    private func createBooking(profile: BookingPilgrimProfile, notificationIntent: BookingCreationNotificationIntent) async throws -> StoredBookingSession {
        if let pendingBookingSession { return pendingBookingSession }
        guard !isSubmitting, canBook,
              let hotel = journey.selectedHotel,
              let outbound = journey.selectedOutbound,
              var quote = journey.quote else { throw BookingStoreError.authoritativeQuoteRequired }
        let inbound = journey.selectedInbound
        guard flightSelectionReady else {
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
                previousTotal = acceptedTotal; acceptedChangeTotal = acceptedTotal
                let acceptedInput = journey.localBookingInputKey
                await journey.buildQuote()
                guard let fresh = journey.quote, journey.hasFinalGeneratorQuote,
                      fresh.bookingAllowed == true, acceptedInput == journey.localBookingInputKey, canBook else {
                    throw BookingStoreError.authoritativeQuoteRequired
                }
                guard fresh.totalPackagePrice == acceptedTotal else {
                    throw ConfiguratorBookingError.priceChanged(tr("Цена изменилась. Вернитесь к итогу поездки и проверьте новую сумму.", "The price changed. Return to the trip review and check the new total.", "Narx o‘zgardi. Safar yakuniga qaytib, yangi summani tekshiring.", "Нарх ўзгарди. Сафар якунига қайтиб, янги суммани текширинг."))
                }
                quote = fresh
            }
            if savedPackage != nil {
                await saveCurrentPackage()
                guard savedQuoteID == quote.quoteId else { throw BookingStoreError.authoritativeQuoteRequired }
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
                notificationIntent: notificationIntent,
                nuiteeRooms: journey.usesLocalJourney ? journey.localBookingRooms : nil
            )
            if let receipt = savedPackage, let credential = ownerCredential {
                do {
                    try await TripSummaryLifecycle.link(receipt: receipt, credential: credential, booking: session)
                    if let fresh = try? await TripSummaryLifecycle.read(receipt, credential) { credential.record(fresh); savedPackage = fresh }
                } catch { credential.recordPendingLink(receipt: receipt, booking: session) }
            }
            pendingBookingSession = session
            if let deviceToken = push.deviceToken {
                await bookings.syncPushSubscriptions(deviceToken: deviceToken, locale: settings.language.rawValue)
            }
            return session
        } catch {
            errorMessage = L10n.error(error, settings.language)
            IumrahHaptics.error()
            throw error
        }
    }

}

/// A mixed itinerary is represented by two discovery/display records, not by
/// full provider segment models. PackageEngine resolves both exact one-way IDs,
/// validates their route and issues the sealed quote. Do not apply the ordinary
/// segment/fare gate a second time to those display records. The final create
/// path still rebuilds the server quote and checks the input and accepted total.
private enum FinalPackageFlightGate {
    static func ready(outbound: FlightOffer?, inbound: FlightOffer?, roundTrip: Bool,
                      usesLocalJourney: Bool, mixedIdentity: String?, localFlightIDs: [String],
                      quote: PackageQuote?) -> Bool {
        guard let outbound else { return false }
        guard let identity = mixedIdentity else {
            return outbound.isVerifiedForBooking && (!roundTrip || inbound?.isVerifiedForBooking == true)
        }
        guard usesLocalJourney, roundTrip, let inbound, let quote,
              quote.bookingAllowed == true, quote.quoteId?.hasPrefix("server-") == true,
              let proof = quote.quoteProof, !proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              quote.totalPackagePrice > 0, quote.pricePerPerson > 0,
              identity.hasPrefix("mixed:"), outbound.providerItineraryID == identity,
              inbound.providerItineraryID == identity,
              localFlightIDs == [outbound.id, inbound.id], outbound.direction == .outbound,
              inbound.direction == .inbound, outbound.origin == inbound.destination,
              ["JED", "MED"].contains(outbound.destination), ["JED", "MED"].contains(inbound.origin),
              inbound.departureAt > outbound.departureAt else { return false }
        let ids = identity.dropFirst("mixed:".count).split(separator: "~", omittingEmptySubsequences: false)
        guard ids.count == 2,
              ids.filter({ $0.hasPrefix("curated:") && $0.count > "curated:".count }).count == 1,
              ids.filter({ $0.hasPrefix("aviasales:ow:") && $0.count > "aviasales:ow:".count }).count == 1 else { return false }
        return outbound.sourceLabel == (ids[0].hasPrefix("curated:") ? "iumrah Published" : "Aviasales Data") &&
               inbound.sourceLabel == (ids[1].hasPrefix("curated:") ? "iumrah Published" : "Aviasales Data")
    }
}

private enum ConfiguratorBookingError: LocalizedError {
    case priceChanged(String)
    var errorDescription: String? { if case .priceChanged(let message) = self { return message }; return nil }
}


/// Display-only fare normalization. Never used for package pricing or booking.
/// A published round trip carries the same complete fare on both legs.
enum IumrahPackageDisplayPrices {
    struct FlightPrice {
        let amount: Decimal
        let currency: String
        let average: Bool
        let roundTrip: Bool
    }

    static func flight(_ offer: FlightOffer, outbound: FlightOffer?, inbound: FlightOffer?, travelers: Int) -> FlightPrice? {
        guard let amount = offer.fareAmount, amount > 0,
              NSDecimalNumber(decimal: amount).doubleValue.isFinite,
              !offer.currency.isEmpty, let scope = offer.fareScope, scope != .unknown else { return nil }
        var roundTrip = false
        if let out = outbound, let back = inbound {
            if let identity = out.providerItineraryID, !identity.isEmpty, identity == back.providerItineraryID,
               !identity.hasPrefix("aviasales:pair:"), !identity.hasPrefix("mixed:") {
                // No invented leg split: both cards describe one complete fare.
                guard out.fareAmount == back.fareAmount, out.currency == back.currency,
                      out.fareScope == back.fareScope, offer.direction == .inbound else { return nil }
                roundTrip = true
            } else if out.pairedLeg != nil || back.pairedLeg != nil {
                // Inconsistent paired fare identity; do not disclose a misleading amount.
                return nil
            }
        } else if offer.pairedLeg != nil || offer.providerItineraryID?.hasPrefix("aviasales:rt:") == true {
            roundTrip = true
        }
        guard scope != .totalParty || travelers > 0 else { return nil }
        return FlightPrice(amount: scope == .totalParty ? amount / Decimal(travelers) : amount,
                           currency: offer.currency, average: scope == .totalParty, roundTrip: roundTrip)
    }

    static func nightly(_ room: LocalJourneyRoom) -> Decimal? {
        guard room.checkout > room.checkin, room.rate.price.isFinite, room.rate.price > 0,
              !room.rate.currency.isEmpty else { return nil }
        let nights = TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights
        return Decimal(room.rate.price) / Decimal(nights)
    }

    static func money(_ value: Decimal, currency: String, language: AppSettingsStore.Language) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(currency) \(value)"
    }
}

struct IumrahPackageFlightPriceLine: View {
    let offer: FlightOffer
    let outbound: FlightOffer?
    let inbound: FlightOffer?
    let travelers: Int
    let language: AppSettingsStore.Language

    var body: some View {
        if let fare = IumrahPackageDisplayPrices.flight(offer, outbound: outbound, inbound: inbound, travelers: travelers) {
            let unit = fare.average
                ? IumrahFlightCopy.text(language, "в среднем на паломника", "average per pilgrim", "ziyoratchiga o‘rtacha", "зиёратчига ўртача")
                : IumrahFlightCopy.text(language, "на человека", "per person", "kishi uchun", "киши учун")
            let direction = fare.roundTrip ? IumrahFlightCopy.text(language, "Туда и обратно", "Round trip", "Borish va qaytish", "Бориш ва қайтиш") + " · " : ""
            IumrahPackageUnitPriceLine(amount: fare.amount, currency: fare.currency, caption: direction + unit, language: language)
        }
    }
}

struct IumrahPackageUnitPriceLine: View {
    let amount: Decimal
    let currency: String
    let caption: String
    let language: AppSettingsStore.Language

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(IumrahPackageDisplayPrices.money(amount, currency: currency, language: language))
                .font(.title3.weight(.bold)).monospacedDigit()
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}


// MARK: - Trip Summary 2.0 (one review surface for every configurator)
private extension LegacyFinalPackageView {
    var publicPrice: TripSummaryPublicPrice? {
        guard journey.hasFinalGeneratorQuote, !isCalculatingPrice, let quote = journey.quote,
              let price = quote.tripSummary, price.totalUsd == quote.totalPackagePrice,
              price.currency == quote.currency, price.version == "trip-summary-v2" else { return nil }
        return price
    }
    var priceChangeAccepted: Bool {
        guard let previousTotal, let quote = journey.quote, previousTotal != quote.totalPackagePrice else { return true }
        return acceptedChangeTotal == quote.totalPackagePrice
    }
    func copy(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String { tr(ru, en, uz, cy) }
    func usd(_ value: Decimal) -> String { IumrahPackageDisplayPrices.money(value, currency: "USD", language: settings.language) }
    func componentAmount(_ codes: [String]) -> Decimal? {
        guard let price = publicPrice else { return nil }
        let lines = price.components.filter { codes.contains($0.code) }
        return lines.isEmpty ? nil : lines.reduce(Decimal.zero) { $0 + $1.amountUsd }
    }
    func componentText(_ codes: [String]) -> String { componentAmount(codes).map(usd) ?? "—" }
    var summaryStay: TripStayBreakdown {
        if let stay = journey.quote?.stayPlan, journey.hasFinalGeneratorQuote {
            return .init(totalNights: stay.totalNights, totalDays: stay.totalDays, makkahNights: stay.makkahNights, madinahNights: stay.madinahNights)
        }
        return TripStayPlanner.breakdown(for: journey.trip)
    }
    func sectionTitle(_ title: String) -> some View { Text(title).font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading) }
    func surface<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
    }
    func disclosure<Content: View>(_ id: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedSummary.contains(id) { expandedSummary.remove(id) } else { expandedSummary.insert(id) }
                }
                IumrahHaptics.selection()
            } label: {
                HStack(alignment: .center) {
                    Text(title).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: expandedSummary.contains(id) ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.foregroundStyle(.secondary).frame(minHeight: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(expandedSummary.contains(id) ? "Expanded" : "Collapsed")
            if expandedSummary.contains(id) { content().transition(.opacity) }
        }
    }
    func detailLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 10)
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
    var changeTitle: String { copy("Изменить", "Change", "O‘zgartirish", "Ўзгартириш") }
    var fullRefundText: String { copy("Бесплатная отмена · полный возврат до начала услуги", "Free cancellation · full refund before service starts", "Bepul bekor qilish · xizmat boshlanishidan oldin to‘liq qaytarish", "Бепул бекор қилиш · хизмат бошланишидан олдин тўлиқ қайтариш") }
    func policyLabel(_ text: String, refundable: Bool = false) -> some View {
        Label(text, systemImage: refundable ? "checkmark.circle.fill" : "info.circle")
            .font(.caption.weight(.medium)).foregroundStyle(refundable ? Color.green : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    var summaryHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy("Ваше путешествие", "Your journey", "Safaringiz", "Сафарингиз")).font(.title2.bold())
            Text(journey.trip.packageTier.title(settings.language) + " · " + journey.trip.scope.title(settings.language)).font(.subheadline)
            Text(dateRange(journey.trip.departureDate, journey.trip.returnDate)).font(.caption)
            HStack(alignment: .top, spacing: 8) {
                heroMetric(summaryStay.totalDays, copy("Дней", "Days", "Kun", "Кун"))
                heroMetric(summaryStay.makkahNights, copy("Ночей · Мекка", "Nights · Makkah", "Tun · Makka", "Тун · Макка"))
                if needsMadinah { heroMetric(summaryStay.madinahNights, copy("Ночей · Медина", "Nights · Madinah", "Tun · Madina", "Тун · Мадина")) }
            }
            Text(partyText).font(.caption).fixedSize(horizontal: false, vertical: true)
            Divider().overlay(.white.opacity(0.2))
            Text(copy("Общая стоимость", "Total price", "Jami narx", "Жами нарх")).font(.caption)
            Text(totalText).font(.largeTitle.bold()).monospacedDigit()
            if let q = journey.quote, journey.hasFinalGeneratorQuote, !isCalculatingPrice {
                Text(IumrahPackageDisplayPrices.money(q.pricePerPerson, currency: q.currency, language: settings.language) + " · " + copy("на паломника", "per pilgrim", "ziyoratchi uchun", "зиёратчи учун")).font(.subheadline)
            }
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
            .background(Color.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 28))
    }
    func heroMetric(_ n: Int, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(n)").font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2).fixedSize(horizontal: false, vertical: true)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
    var guestCard: some View {
        surface {
            HStack {
                Label(copy("Паломники и размещение", "Guests and rooms", "Ziyoratchilar va xonalar", "Зиёратчилар ва хоналар"), systemImage: "person.2").font(.headline)
                Spacer(minLength: 4)
                Button(changeTitle) { guestDraft = TripSummaryGuestDraft(journey: journey); expandedSummary.insert("guest") }.font(.subheadline.weight(.semibold))
            }
            Text(partyText).font(.subheadline).foregroundStyle(.secondary)
            disclosure("guest", copy("Состав семьи и номера", "Family and rooms", "Oila va xonalar", "Оила ва хоналар")) {
                if guestDraft == nil {
                    Button(copy("Изменить состав", "Edit guests", "Tarkibni o‘zgartirish", "Таркибни ўзгартириш")) { guestDraft = TripSummaryGuestDraft(journey: journey) }.buttonStyle(IumrahSecondaryButtonStyle())
                }
                if let draft = guestDraft { guestControls(draft) }
                else { roomDistribution(journey.trip) }
                Text(copy("Обычно до четырёх взрослых; некоторые номера вмещают пять. Вместимость с детьми проверяется отдельно по тарифу отеля.", "Usually up to four adults; some rooms sleep five. Hotel occupancy including children is checked separately.", "Odatda to‘rt katta, ayrim xonalarda beshta. Bolalar bilan sig‘im tarif bo‘yicha tekshiriladi.", "Одатда тўрт катта, айрим хоналарда бешта. Болалар билан сиғим тариф бўйича текширилади.")).font(.caption).foregroundStyle(.secondary)
            }
            if let approved = approvedRoomRequest, approved.adults == journey.trip.adults, approved.rooms < journey.trip.rooms, journey.usesLocalJourney {
                Button(copy("Выбрать согласованное размещение", "Select approved occupancy", "Kelishilgan joylashuvni tanlash", "Келишилган жойлашувни танлаш")) {
                    var draft = TripSummaryGuestDraft(journey: journey); draft.rooms = approved.rooms; adultExceptionRequested = false; applyGuests(draft)
                }.buttonStyle(IumrahSecondaryButtonStyle())
                Text(approved.note).font(.caption).foregroundStyle(.secondary)
            }
            if adultExceptionRequested { adultWarning }
        }
    }
    func guestControls(_ draft: TripSummaryGuestDraft) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper(copy("Взрослые", "Adults", "Kattalar", "Катталар") + " · \(draft.adults)", onIncrement: {
                var next = draft; guard next.total < 9 else { return }; next.adults += 1
                if next.adults > next.rooms * 5 { next.rooms = TripSummaryGuestDraft.minimumRooms(next.adults); adultExceptionRequested = true }
                guestDraft = next
            }, onDecrement: {
                var next = draft; guard next.adults > 1 else { return }; next.adults -= 1; next.rooms = min(next.rooms, next.adults); guestDraft = next
                if next.adults <= 5 { adultExceptionRequested = false }
            })
            guestAgeCounter(draft, group: .teen)
            guestAgeCounter(draft, group: .child)
            guestAgeCounter(draft, group: .infant)
            ForEach(draft.ages.indices, id: \.self) { index in
                Picker(copy("Возраст ребёнка", "Child age", "Bola yoshi", "Бола ёши") + " \(index + 1)", selection: Binding(get: { guestDraft.flatMap { $0.ages.indices.contains(index) ? $0.ages[index] : nil } ?? draft.ages[index] }, set: { age in
                    guard var next = guestDraft, next.ages.indices.contains(index) else { return }; next.ages[index] = age; guestDraft = next
                })) {
                    Text(copy("Укажите возраст", "Select age", "Yoshni tanlang", "Ёшни танланг")).tag(draft.ages[index] < 0 ? draft.ages[index] : -1)
                    ForEach(0...17, id: \.self) { Text("\($0)").tag($0) }
                }.font(.subheadline)
            }
            Divider()
            Stepper(copy("Номера", "Rooms", "Xonalar", "Хоналар") + " · \(draft.rooms)", onIncrement: {
                var next = draft; guard next.rooms < next.adults else { return }; next.rooms += 1; guestDraft = next; adultExceptionRequested = false
            }, onDecrement: {
                guard draft.rooms > 1 else { return }
                if draft.adults > (draft.rooms - 1) * 5 { adultExceptionRequested = true; return }
                var next = draft; next.rooms -= 1; guestDraft = next; adultExceptionRequested = false
            })
            roomDistribution(draft.trip(from: journey.trip), minorCount: draft.ages.count)
            if draft.total > 7 { policyLabel(copy("Потребуется проверка транспорта для большой семьи.", "Transport for a large family requires verification.", "Katta oila uchun transport tekshiriladi.", "Катта оила учун транспорт текширилади.")) }
            Button(copy("Применить и пересчитать", "Apply and reprice", "Qo‘llash va hisoblash", "Қўллаш ва ҳисоблаш")) { applyGuests(draft) }
                .buttonStyle(IumrahPrimaryButtonStyle()).disabled(draft.ages.contains(where: { $0 < 0 }) || draft.total > 9 || draft.rooms > draft.adults)
            Button(copy("Отменить изменения", "Discard changes", "O‘zgarishlarni bekor qilish", "Ўзгаришларни бекор қилиш")) { guestDraft = nil; adultExceptionRequested = false }.font(.subheadline)
        }.tint(.primary)
    }
    func guestAgeCounter(_ draft: TripSummaryGuestDraft, group: TripSummaryGuestDraft.AgeGroup) -> some View {
        let title: String = switch group {
        case .teen: copy("Подростки 12–17", "Teens 12–17", "O‘smirlar 12–17", "Ўсмирлар 12–17")
        case .child: copy("Дети 2–11", "Children 2–11", "Bolalar 2–11", "Болалар 2–11")
        case .infant: copy("Младенцы до 2", "Infants under 2", "Chaqaloqlar 2 yoshgacha", "Чақалоқлар 2 ёшгача")
        }
        return Stepper(title + " · \(draft.ages.filter(group.contains).count)", onIncrement: {
            var next = draft; guard next.total < 9 else { return }; next.ages.append(group.defaultAge); guestDraft = next
        }, onDecrement: {
            var next = draft; if let index = next.ages.lastIndex(where: group.contains) { next.ages.remove(at: index); guestDraft = next }
        })
    }
    func roomDistribution(_ trip: TripDraft, minorCount: Int? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(0..<max(1, trip.rooms), id: \.self) { index in
                let adults = trip.adults / max(1, trip.rooms) + (index < trip.adults % max(1, trip.rooms) ? 1 : 0)
                let count = minorCount ?? (trip.children + trip.infants)
                let minors = count / max(1, trip.rooms) + (index < count % max(1, trip.rooms) ? 1 : 0)
                detailLine(copy("Номер", "Room", "Xona", "Хона") + " \(index + 1)", "\(adults) " + copy("взр.", "adults", "katta", "катта") + " · \(minors) " + copy("дет.", "children", "bola", "бола"))
            }
            Text(copy("Предварительное распределение", "Proposed room distribution", "Taxminiy joylashuv", "Тахминий жойлашув")).font(.caption2).foregroundStyle(.secondary)
        }
    }
    var adultWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(copy("Индивидуальное размещение", "Custom occupancy", "Individual joylashuv", "Индивидуал жойлашув"), systemImage: "exclamationmark.triangle.fill").font(.headline)
            Text(copy("Более пяти взрослых в одном номере — только после согласования. Мы проверим возможность размещения в выбранных отелях.", "More than five adults in one room requires approval. We will check the selected hotels.", "Bitta xonada beshtadan ortiq katta faqat kelishuv bilan. Mehmonxonalarni tekshiramiz.", "Битта хонада бештадан ортиқ катта фақат келишув билан. Меҳмонхоналарни текширамиз.")).font(.subheadline)
            Button(copy("Обратиться в поддержку", "Contact support", "Yordamga murojaat qilish", "Ёрдамга мурожаат қилиш")) { showPackageSupport = true }.buttonStyle(IumrahSecondaryButtonStyle())
            Button(copy("Оставить дополнительные номера", "Keep additional rooms", "Qo‘shimcha xonalarni qoldirish", "Қўшимча хоналарни қолдириш")) { adultExceptionRequested = false }.font(.caption.weight(.semibold))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.yellow.opacity(0.20), in: RoundedRectangle(cornerRadius: 16))
    }
    @MainActor func refreshRoomApproval() async {
        guard let receipt = savedPackage, let credential = ownerCredential else { return }
        do {
            let thread = try await TripSummaryLifecycle.thread(receipt, credential)
            if let request = thread.roomRequest, request.state == "approved" {
                approvedRoomRequest = request
                journey.tripSummaryApprovalHeaders = ["x-package-id":receipt.packageID,"x-package-owner":credential.token]
            }
        } catch { /* Normal room limit remains in force. */ }
    }
    func applyGuests(_ draft: TripSummaryGuestDraft) {
        let next = draft.trip(from: journey.trip)
        guard next != journey.trip || draft.ages != journey.tripSummaryChildAges else { guestDraft = nil; return }
        beginPriceChange()
        journey.applyTripSummaryGuests(next, ages: draft.ages)
        guestDraft = nil
        if journey.usesLocalJourney { editSession = TripSummaryEditSession(kind: .allHotels, journey: journey) }
    }
    func beginPriceChange() {
        if previousTotal == nil || priceChangeAccepted { previousTotal = journey.quote?.totalPackagePrice }
        acceptedChangeTotal = nil
        savedQuoteID = nil
    }
    func priceChangeCard(_ old: Decimal, quote: PackageQuote) -> some View {
        surface {
            Text(copy("Стоимость изменилась", "Price changed", "Narx o‘zgardi", "Нарх ўзгарди")).font(.headline)
            detailLine(copy("Прежняя стоимость", "Previous total", "Avvalgi narx", "Аввалги нарх"), usd(old))
            detailLine(copy("Новая стоимость", "New total", "Yangi narx", "Янги нарх"), usd(quote.totalPackagePrice))
            detailLine(copy("Разница", "Difference", "Farq", "Фарқ"), usd(quote.totalPackagePrice - old))
            Button(copy("Подтвердить новую цену", "Accept new price", "Yangi narxni tasdiqlash", "Янги нархни тасдиқлаш")) { acceptedChangeTotal = quote.totalPackagePrice }.buttonStyle(IumrahPrimaryButtonStyle())
        }
    }
    var compactFlights: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(copy("Авиабилеты", "Flights", "Aviachiptalar", "Авиачипталар"))
            if let out = journey.selectedOutbound { compactFlight(out, id: "out", title: copy("Рейс туда", "Outbound", "Borish reysi", "Бориш рейси")) }
            else { missingFlight }
            if journey.trip.isRoundTripFlight, let back = journey.selectedInbound { compactFlight(back, id: "back", title: copy("Обратный рейс", "Return flight", "Qaytish reysi", "Қайтиш рейси")) }
            else if journey.trip.isRoundTripFlight { missingFlight }
            detailLine(copy("Все авиабилеты", "All flights", "Barcha chiptalar", "Барча чипталар"), componentText(["flight_roundtrip", "flight_outbound", "flight_inbound"]))
        }
    }
    var missingFlight: some View {
        surface { Button(copy("Выбрать рейсы", "Choose flights", "Reyslarni tanlash", "Рейсларни танлаш")) { editSession = TripSummaryEditSession(kind: .flights, journey: journey) }.buttonStyle(IumrahSecondaryButtonStyle()) }
    }
    func compactFlight(_ offer: FlightOffer, id: String, title: String) -> some View {
        let leg = flightLeg(offer)
        return surface {
            HStack { Text(title).font(.headline); Spacer(); Button(changeTitle) { editSession = TripSummaryEditSession(kind: .flights, journey: journey) }.font(.subheadline.weight(.semibold)) }
            Text(offer.airlinesSummary + " · " + offer.flightNumbersSummary).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) { Text(offer.origin).font(.title2.bold()); Text(IumrahFlightClock.local(leg.departureAt, airport: offer.origin)).font(.caption2) }
                Spacer(minLength: 4)
                VStack(spacing: 3) { Image(systemName: "airplane"); Text(offer.stops == 0 ? copy("Прямой", "Direct", "To‘g‘ridan to‘g‘ri", "Тўғридан тўғри") : "\(offer.stops) " + copy("пересадок", "stops", "bekat", "бекат")).font(.caption2) }.foregroundStyle(.secondary)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) { Text(offer.destination).font(.title2.bold()); Text(IumrahFlightClock.local(leg.arrivalAt, airport: offer.destination)).font(.caption2) }
            }
            if let _ = IumrahPackageDisplayPrices.flight(offer, outbound: journey.selectedOutbound, inbound: journey.selectedInbound, travelers: journey.trip.travelerCount) {
                IumrahPackageFlightPriceLine(offer: offer, outbound: journey.selectedOutbound, inbound: journey.selectedInbound, travelers: journey.trip.travelerCount, language: settings.language)
            }
            policyLabel(IumrahRefundComponent.flight.badge(settings.language))
            disclosure("flight-" + id, copy("Багаж, тариф и условия", "Baggage, fare and terms", "Bagaj, tarif va shartlar", "Багаж, тариф ва шартлар")) {
                detailLine(copy("Класс", "Cabin", "Klass", "Класс"), offer.cabinClass ?? journey.trip.effectiveFlightFilters.cabinClass.rawValue)
                if let b = offer.baggage {
                    if let checked = b.checked { detailLine(copy("Багаж", "Checked baggage", "Bagaj", "Багаж"), "\(checked) kg") }
                    if let carry = b.carryOn { detailLine(copy("Ручная кладь", "Carry-on", "Qo‘l yuki", "Қўл юки"), "\(carry) kg") }
                } else { Text(copy("Багаж — по условиям тарифа", "Baggage according to fare", "Bagaj tarifga muvofiq", "Багаж тарифга мувофиқ")).font(.caption) }
                Text(IumrahRefundComponent.flight.summary(settings.language)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    var compactHotels: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(copy("Проживание", "Accommodation", "Mehmonxonalar", "Меҳмонхоналар"))
            if journey.usesLocalJourney {
                if journey.localJourneyRooms.isEmpty { missingHotels }
                ForEach(journey.localJourneyRooms.values.sorted { $0.checkin == $1.checkin ? $0.id < $1.id : $0.checkin < $1.checkin }) { room in compactLocalHotel(room) }
                if !journey.localRoomsComplete && !journey.localJourneyRooms.isEmpty { missingHotels }
            } else {
                if let hotel = journey.selectedHotel { compactCatalogHotel(hotel, role: .makkah) } else { missingHotels }
                if needsMadinah, let hotel = journey.selectedMadinahHotel { compactCatalogHotel(hotel, role: .madinah) }
                else if needsMadinah { missingHotels }
            }
        }
    }
    var missingHotels: some View {
        surface { Button(copy("Выбрать отели и номера", "Choose hotels and rooms", "Mehmonxona va xonalarni tanlash", "Меҳмонхона ва хоналарни танлаш")) { editSession = TripSummaryEditSession(kind: journey.usesLocalJourney ? .allHotels : .catalog(.makkah), journey: journey) }.buttonStyle(IumrahSecondaryButtonStyle()) }
    }
    func photo(_ url: String?) -> some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() } placeholder: {
            Rectangle().fill(Color.secondary.opacity(0.12)).overlay(Image(systemName: "building.2").foregroundStyle(.secondary))
        }.frame(width: 82, height: 86).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    func cityName(_ city: String) -> String { L10n.city(city == "madinah" ? "Madinah" : "Makkah", settings.language) }
    func plannedHotelTime(_ city: String, kind: String) -> String? {
        guard let items = journey.quote?.itineraryPreview else { return nil }
        return items.first { $0.kind == kind && ($0.location.lowercased().contains(city) || (city == "madinah" && $0.location.lowercased().contains("medina"))) }?.timeLocal.map { $0 + " (KSA · " + copy("план", "planned", "reja", "режа") + ")" }
    }
    func hotelAmount(_ city: String) -> String { componentText([city == "madinah" ? "madinah_hotel" : "makkah_hotel"]) }
    func compactLocalHotel(_ room: LocalJourneyRoom) -> some View {
        let nights = TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights
        let roomCount = journey.localJourneyRooms.values.filter { $0.city == room.city }.count
        return surface {
            HStack(alignment: .top, spacing: 12) {
                photo(room.hotel.coverImageURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(cityName(room.city) + " · \(nights) " + copy("ночей", "nights", "tun", "тун")).font(.caption).foregroundStyle(.secondary)
                    Text(room.hotel.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(String(repeating: "★", count: max(0, min(5, room.hotel.roundedStars))) + " · " + dateRange(room.checkin, room.checkout)).font(.caption)
                    if roomCount == 1 { Text(hotelAmount(room.city)).font(.title3.bold()).monospacedDigit() }
                    else { Text(IumrahPackageDisplayPrices.money(Decimal(room.rate.price), currency: room.rate.currency, language: settings.language)).font(.headline); Text(copy("Тариф номера", "Room rate", "Xona tarifi", "Хона тарифи")).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            Text(room.rate.roomName).font(.subheadline)
            HStack { Text(room.rate.mealPlan).font(.caption).foregroundStyle(.secondary); Spacer(); Button(changeTitle) { editSession = TripSummaryEditSession(kind: .hotel(room.city), journey: journey) }.font(.subheadline.weight(.semibold)) }
            policyLabel(room.rate.refundable ? copy("Возврат по условиям тарифа", "Refundable under rate terms", "Tarif shartlari bo‘yicha qaytarish", "Тариф шартлари бўйича қайтариш") : copy("Невозвратный тариф", "Non-refundable rate", "Qaytarilmaydigan tarif", "Қайтарилмайдиган тариф"), refundable: room.rate.refundable)
            if !room.rate.cancellationDescription.isEmpty { Text(room.rate.cancellationDescription).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            disclosure("hotel-" + room.id, copy("Номер, питание и условия", "Room, meals and terms", "Xona, ovqat va shartlar", "Хона, овқат ва шартлар")) {
                IumrahHotelStaySummary(checkin: room.checkin, checkout: room.checkout, nights: nights, adults: room.adults, children: room.childrenAges.count, checkinTime: plannedHotelTime(room.city, kind: "hotelCheckIn"), checkoutTime: plannedHotelTime(room.city, kind: "hotelCheckOut"))
                if let nightly = IumrahPackageDisplayPrices.nightly(room) { detailLine(copy("Средняя цена за ночь", "Average per night", "Tun uchun o‘rtacha", "Тун учун ўртача"), IumrahPackageDisplayPrices.money(nightly, currency: room.rate.currency, language: settings.language)) }
                Button(copy("Изменить номер и питание", "Change room and meals", "Xona va ovqatni o‘zgartirish", "Хона ва овқатни ўзгартириш")) { beginPriceChange(); localHotelForDetails = room }.buttonStyle(IumrahSecondaryButtonStyle())
                IumrahHotelMealsEditor(selection: Binding(get: { journey.localJourneyRooms[room.id]?.meals ?? HotelMealChoices() }, set: { value in
                    beginPriceChange(); journey.localJourneyRooms[room.id]?.meals = value; journey.invalidateTripSummaryQuote()
                }), stars: room.hotel.roundedStars, city: room.city, included: room.rate.supplierMeals)
            }
        }
    }
    func compactCatalogHotel(_ hotel: HotelSummary, role: HotelSelectionRole) -> some View {
        let windows = TripStayPlanner.windows(for: journey.trip)
        let window = role == .makkah ? windows.makkah : windows.madinah ?? windows.makkah
        let nights = role == .makkah ? summaryStay.makkahNights : summaryStay.madinahNights
        return surface {
            HStack(alignment: .top, spacing: 12) {
                photo(hotel.coverImageURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(cityName(role.rawValue) + " · \(nights) " + copy("ночей", "nights", "tun", "тун")).font(.caption).foregroundStyle(.secondary)
                    Text(hotel.name).font(.headline)
                    if let stars = hotel.stars { Text(String(repeating: "★", count: max(0, min(5, stars)))).font(.caption) }
                    if let rating = hotel.rating { Text(String(format: "%.1f", rating)).font(.caption) }
                    Text(hotelAmount(role.rawValue)).font(.title3.bold())
                }
                Spacer(minLength: 0)
            }
            detailLine(copy("Даты", "Dates", "Sanalar", "Саналар"), dateRange(window.checkIn, window.checkOut))
            HStack { Text(roomName(role)).font(.subheadline); Spacer(); Button(changeTitle) { editSession = TripSummaryEditSession(kind: .catalog(role), journey: journey) }.font(.subheadline.weight(.semibold)) }
            policyLabel(IumrahRefundComponent.hotel.badge(settings.language))
            disclosure("catalog-" + role.rawValue, copy("Номер, питание и условия", "Room, meals and terms", "Xona, ovqat va shartlar", "Хона, овқат ва шартлар")) {
                Text(mealsText).font(.caption)
                Text(IumrahRefundComponent.hotel.summary(settings.language)).font(.caption).foregroundStyle(.secondary)
                Button(copy("Изменить номер", "Change room", "Xonani o‘zgartirish", "Хонани ўзгартириш")) { beginPriceChange(); hotelForDetails = hotel }.buttonStyle(IumrahSecondaryButtonStyle())
            }
        }
    }
    var compactServices: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(copy("Индивидуальное обслуживание", "Private services", "Individual xizmatlar", "Индивидуал хизматлар"))
            surface {
                HStack(alignment: .center, spacing: 12) {
                    if let vehicle = journey.selectedTransferVehicle { Image(vehicle.assetName).resizable().scaledToFit().frame(width: 112, height: 74) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy("Индивидуальный трансфер", "Private transfer", "Individual transfer", "Индивидуал трансфер")).font(.headline)
                        Text(journey.selectedTransferVehicle?.modelName ?? copy("Выберите автомобиль", "Select vehicle", "Avtomobilni tanlang", "Автомобилни танланг")).font(.caption).foregroundStyle(.secondary)
                        Text(componentText(["transfers", "vip_transfer_upgrade"])).font(.title3.bold())
                    }; Spacer(minLength: 0)
                }
                if let deadline = transferDeadline { policyLabel(copy("Плановый срок бесплатной отмены: ", "Planned free cancellation deadline: ", "Bepul bekor qilishning taxminiy muddati: ", "Бепул бекор қилишнинг тахминий муддати: ") + deadline, refundable: true) }
                else { policyLabel(copy("Полный возврат при отмене за 24 часа", "Full refund when cancelled 24h before pickup", "24 soat oldin bekor qilishda to‘liq qaytarish", "24 соат олдин бекор қилишда тўлиқ қайтариш"), refundable: true) }
                Text(copy("Позже, до начала: штраф до $100, возврат остатка.", "Later, before service: up to $100 penalty, remainder refunded.", "Keyin, xizmatdan oldin: $100 gacha jarima, qoldiq qaytariladi.", "Кейин, хизматдан олдин: $100 гача жарима, қолдиқ қайтарилади.")).font(.caption).foregroundStyle(.secondary)
                if let vehicle = journey.selectedTransferVehicle, vehicle.passengerCapacity < journey.trip.travelerCount { policyLabel(copy("Нужен автомобиль подходящей вместимости", "Select a vehicle with enough seats", "Yetarli o‘rinli avtomobilni tanlang", "Етарли ўринли автомобилни танланг")) }
                Button(changeTitle) { editSession = TripSummaryEditSession(kind: .transfer, journey: journey) }.font(.subheadline.weight(.semibold))
                disclosure("transfer", copy("Маршрут и условия", "Route and terms", "Yo‘nalish va shartlar", "Йўналиш ва шартлар")) { IumrahTransferRouteDetails(); Text(IumrahRefundComponent.transfer.summary(settings.language)).font(.caption).foregroundStyle(.secondary) }
            }
            simpleService("guide", title: copy("Персональный гид", "Personal guide", "Shaxsiy gid", "Шахсий гид"), subtitle: copy("Один гид для вашей семьи", "One guide for your family", "Oilangiz uchun bitta gid", "Оилангиз учун битта гид"), icon: "person.crop.circle.badge.checkmark", asset: "AboutIumrahPilgrims", codes: ["accompaniment"], policy: fullRefundText, refundable: true) {
                Text(copy("Встреча в аэропорту, заселение, сопровождение при умре и зияратах, помощь до возвращения домой.", "Airport welcome, check-in, Umrah and ziyarat accompaniment, help until the return home.", "Aeroportda kutib olish, joylashish, umra va ziyoratlarda hamrohlik, qaytishgacha yordam.", "Аэропортда кутиб олиш, жойлашиш, умра ва зиёратларда ҳамроҳлик, қайтишгача ёрдам.")).font(.subheadline)
                Button(copy("Подробнее о гиде", "Guide details", "Gid haqida", "Гид ҳақида")) { infoSheet = .guide }.buttonStyle(IumrahSecondaryButtonStyle())
            }
            simpleService("ziyarat-m", title: copy("Зияраты в Мекке", "Makkah ziyarat", "Makka ziyoratlari", "Макка зиёратлари"), subtitle: copy("Индивидуальная программа", "Private program", "Individual dastur", "Индивидуал дастур"), icon: "mappin.and.ellipse", asset: nil, codes: ["ziyarat_makkah"], policy: fullRefundText, refundable: true) { Text(copy("Маршрут и время согласовываются с гидом.", "Route and time arranged with the guide.", "Yo‘nalish va vaqt gid bilan kelishiladi.", "Йўналиш ва вақт гид билан келишилади.")).font(.caption) }
            if needsMadinah { simpleService("ziyarat-d", title: copy("Зияраты в Медине", "Madinah ziyarat", "Madina ziyoratlari", "Мадина зиёратлари"), subtitle: copy("Индивидуальная программа", "Private program", "Individual dastur", "Индивидуал дастур"), icon: "mappin.and.ellipse", asset: "ZiyaratQuba1", codes: ["ziyarat_madinah"], policy: fullRefundText, refundable: true) { Text(copy("Маршрут и время согласовываются с гидом.", "Route and time arranged with the guide.", "Yo‘nalish va vaqt gid bilan kelishiladi.", "Йўналиш ва вақт гид билан келишилади.")).font(.caption) } }
            simpleService("visa", title: copy("Визы и документы", "Visas and documents", "Viza va hujjatlar", "Виза ва ҳужжатлар"), subtitle: copy("Туристические визы", "Tourist visas", "Turistik vizalar", "Туристик визалар"), icon: "doc.text", asset: nil, codes: ["visa"], policy: copy("Полный возврат до подачи; после подачи — без возврата", "Full refund before submission; non-refundable after submission", "Topshirishdan oldin to‘liq qaytarish; keyin qaytarilmaydi", "Топширишдан олдин тўлиқ қайтариш; кейин қайтарилмайди"), refundable: true) {
                Text(copy("Сначала оформляются визы. После успешного получения виз начинается покупка авиабилетов.", "Visas are processed first. Ticket purchase starts after the visas are issued.", "Avval vizalar rasmiylashtiriladi. Vizalar olingach aviachiptalar xaridi boshlanadi.", "Аввал визалар расмийлаштирилади. Визалар олингач авиачипталар хариди бошланади.")).font(.subheadline)
            }
            if journey.haramainTrainSelected { simpleService("train", title: "Haramain", subtitle: trainText, icon: "tram", asset: nil, codes: ["haramain_train_addon"], policy: copy("По условиям тарифа", "Subject to fare terms", "Tarif shartlariga ko‘ra", "Тариф шартларига кўра"), refundable: false) { Text(trainText).font(.caption) } }
            surface { Label("iumrah Mobile eSIM", systemImage: "simcard").font(.headline); Text(FlowCopy.text(.included, settings.language)).font(.caption).foregroundStyle(.secondary) }
        }
    }
    func simpleService<Content: View>(_ id: String, title: String, subtitle: String, icon: String, asset: String?, codes: [String], policy: String, refundable: Bool, @ViewBuilder content: () -> Content) -> some View {
        surface {
            HStack(alignment: .center, spacing: 12) {
                if let asset { Image(asset).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 14)) }
                else { Image(systemName: icon).font(.title2).frame(width: 38) }
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 4); Text(componentText(codes)).font(.headline).monospacedDigit()
            }
            policyLabel(policy, refundable: refundable)
            disclosure("service-" + id, copy("Подробнее", "Details", "Batafsil", "Батафсил"), content: content)
        }
    }
    var transferDeadline: String? {
        guard let event = journey.quote?.itineraryPreview?.first(where: { $0.kind == "hotelTransfer" }), let time = event.timeLocal else { return nil }
        let parser = ISO8601DateFormatter()
        guard let start = parser.date(from: event.dateLocal + "T" + time + ":00+03:00") else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: settings.language.localeIdentifier); formatter.timeZone = TimeZone(identifier: "Asia/Riyadh"); formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: start.addingTimeInterval(-86400)) + " (KSA)"
    }
    var supportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Label(copy("iumrah Поддержка", "iumrah Support", "iumrah Yordam", "iumrah Ёрдам"), systemImage: "headset").font(.title3.bold()); Spacer(); Text("9%").font(.title2.bold()) }
            Text(copy("Мы с вами на каждом этапе", "With you at every stage", "Har bosqichda yoningizdamiz", "Ҳар босқичда ёнингиздамиз")).font(.headline)
            Text(copy("До поездки, во время путешествия и до возвращения домой.", "Before, during and until your return home.", "Safardan oldin, safarda va uyga qaytguncha.", "Сафардан олдин, сафарда ва уйга қайтгунча.")).font(.caption)
            Divider().overlay(.white.opacity(0.2))
            detailLine(copy("Поддержка и комиссия", "Support and platform fee", "Yordam va platforma haqi", "Ёрдам ва платформа ҳақи"), publicPrice.map { usd($0.supportAmountUsd) } ?? "—")
            disclosure("support", copy("Что входит", "What is included", "Nimalar kiradi", "Нималар киради")) { Text(copy("Координация бронирований, помощь с документами, гидом, трансферами и поддержка 24/7.", "Booking coordination, help with documents, guide, transfers and 24/7 support.", "Bronlar, hujjatlar, gid, transferlar va 24/7 yordam.", "Бронлар, ҳужжатлар, гид, трансферлар ва 24/7 ёрдам.")).font(.subheadline) }
            Button(copy("Задать вопрос о путешествии", "Ask about your trip", "Safar haqida so‘rash", "Сафар ҳақида сўраш")) { showPackageSupport = true }.buttonStyle(.bordered).tint(.white)
        }.padding(18).foregroundStyle(.white).environment(\.colorScheme, .dark).background(Color.black, in: RoundedRectangle(cornerRadius: 24))
    }
    func componentLabel(_ c: TripSummaryPublicPrice.Component) -> String {
        switch c.code {
        case "flight_roundtrip": return copy("Авиабилеты", "Flights", "Aviachiptalar", "Авиачипталар")
        case "flight_outbound": return copy("Рейс туда", "Outbound", "Borish", "Бориш")
        case "flight_inbound": return copy("Обратно", "Return", "Qaytish", "Қайтиш")
        case "makkah_hotel": return copy("Отель в Мекке", "Makkah hotel", "Makka mehmonxonasi", "Макка меҳмонхонаси")
        case "madinah_hotel": return copy("Отель в Медине", "Madinah hotel", "Madina mehmonxonasi", "Мадина меҳмонхонаси")
        case "visa": return copy("Визы", "Visas", "Vizalar", "Визалар")
        case "transfers": return copy("Трансфер", "Transfer", "Transfer", "Трансфер")
        case "accompaniment": return copy("Персональный гид", "Personal guide", "Shaxsiy gid", "Шахсий гид")
        case "ziyarat_makkah": return copy("Зияраты в Мекке", "Makkah ziyarat", "Makka ziyoratlari", "Макка зиёратлари")
        case "ziyarat_madinah": return copy("Зияраты в Медине", "Madinah ziyarat", "Madina ziyoratlari", "Мадина зиёратлари")
        case "meals": return copy("Питание", "Meals", "Ovqatlanish", "Овқатланиш")
        case "esim": return "eSIM"
        case "vip_transfer_upgrade": return copy("VIP трансфер", "VIP transfer", "VIP transfer", "VIP трансфер")
        case "haramain_train_addon": return "Haramain"
        default: return c.label
        }
    }
    var priceBreakdownCard: some View {
        surface {
            sectionTitle(copy("Детализация стоимости", "Price breakdown", "Narx tafsilotlari", "Нарх тафсилотлари"))
            if let price = publicPrice {
                ForEach(price.components) { c in
                    disclosure("price-" + c.code, componentLabel(c) + " · " + usd(c.amountUsd)) { componentDetails(c) }
                    Divider()
                }
                detailLine(copy("Стоимость услуг", "Services subtotal", "Xizmatlar jami", "Хизматлар жами"), usd(price.servicesSubtotalUsd))
                disclosure("price-support", copy("Поддержка и комиссия · 9%", "Support and fee · 9%", "Yordam va komissiya · 9%", "Ёрдам ва комиссия · 9%") + " · " + usd(price.supportAmountUsd)) { detailLine(usd(price.servicesSubtotalUsd) + " × 9%", usd(price.supportAmountUsd)) }
                disclosure("price-payment", copy("Комиссия оплаты · 2%", "Payment fee · 2%", "To‘lov komissiyasi · 2%", "Тўлов комиссияси · 2%") + " · " + usd(price.paymentAmountUsd)) { detailLine(usd(price.totalUsd) + " × 2%", usd(price.paymentAmountUsd)) }
                if price.roundingUsd != 0 { detailLine(copy("Округление", "Rounding", "Yaxlitlash", "Яхлитлаш"), usd(price.roundingUsd)) }
                Divider()
                disclosure("chart", copy("Диаграмма стоимости", "Price distribution", "Narx diagrammasi", "Нарх диаграммаси")) { priceChart(price) }
                Divider()
                detailLine(copy("Итого", "Total", "Jami", "Жами"), usd(price.totalUsd))
            } else {
                Text(copy("Подробный расчёт пока недоступен. Стоимость подтверждается сервером; отдельные цены не вычисляются на устройстве.", "Detailed pricing is not available yet. The server confirms the total; individual prices are not calculated on the device.", "Batafsil narx hozircha mavjud emas. Jami serverda tasdiqlanadi.", "Батафсил нарх ҳозирча мавжуд эмас. Жами серверда тасдиқланади.")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder func componentDetails(_ c: TripSummaryPublicPrice.Component) -> some View {
        if c.code == "visa" {
            detailLine(copy("Количество виз", "Visa count", "Vizalar soni", "Визалар сони"), "\(journey.trip.travelerCount)")
            if journey.trip.travelerCount > 0 { detailLine(copy("Средняя стоимость визы", "Average visa price", "O‘rtacha viza narxi", "Ўртача виза нархи"), usd(c.amountUsd / Decimal(journey.trip.travelerCount))) }
        } else if c.code == "makkah_hotel" || c.code == "madinah_hotel" {
            let nights = c.code == "makkah_hotel" ? summaryStay.makkahNights : summaryStay.madinahNights
            detailLine(copy("Ночей", "Nights", "Tunlar", "Тунлар"), "\(nights)")
            detailLine(copy("Номеров", "Rooms", "Xonalar", "Хоналар"), "\(journey.trip.rooms)")
            if nights > 0, journey.trip.rooms > 0 { detailLine(copy("В среднем за номер / ночь", "Average per room / night", "Xona / tun o‘rtacha", "Хона / тун ўртача"), usd(c.amountUsd / Decimal(nights * journey.trip.rooms))) }
        } else if c.code.hasPrefix("flight_") {
            detailLine(copy("Пассажиры", "Passengers", "Yo‘lovchilar", "Йўловчилар"), "\(journey.trip.travelerCount)")
            if journey.trip.travelerCount > 0 { detailLine(copy("В среднем на пассажира", "Average per passenger", "Yo‘lovchi uchun o‘rtacha", "Йўловчи учун ўртача"), usd(c.amountUsd / Decimal(journey.trip.travelerCount))) }
        } else if c.code == "transfers" { detailLine(copy("Автомобиль", "Vehicle", "Avtomobil", "Автомобил"), journey.selectedTransferVehicle?.modelName ?? "—") }
        else if c.code == "accompaniment" { detailLine(copy("Сопровождение", "Accompaniment", "Hamrohlik", "Ҳамроҳлик"), copy("Индивидуально", "Private", "Individual", "Индивидуал")) }
        else { detailLine(copy("Паломники", "Pilgrims", "Ziyoratchilar", "Зиёратчилар"), "\(journey.trip.travelerCount)") }
        detailLine(copy("Итого", "Total", "Jami", "Жами"), usd(c.amountUsd))
    }
    func priceChart(_ price: TripSummaryPublicPrice) -> some View {
        let values = price.components.map { (componentLabel($0), $0.amountUsd) } + [(copy("Поддержка", "Support", "Yordam", "Ёрдам"), price.supportAmountUsd), (copy("Оплата", "Payment", "To‘lov", "Тўлов"), price.paymentAmountUsd), (copy("Округление", "Rounding", "Yaxlitlash", "Яхлитлаш"), price.roundingUsd)]
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        let positiveTotal = values.reduce(Decimal.zero) { $0 + max(0, $1.1) }
                        if value.1 > 0, positiveTotal > 0 { Rectangle().fill(Color.primary.opacity(max(0.18, 0.95 - Double(index) * 0.07))).frame(width: geo.size.width * CGFloat(NSDecimalNumber(decimal: value.1 / positiveTotal).doubleValue)) }
                    }
                }.clipShape(Capsule())
            }.frame(height: 14).accessibilityHidden(true)
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                if value.1 != 0 { HStack { Circle().fill(Color.primary.opacity(max(0.18, 0.95 - Double(index) * 0.07))).frame(width: 9, height: 9); detailLine(value.0, usd(value.1)) } }
            }
        }
    }
    var itineraryCard: some View {
        surface {
            sectionTitle(copy("Расписание путешествия", "Trip schedule", "Safar jadvali", "Сафар жадвали"))
            TripSummaryCalendar(trip: journey.trip, quote: journey.hasFinalGeneratorQuote ? journey.quote : nil, outbound: journey.selectedOutbound, inbound: journey.selectedInbound, language: settings.language)
        }
    }
    var conditionsCard: some View {
        surface {
            disclosure("booking-terms", copy("Условия бронирования", "Booking terms", "Bron shartlari", "Брон шартлари")) { Text(copy("После заявки мы проверяем наличие. Оплата после подтверждения. Сначала оформляем визы, затем покупаем авиабилеты.", "We check availability after your request. Pay after confirmation. Visas first, then ticket purchase.", "Arizadan keyin mavjudlik tekshiriladi. Tasdiqdan keyin to‘lov. Avval viza, keyin chipta.", "Аризадан кейин мавжудлик текширилади. Тасдиқдан кейин тўлов. Аввал виза, кейин чипта.")).font(.subheadline) }
            Divider()
            disclosure("refund-terms", copy("Условия отмены и возврата", "Cancellation and refunds", "Bekor qilish va qaytarish", "Бекор қилиш ва қайтариш")) {
                ForEach([IumrahRefundComponent.flight, .hotel, .transfer, .services]) { item in
                    Text(item.title(settings.language)).font(.subheadline.bold()); Text(item.summary(settings.language)).font(.caption).foregroundStyle(.secondary)
                }
                Text(copy("Визы: полный возврат до подачи заявки. После подачи — без возврата. Комиссии — по применимым условиям.", "Visas: full refund before submission; non-refundable after submission. Fees subject to applicable terms.", "Viza: ariza topshirilguncha to‘liq qaytariladi, keyin qaytarilmaydi. Komissiyalar tegishli shartlarga ko‘ra.", "Виза: ариза топширилгунча тўлиқ қайтарилади, кейин қайтарилмайди. Комиссиялар тегишли шартларга кўра.")).font(.caption)
            }
        }
    }
    var summaryTotalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("iumrah").font(.title2.bold())
            Text(copy("Итого за путешествие", "Trip total", "Safar jami", "Сафар жами")).font(.caption)
            Text(totalText).font(.largeTitle.bold()).monospacedDigit()
            if let q = journey.quote, journey.hasFinalGeneratorQuote, !isCalculatingPrice { Text(IumrahPackageDisplayPrices.money(q.pricePerPerson, currency: q.currency, language: settings.language) + " · " + copy("на паломника", "per pilgrim", "ziyoratchi uchun", "зиёратчи учун")).font(.subheadline) }
            Divider().overlay(.white.opacity(0.2))
            Label(copy("Индивидуальное обслуживание", "Private service", "Individual xizmat", "Индивидуал хизмат"), systemImage: "checkmark.circle")
            Label(copy("Поддержка на всех этапах", "Support at every stage", "Har bosqichda yordam", "Ҳар босқичда ёрдам"), systemImage: "checkmark.circle")
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(Color.black, in: RoundedRectangle(cornerRadius: 28))
    }
    var canSavePackage: Bool { journey.hasFinalGeneratorQuote && journey.quote?.bookingAllowed != false && publicPrice != nil && !isCalculatingPrice && !savingPackage && guestDraft == nil && priceChangeAccepted && roomsComplete && flightSelectionReady }
    var summaryActions: some View {
        VStack(spacing: 10) {
            Button { Task { await saveCurrentPackage() } } label: { Label(savedQuoteID == journey.quote?.quoteId && savedPackage != nil ? copy("Пакет сохранён", "Package saved", "Paket saqlandi", "Пакет сақланди") : copy("Сохранить пакет", "Save package", "Paketni saqlash", "Пакетни сақлаш"), systemImage: "bookmark") }.buttonStyle(IumrahSecondaryButtonStyle()).disabled(!canSavePackage)
            Button(copy("Забронировать путешествие", "Book journey", "Safarni bron qilish", "Сафарни брон қилиш")) { isProfileSheetPresented = true }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(!canBook || isSubmitting)
            Button { Task { await saveCurrentPackage(); if savedQuoteID == journey.quote?.quoteId, savedPackage != nil { prepareShareImage(); showSharePreview = true } } } label: { Label(copy("Сохранить и поделиться", "Save and share", "Saqlash va ulashish", "Сақлаш ва улашиш"), systemImage: "square.and.arrow.up") }.buttonStyle(IumrahSecondaryButtonStyle()).disabled(!canSavePackage)
            if savingPackage { ProgressView() }
            if let receipt = savedPackage, savedQuoteID == journey.quote?.quoteId { Text(receipt.packageID).font(.caption.monospaced()).foregroundStyle(.secondary) }
            Text(copy("Сначала подтверждаем наличие, затем оплата.", "Availability first, payment after confirmation.", "Avval mavjudlik, keyin to‘lov.", "Аввал мавжудлик, кейин тўлов.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
    var compactBookingBar: some View {
        VStack(spacing: 6) {
            HStack { Text(totalText).font(.title3.bold()).monospacedDigit(); Spacer(); if let q = journey.quote, journey.hasFinalGeneratorQuote, !isCalculatingPrice { Text(IumrahPackageDisplayPrices.money(q.pricePerPerson, currency: q.currency, language: settings.language) + " / " + copy("чел.", "person", "kishi", "киши")).font(.caption).foregroundStyle(.secondary) } }
            if !journey.transferSelectionConfirmed { Button(copy("Подтвердить трансфер", "Confirm transfer", "Transferni tasdiqlash", "Трансферни тасдиқлаш")) { editSession = TripSummaryEditSession(kind: .transfer, journey: journey) }.buttonStyle(IumrahPrimaryButtonStyle()) }
            else if !journey.hasFinalGeneratorQuote { Button(copy("Обновить расчёт", "Refresh price", "Narxni yangilash", "Нархни янгилаш")) { Task { await recalculatePrice() } }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(isCalculatingPrice) }
            else { Button(copy("Забронировать путешествие", "Book journey", "Safarni bron qilish", "Сафарни брон қилиш")) { isProfileSheetPresented = true }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(!canBook || isSubmitting) }
        }.padding(.horizontal, 18).padding(.vertical, 8).background(.regularMaterial)
    }
    @ViewBuilder func summaryEditor(_ session: TripSummaryEditSession) -> some View {
        NavigationStack {
            Group {
                switch session.kind {
                case .flights:
                    IumrahGuidedFlightSelectionView(smartConfirm: { commitEditor(session) })
                case .hotel(let city):
                    NuiteeJourneyHotelsView(transferAlreadySelected: true, smartCity: city, smartChildAges: session.ages, reviewEditing: true, smartConfirm: { commitEditor(session) })
                case .allHotels:
                    NuiteeJourneyHotelsView(transferAlreadySelected: true, smartChildAges: session.ages, reviewEditing: true, smartConfirm: { commitEditor(session) })
                case .catalog(let role):
                    HotelSelectionView(role: role)
                        .safeAreaInset(edge: .bottom) { Button(copy("Применить", "Apply", "Qo‘llash", "Қўллаш")) { commitEditor(session) }.buttonStyle(IumrahPrimaryButtonStyle()).padding() }
                case .transfer:
                    ScrollView { VStack(spacing: 14) {
                        ForEach(TransferVehicleKind.allCases) { vehicle in
                            Button { session.draft.chooseTransferVehicle(vehicle); session.draft.confirmTransferSelection(); commitEditor(session) } label: {
                                HStack { Image(vehicle.assetName).resizable().scaledToFit().frame(width: 105, height: 70); VStack(alignment: .leading) { Text(vehicle.modelName).font(.headline); Text("\(vehicle.passengerCapacity) · " + copy("мест", "seats", "o‘rin", "ўрин")).font(.caption) }; Spacer(); Image(systemName: "chevron.right") }.padding(14).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain).disabled(vehicle.passengerCapacity < session.draft.trip.travelerCount)
                        }
                    }.padding(18) }
                }
            }.environmentObject(session.draft)
            .safeAreaInset(edge: .top) { HStack { Button(copy("Закрыть", "Close", "Yopish", "Ёпиш")) { editSession = nil }; Spacer() }.padding(12).background(.regularMaterial) }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }
    func commitEditor(_ session: TripSummaryEditSession) {
        beginPriceChange()
        journey.applyTripSummaryEditor(session)
        editSession = nil
        if session.kind == .flights, journey.usesLocalJourney, !journey.localRoomsComplete { editSession = TripSummaryEditSession(kind: .allHotels, journey: journey) }
    }
    @MainActor func saveCurrentPackage() async {
        guard canSavePackage, let q = journey.quote, let hotel = journey.selectedHotel, let out = journey.selectedOutbound else { return }
        if savedQuoteID == q.quoteId, savedPackage != nil { return }
        savingPackage = true; errorMessage = nil
        defer { savingPackage = false }
        do {
            let credential = try ownerCredential ?? TripSummaryOwnerCredential.create()
            ownerCredential = credential
            let payload = BookingDraftBuilder.make(trip: journey.trip, hotel: hotel, madinahHotel: journey.selectedMadinahHotel, room: journey.selectedRoom, roomCategory: journey.selectedRoomCategory, madinahRoom: journey.selectedMadinahRoom, madinahRoomCategory: journey.selectedMadinahRoomCategory, intercityTransport: needsMadinah ? (journey.haramainTrainSelected ? .haramainTrain : .road) : nil, outbound: out, inbound: journey.selectedInbound, quote: q, language: settings.language, pilgrimProfile: nil, nuiteeRooms: journey.usesLocalJourney ? journey.localBookingRooms : nil)
            guard let price = q.tripSummary else { throw APIError.invalidResponse }
            let receipt = try await TripSummarySavedClient.save(payload, credential: credential, previous: savedPackage, price: price)
            savedPackage = receipt
            credential.recordDraft(TripSummaryLocalDraft(journey: journey), packageID: receipt.packageID)
            savedQuoteID = q.quoteId
            IumrahHaptics.success()
        } catch { errorMessage = L10n.error(error, settings.language) }
    }
    var packageSupportSheet: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 18) {
            Text(copy("iumrah Поддержка", "iumrah Support", "iumrah Yordam", "iumrah Ёрдам")).font(.title.bold())
            if let receipt = savedPackage, savedQuoteID == journey.quote?.quoteId {
                if let credential = ownerCredential {
                    let request = adultExceptionRequested ? copy("Здравствуйте! Хотим разместить \(journey.trip.adults) взрослых в одном номере без добавления дополнительного номера. Проверьте, пожалуйста, возможность в выбранных отелях.", "Hello! We would like to accommodate \(journey.trip.adults) adults in one room without adding another room. Please check availability at the selected hotels.", "Salom! \(journey.trip.adults) kattani qo‘shimcha xonasiz bitta xonaga joylashtirish imkonini tekshiring.", "Салом! \(journey.trip.adults) каттани қўшимча хонасиз битта хонага жойлаштириш имконини текширинг.") : ""
                    SavedPackageThreadView(receipt: receipt, credential: credential, initialMessage: request, requestedRooms: adultExceptionRequested ? max(1, journey.trip.rooms - 1) : nil)
                }
            } else {
                Text(copy("Сначала сохраните путешествие", "Save your journey first", "Avval safarni saqlang", "Аввал сафарни сақланг")).font(.headline)
                if let draft = guestDraft {
                    Text(copy("Сначала примените состав паломников и получите актуальный расчёт.", "Apply your guest changes and obtain a current quote first.", "Avval tarkibni qo‘llang va narxni hisoblang.", "Аввал таркибни қўлланг ва нархни ҳисобланг.")).font(.caption)
                    Button(copy("Применить и пересчитать", "Apply and reprice", "Qo‘llash va hisoblash", "Қўллаш ва ҳисоблаш")) { showPackageSupport = false; applyGuests(draft) }.buttonStyle(IumrahSecondaryButtonStyle()).disabled(draft.ages.contains(where: { $0 < 0 }))
                }
                Button(copy("Сохранить пакет", "Save package", "Paketni saqlash", "Пакетни сақлаш")) { Task { await saveCurrentPackage() } }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(!canSavePackage || guestDraft != nil)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
        }.padding(20) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy("Закрыть", "Close", "Yopish", "Ёпиш")) { showPackageSupport = false } } } }
    }
    @MainActor func prepareShareImage() {
        shareImageURL = nil
        let artwork = VStack(alignment: .leading, spacing: 22) {
            Text("iumrah").font(.system(size: 42, weight: .bold, design: .rounded))
            Image("AboutIumrahKaabaCorner").resizable().scaledToFill().frame(width: 480, height: 220).clipped().clipShape(RoundedRectangle(cornerRadius: 22))
            Text(copy("Индивидуальная умра", "Individual Umrah", "Individual umra", "Индивидуал умра")).font(.system(size: 32, weight: .bold, design: .rounded))
            Text(dateRange(journey.trip.departureDate, journey.trip.returnDate)).font(.title3)
            Text(partyText).font(.title3)
            Divider().overlay(Color.white.opacity(0.3))
            Text(totalText).font(.system(size: 48, weight: .bold, design: .rounded))
            Text("iumrah.app").font(.headline)
        }.padding(32).frame(width: 544, alignment: .leading).foregroundStyle(Color.white).background(Color.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("iumrah-\(UUID().uuidString).png")
        do { try data.write(to: url, options: .atomic); shareImageURL = url } catch { shareImageURL = nil }
    }
    var savedShareSheet: some View {
        NavigationStack { ScrollView { VStack(spacing: 16) {
            summaryTotalCard
            if let receipt = savedPackage {
                Text(receipt.packageID).font(.caption.monospaced())
                if let raw = receipt.shareURL, let url = URL(string: raw) {
                    if let shareImageURL { PackageNativeShareButton(items: [shareImageURL, url], title: copy("Поделиться путешествием", "Share journey", "Safarni ulashish", "Сафарни улашиш")) }
                    ShareLink(item: url) { Label(copy("Поделиться ссылкой", "Share link", "Havolani ulashish", "Ҳаволани улашиш"), systemImage: "link") }
                } else { Text(copy("Ссылка недоступна. Повторите сохранение.", "Link unavailable. Save again.", "Havola mavjud emas.", "Ҳавола мавжуд эмас.")).font(.caption) }
            }
        }.padding(20) }.toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy("Закрыть", "Close", "Yopish", "Ёпиш")) { showSharePreview = false } } } }
    }
}
