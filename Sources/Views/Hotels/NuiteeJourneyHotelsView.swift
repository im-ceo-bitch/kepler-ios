import SwiftUI

/// Package selection uses the same Nuitee detail/rate UI as the Hotels tab.
struct NuiteeJourneyHotelsView: View {
    @EnvironmentObject private var journey: JourneyStore
    @State private var city = "makkah"
    @State private var roomIndex = 0
    @State private var stars = 0
    @State private var favorites: Set<String> = []
    @State private var visibleCount = 20
    @State private var hotels: [NuiteeHotel] = []
    @State private var sandbox = false
    @State private var loading = false
    @State private var error: String?
    @State private var opened: NuiteeHotel?
    @State private var showTransfer = false
    @State private var ages: [Int] = []
    @State private var requestID = UUID()
    private let service = NuiteeHotelService()

    private var window: TripStayWindow {
        let windows = TripStayPlanner.windows(for: journey.trip)
        return city == "madinah" ? (windows.madinah ?? windows.makkah) : windows.makkah
    }
    private var key: String { "\(city):\(roomIndex)" }
    private var roomAdults: Int {
        journey.trip.adults / journey.trip.rooms + (roomIndex < journey.trip.adults % journey.trip.rooms ? 1 : 0)
    }
    private var roomChildren: [Int] { ages.enumerated().filter { $0.offset % journey.trip.rooms == roomIndex }.map(\.element) }
    private var ready: Bool { ages.count == journey.trip.children + journey.trip.infants && !ages.contains(-1) && roomAdults > 0 }
    private var filtered: [NuiteeHotel] { hotels.filter { stars == 0 || $0.roundedStars == stars } }
    private var searchID: String { "\(city):\(roomAdults):\(window.checkIn):\(window.checkOut)" }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                IumrahJourneyHeader {
                    IumrahJourneyDisclosureCard(title: "Отели и номера", total: "\(journey.trip.travelerCount) чел. · \(journey.trip.rooms) ном.",
                        subtitle: "\(journey.trip.hotelStayStartDate.formatted(date: .abbreviated, time: .omitted)) — \(journey.trip.returnDate.formatted(date: .abbreviated, time: .omitted))",
                        priceCaption: "Состав поездки") {
                        Stepper("Номера: \(journey.trip.rooms)", value: $journey.trip.rooms, in: 1...journey.trip.adults)
                        ForEach(ages.indices, id: \.self) { index in
                            Picker("Возраст ребёнка \(index + 1)", selection: $ages[index]) {
                                Text("Укажите возраст").tag(-1)
                                ForEach(0...17, id: \.self) { Text("\($0)").tag($0) }
                            }
                        }
                    }
                }
                LazyVStack(alignment: .leading, spacing: 14) {
                    if journey.trip.scope == .makkahAndMadinah {
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
                    Text("\(window.checkIn.formatted(date: .abbreviated, time: .omitted)) — \(window.checkOut.formatted(date: .abbreviated, time: .omitted)) · \(roomAdults) взр. · \(roomChildren.count) дет.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Звёзды", selection: $stars) {
                        Text("Все").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) ★").tag($0) }
                    }.pickerStyle(.segmented)
                    if !ready { Text("Раскройте карточку сверху и укажите возраст детей для точного тарифа.").font(.footnote) }
                    if let selection = journey.localJourneyRooms[key] {
                        Label(selection.hotel.name + " · " + selection.rate.roomName, systemImage: "checkmark.circle.fill")
                            .font(.subheadline).foregroundStyle(Color.iumrahJourneyGreen)
                        Text(NuiteeHotelService.usd(selection.rate.price) + " · за номер, весь срок").font(.caption)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    ForEach(Array(filtered.prefix(visibleCount))) { hotel in
                        NuiteeHotelListingCard(hotel: hotel, nights: window.nights, adults: roomAdults, sandbox: sandbox,
                            favorite: favorites.contains(hotel.id), onOpen: { if ready { opened = hotel } }, onFavorite: {
                                if favorites.contains(hotel.id) { favorites.remove(hotel.id) } else { favorites.insert(hotel.id) }
                            })
                            .onAppear { if hotel.id == filtered.prefix(visibleCount).last?.id { visibleCount += 20 } }
                    }
                    if !loading && filtered.isEmpty { Text("На эти даты отели не найдены.").foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
        .background(Color.iumrahPageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .modifier(IumrahJourneyRefresh {
            await journey.refreshLocalJourneyRoomRates()
            await load()
        })
        .task(id: searchID) { await load() }
        .onAppear {
            if ages.count != journey.trip.children + journey.trip.infants {
                ages = Array(repeating: -1, count: journey.trip.children + journey.trip.infants)
            }
        }
        .onChange(of: journey.trip.rooms) { _, _ in invalidateRooms() }
        .onChange(of: ages) { _, _ in journey.localJourneyRooms = [:]; journey.quote = nil }
        .onChange(of: stars) { _, _ in visibleCount = 20 }
        .navigationDestination(item: $opened) { hotel in
            NuiteeHotelDetailView(hotel: hotel, checkin: window.checkIn, nights: window.nights,
                adults: roomAdults, sandbox: sandbox, childrenAges: roomChildren, onSelectRate: { rate in
                    guard rate.currency == "USD", rate.price.isFinite, rate.price > 0 else { return }
                    journey.localJourneyRooms[key] = LocalJourneyRoom(id: key, city: city, hotel: hotel, rate: rate,
                        checkin: window.checkIn, checkout: window.checkOut, adults: roomAdults, childrenAges: roomChildren)
                    journey.transferSelectionConfirmed = false
                    journey.rebuildLocalJourneyQuote()
                })
        }
        .navigationDestination(isPresented: $showTransfer) { TransferSelectionView() }
        .safeAreaInset(edge: .bottom) {
            if journey.localRoomsComplete {
                Button("Выбрать трансфер") { journey.rebuildLocalJourneyQuote(); showTransfer = true }
                    .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
    }

    private func invalidateRooms() {
        roomIndex = 0
        journey.localJourneyRooms = [:]
        journey.quote = nil
        journey.transferSelectionConfirmed = false
    }
    @MainActor private func load() async {
        let token = UUID(); requestID = token
        loading = true; error = nil; visibleCount = 20
        do {
            let response = try await service.hotels(city: city, checkin: window.checkIn, checkout: window.checkOut, adults: max(1, roomAdults))
            guard requestID == token, !Task.isCancelled else { return }
            hotels = response.hotels; sandbox = response.sandbox
            error = response.rateError
        } catch {
            guard requestID == token, !Task.isCancelled else { return }
            hotels = []; self.error = error.localizedDescription
        }
        if requestID == token { loading = false }
    }
}
