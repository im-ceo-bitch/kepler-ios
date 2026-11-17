import SwiftUI

/// Package selection uses the same Nuitee detail/rate UI as the Hotels tab.
struct NuiteeJourneyHotelsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var journey: JourneyStore
    var transferAlreadySelected = false
    var smartCity: String? = nil
    var smartConfirm: (() -> Void)? = nil

    init(transferAlreadySelected: Bool = false, smartCity: String? = nil, smartChildAges: [Int] = [], smartConfirm: (() -> Void)? = nil) {
        self.transferAlreadySelected = transferAlreadySelected
        self.smartCity = smartCity
        self.smartConfirm = smartConfirm
        _city = State(initialValue: smartCity ?? "makkah")
        _ages = State(initialValue: smartChildAges)
    }
    @State private var showFinalAfterHotels = false
    @State private var city = "makkah"
    @State private var roomIndex = 0
    @State private var stars = 0
    @State private var favorites: Set<String> = []
    @State private var nextOffset: Int?
    @State private var total = 0
    @State private var loadingMore = false
    @State private var pageError = false
    @State private var hotels: [NuiteeHotel] = []
    @State private var hotelRevision = 0
    @State private var loadedSearchID: String?
    private struct HotelFilterKey: Equatable { let revision: Int; let stars: Int }
    @State private var hotelMemo = IumrahViewMemo<HotelFilterKey, [NuiteeHotel]>()
    @State private var sandbox = false
    @State private var loading = false
    @State private var error: String?
    @State private var opened: NuiteeHotel?
    @State private var showTransfer = false
    @State private var advanceAfterRoomSelection = false
    @State private var selectedMeals = HotelMealChoices()
    @State private var ages: [Int] = []
    @State private var requestID = UUID()
    private let service = NuiteeHotelService()

    private var window: TripStayWindow {
        let windows = TripStayPlanner.windows(for: journey.trip)
        return city == "madinah" ? (windows.madinah ?? windows.makkah) : windows.makkah
    }
    private var key: String { "\(city):\(roomIndex)" }
    private var roomAdults: Int {
        journey.trip.adults / max(1, journey.trip.rooms) + (roomIndex < journey.trip.adults % max(1, journey.trip.rooms) ? 1 : 0)
    }
    private var roomChildren: [Int] { ages.enumerated().filter { $0.offset % max(1, journey.trip.rooms) == roomIndex }.map(\.element) }
    private var ready: Bool { ages.count == journey.trip.children + journey.trip.infants && !ages.contains(-1) && roomAdults > 0 }
    private var filtered: [NuiteeHotel] {
        guard loadedSearchID == searchID else { return [] }
        return hotelMemo.value(for: HotelFilterKey(revision: hotelRevision, stars: stars)) {
            hotels.filter { stars == 0 || $0.roundedStars == stars }
        }
    }
    private var searchID: String { "\(city):\(roomAdults):\(window.checkIn):\(window.checkOut):\(stars)" }

    var body: some View {
        let results = filtered
        let stay = window
        let adults = roomAdults
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 18) {
                IumrahJourneyHeader {
                    IumrahJourneyDisclosureCard(title: "Отели и номера", total: "\(journey.trip.travelerCount) чел. · \(journey.trip.rooms) ном.",
                        subtitle: "\(window.checkIn.formatted(date: .abbreviated, time: .omitted)) — \(window.checkOut.formatted(date: .abbreviated, time: .omitted)) · \(roomAdults) взр. · \(roomChildren.count) дет.",
                        priceCaption: "Состав поездки") {
                        if smartCity == nil {
                        Stepper("Номера: \(journey.trip.rooms)", value: $journey.trip.rooms, in: 1...journey.trip.adults)
                        ForEach(ages.indices, id: \.self) { index in
                            Picker("Возраст ребёнка \(index + 1)", selection: $ages[index]) {
                                Text("Укажите возраст").tag(-1)
                                ForEach(0...17, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                        } else {
                            Text(city == "makkah" ? "Мекка" : "Медина").font(.headline)
                        }
                    }
                }
                .id("hotels-top")
                LazyVStack(alignment: .leading, spacing: 14) {
                    IumrahPageHelpCard(!ready ? "hotels.child_ages" : journey.localRoomsComplete ? "hotels.complete" : journey.trip.rooms > 1 ? "hotels.multiple_rooms" : city == "madinah" ? "hotels.madinah" : "hotels.makkah")
                    if smartCity == nil && journey.trip.scope == .makkahAndMadinah {
                        Picker("Город", selection: $city) {
                            Text("Мекка").tag("makkah")
                            Text("Медина").tag("madinah")
                        }.pickerStyle(.segmented)
                    }
                    if journey.trip.rooms > 1 {
                        Picker("Номер", selection: $roomIndex) {
                            ForEach(0..<journey.trip.rooms, id: \.self) { Text("Номер \($0 + 1)").tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    Picker("Звёзды", selection: $stars) {
                        Text("Все").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) ★").tag($0) }
                    }.pickerStyle(.segmented)
                    if !ready { Text("Раскройте карточку сверху и укажите возраст детей для точного тарифа.").font(.footnote) }
                    if let selection = journey.localJourneyRooms[key] {
                        Label(selection.hotel.name + " · " + selection.rate.roomName, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Color.iumrahJourneyGreen)
                        Text(NuiteeHotelService.usd(selection.rate.price) + " · " + NuiteeCopy.text("ориентировочно за номер, весь срок", "butun muddat uchun xona narxi, taxminan", "estimated per room, entire stay", settings.language)).font(.caption)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if error != nil { Text(NuiteeCopy.text("Не удалось проверить наличие", "Mavjudlikni tekshirib bo‘lmadi", "Could not check availability", settings.language)).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(results) { hotel in
                        NuiteeHotelListingCard(hotel: hotel, nights: stay.nights, adults: adults, sandbox: sandbox,
                            favorite: favorites.contains(hotel.id), onOpen: { if ready { opened = hotel } }, onFavorite: {
                                if favorites.contains(hotel.id) { favorites.remove(hotel.id) } else { favorites.insert(hotel.id) }
                            })

                    }
                    IumrahHotelPageButton(remaining: max(0, total - hotels.count), loading: loadingMore, failed: pageError, hasMore: nextOffset != nil && loadedSearchID == searchID) {
                        Task { await loadMore() }
                    }
                    if !loading && results.isEmpty && error == nil { Text("На эти даты отели не найдены.").foregroundStyle(.secondary) }
                    if !loading && error != nil { Button(NuiteeCopy.text("Повторить", "Qayta urinish", "Retry", settings.language)) { Task { await load(forceRefresh: true) } }.buttonStyle(IumrahSecondaryButtonStyle()) }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
        .onChange(of: key) { _, _ in proxy.scrollTo("hotels-top", anchor: .top) }
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .modifier(IumrahJourneyRefresh {
            await journey.refreshLocalJourneyRoomRates()
            await load(forceRefresh: true)
        })
        .task(id: searchID) { await load() }
        .onAppear {
            if smartCity == nil && ages.count != journey.trip.children + journey.trip.infants {
                ages = Array(repeating: -1, count: journey.trip.children + journey.trip.infants)
            }
        }
        .onChange(of: journey.trip.rooms) { _, _ in invalidateRooms() }
        .onChange(of: ages) { _, _ in if smartCity == nil { journey.localJourneyRooms = [:]; journey.quote = nil } }
        .navigationDestination(item: $opened) { hotel in
            NuiteeHotelDetailView(hotel: hotel, checkin: window.checkIn, nights: window.nights,
                adults: roomAdults, sandbox: sandbox, childrenAges: roomChildren, onSelectRate: { rate in
                    guard rate.currency == "USD", rate.price.isFinite, rate.price > 0 else { return }
                    // A canonical booking has one hotel per city; changing it resets that city's room choices.
                    journey.localJourneyRooms = journey.localJourneyRooms.filter { $0.value.city != city || $0.value.hotel.id == hotel.id }
                    journey.localJourneyRooms[key] = LocalJourneyRoom(id: key, city: city, hotel: hotel, rate: rate,
                        checkin: window.checkIn, checkout: window.checkOut, adults: roomAdults, childrenAges: roomChildren, meals: selectedMeals)
                    if let tier = journey.localPackageTier { journey.trip.packageTier = tier }
                    if !transferAlreadySelected { journey.transferSelectionConfirmed = false }
                    journey.invalidateLocalJourneyQuote()
                    advanceAfterRoomSelection = true
                }, onSelectMeals: { selectedMeals = $0 })
                .onDisappear {
                    guard advanceAfterRoomSelection else { return }
                    advanceAfterRoomSelection = false
                    advanceToNextSelection()
                }
        }
        .navigationDestination(isPresented: $showTransfer) { TransferSelectionView() }
        .navigationDestination(isPresented: $showFinalAfterHotels) { FinalPackageView() }
        .safeAreaInset(edge: .bottom) {
            if journey.localRoomsComplete {
                Button(smartCity != nil ? IumrahFlightCopy.text(settings.language, "Подтвердить отель", "Confirm hotel", "Mehmonxonani tasdiqlash", "Меҳмонхонани тасдиқлаш") : transferAlreadySelected ? "Посмотреть итог" : "Выбрать трансфер") { finishRooms() }
                    .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private func advanceToNextSelection() {
        // Advance only after the detail view has popped. Never mutate its city/date bindings mid-dismissal.
        let cities = smartCity.map { [$0] } ?? (journey.trip.scope == .makkahAndMadinah ? ["makkah", "madinah"] : ["makkah"])
        let orderedCities = [city] + cities.filter { $0 != city }
        for nextCity in orderedCities {
            if let nextRoom = (0..<journey.trip.rooms).first(where: { journey.localJourneyRooms["\(nextCity):\($0)"] == nil }) {
                city = nextCity
                roomIndex = nextRoom
                stars = 0
                return
            }
        }
        if journey.localRoomsComplete && smartCity == nil { finishRooms() }
    }

    private func finishRooms() {
        journey.invalidateLocalJourneyQuote()
        if let smartConfirm { smartConfirm(); return }
        if transferAlreadySelected { journey.confirmTransferSelection(); showFinalAfterHotels = true }
        else { showTransfer = true }
    }

    private func invalidateRooms() {
        roomIndex = 0
        journey.localJourneyRooms = [:]
        journey.quote = nil
        journey.transferSelectionConfirmed = false
    }
    @MainActor private func load(forceRefresh: Bool = false) async {
        if !forceRefresh, loadedSearchID == searchID, error == nil { return }
        let trace = IumrahPerformanceTrace.begin("Journey hotel load")
        defer { IumrahPerformanceTrace.end("Journey hotel load", trace) }
        let token = UUID(); requestID = token
        let requestedSearchID = searchID
        loading = true; loadingMore = false; pageError = false; error = nil
        if loadedSearchID != requestedSearchID { hotels = []; nextOffset = nil; total = 0; hotelRevision &+= 1; loadedSearchID = nil }
        defer { if requestID == token { loading = false } }
        do {
            let response = try await service.hotelPage(city: city, checkin: window.checkIn, checkout: window.checkOut, adults: max(1, roomAdults), stars: stars)
            guard requestID == token, searchID == requestedSearchID, !Task.isCancelled else { return }
            hotels = response.hotels; nextOffset = response.nextOffset; total = response.total ?? hotels.count; hotelRevision &+= 1; loadedSearchID = requestedSearchID; sandbox = response.sandbox
            error = response.rateError
        } catch {
            guard requestID == token, searchID == requestedSearchID, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            if loadedSearchID == requestedSearchID {
                hotels = hotels.map { hotel in var row = hotel; row.minimumRate = nil; row.rateStatus = "provider_error"; return row }; hotelRevision &+= 1
            }
        }
    }
    @MainActor private func loadMore() async {
        guard !loading, !loadingMore, let offset = nextOffset, loadedSearchID == searchID else { return }
        let token = requestID; let identity = searchID
        loadingMore = true; pageError = false
        defer { if requestID == token { loadingMore = false } }
        do {
            let response = try await service.hotelPage(city: city, checkin: window.checkIn, checkout: window.checkOut, adults: max(1, roomAdults), stars: stars, offset: offset)
            guard requestID == token, searchID == identity, !Task.isCancelled else { return }
            var ids = Set(hotels.map(\.id)); hotels += response.hotels.filter { ids.insert($0.id).inserted }
            hotelRevision &+= 1; nextOffset = response.nextOffset; total = response.total ?? hotels.count
        } catch { if requestID == token && !Task.isCancelled { pageError = true } }
    }

}
