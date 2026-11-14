import SwiftUI

/// A fresh public discovery surface. Legacy hotel storefront/package helper
/// components remain available below for existing deep links, never displayed
/// as an alternative supplier catalogue on this root tab.
struct HotelsHomeView: View {
    private enum Discovery: Int { case hotels, flights, weekends, transfer, summary }

    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var manual: IumrahManualJourneyStore
    @State private var browseTrip = TripDraft()
    @State private var requestedFlightDay: String?
    @State private var requestedSaudiAirport: String?
    @State private var openedManualFlight: LocalJourneyFlight?
    @State private var selectionMessage: String?
    @State private var pendingFlight: LocalJourneyFlight?
    @State private var noticeTask: Task<Void, Never>?
    @State private var noticeRevision = 0
    @State private var flightSearchRevision = 0
    @EnvironmentObject private var storefront: HotelStorefrontStore

    @State private var mode: Discovery = .hotels
    @State private var hotelCity = "makkah"
    @State private var hotelName = ""
    @State private var hotelCheckin = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var hotelNights = 7
    @State private var hotelRooms = 1
    @State private var hotelAdults = 2
    @State private var hotelChildren = 0
    @State private var childAges: [Int] = []
    @State private var hotelRequest: IumrahHotelTabSearch? = IumrahHotelTabSearch(
        city: "makkah", checkin: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
        nights: 7, adults: 2)
    @State private var hotelSearchRevision = 0
    @State private var showHotelResults = true
    @State private var searchExpanded = false
    @State private var flightDirection = 0
    @StateObject private var hotelCatalog = NuiteeCatalogModel()
    @State private var manualHotelLimit = 20
    @StateObject private var flightCatalog = IumrahFlightBrowseModel()
    @State private var appliedHotelName = ""
    @State private var manualQuoteRequired = false
    @State private var manualHotels: [NuiteeHotel] = []
    @State private var manualHotelsBusy = false
    @State private var manualHotelsError: String?
    @State private var manualHotelsRequestID = UUID()

    @State private var flightDestination: SaudiArrivalAirport = .jeddah
    @State private var flightDeparture = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var flightReturn = Calendar.current.date(byAdding: .day, value: 21, to: Date()) ?? Date()
    @State private var flightAdults = 2
    @State private var flightCabin: FlightCabinClass = .economy
    @State private var weekendDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var weekendNights = 3
    @State private var selectedLegacyPackage: StorefrontFlightPackagePreview?

    private var modes: [String] {
        [copy("Отели", "Hotels", "Mehmonxonalar", "Меҳмонхоналар"),
         copy("Авиабилеты", "Flights", "Aviachiptalar", "Авиачипталар"),
         copy("Выходные", "Weekends", "Dam olish", "Дам олиш"),
         copy("Трансфер", "Transfer", "Transfer", "Трансфер"),
         copy("Мой пакет", "My package", "Mening paketim", "Менинг пакетим")]
    }

    private var matchingPairID: String? {
        let other = flightDirection == 0 ? manual.inbound : manual.outbound
        return other?.publishedIsPair == true ? other?.publishedID : nil
    }

    private var fixedHeader: some View {
        IumrahDiscoveryMasthead(selection: mode == .hotels ? 1 : mode == .transfer ? 3 : mode == .summary ? 4 : 2)
    }

    var body: some View {
        IumrahRootScrollingPage(onRefresh: { await refreshSearch() }, searchCardOverlap: 40, extendsUnderStatusBar: true, helpContext: mode == .transfer ? "transfer.default" : mode == .summary ? "review.local" : mode == .hotels ? (manualQuoteRequired ? "discovery.family" : "discovery.hotels") : mode == .weekends ? "discovery.weekends" : "discovery.flights", header: {
            fixedHeader
        }, content: {
            LazyVStack(alignment: .leading, spacing: 0) {
                if mode == .transfer {
                    IumrahManualTransferCatalog()
                } else if mode == .summary {
                    IumrahManualPackageView()
                } else {
                IumrahGraphiteSearchSurface(
                    isExpanded: $searchExpanded,
                    summary: mode == .hotels
                        ? copy("Поиск отелей", "Hotel search", "Mehmonxona qidirish", "Меҳмонхона қидириш") : modes[mode.rawValue],
                    subtitle: mode == .hotels
                        ? "\((hotelRequest?.checkin ?? hotelCheckin).formatted(date: .abbreviated, time: .omitted)) · \(hotelRequest?.nights ?? hotelNights) " + copy("ночей", "nights", "tun", "тун")
                        : copy("Даты и пассажиры", "Dates and passengers", "Sanalar va yo‘lovchilar", "Саналар ва йўловчилар")
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        switch mode {
                        case .hotels: hotelFields
                        case .flights: flightFields
                        case .weekends: weekendFields
                        case .transfer, .summary: EmptyView()
                        }
                        searchAction
                    }
                }
                .padding(.horizontal, IumrahDesign.pagePadding)
                .padding(.top, -40)
                .padding(.bottom, 20)

                if mode == .hotels && (!manual.routeConfigured || manual.scope == .makkahAndMadinah) {
                    Picker("City", selection: $hotelCity) {
                        Text(copy("Мекка", "Makkah", "Makka", "Макка")).tag("makkah")
                        Text(copy("Медина", "Madinah", "Madina", "Мадина")).tag("madinah")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .padding(.top, 0)
                    .padding(.bottom, 16)
                }
                if mode != .hotels {
                    Picker("Direction", selection: $flightDirection) {
                        Text(copy("Туда", "Outbound", "Borish", "Бориш")).tag(0)
                        Text(copy("Обратно", "Return", "Qaytish", "Қайтиш")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .padding(.bottom, 16)
                }

                if mode == .hotels && showHotelResults {
                    if manualQuoteRequired {
                        manualHotelQuote
                        manualHotelList
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            NuiteeHotelsCatalogView(
                                refreshSignal: hotelSearchRevision,
                                initialHotelQuery: appliedHotelName,
                                searchOverride: hotelRequest,
                                showsSearchControls: false, model: hotelCatalog, onManualRoom: { room in
                                    guard manual.select(room) else { return }
                                    showNotice(copy("Отель добавлен в ваш пакет", "Hotel added to your package", "Mehmonxona paketingizga qo‘shildi", "Меҳмонхона пакетингизга қўшилди"))
                                    IumrahHaptics.success()
                                }
                            )
                        }
                        .padding(.horizontal, IumrahDesign.pagePadding)
                    }
                } else if mode == .hotels {
                    discoveryPrompt(
                        icon: "building.2.crop.circle",
                        title: copy("Ваш отель в Саудовской Аравии", "Find your Saudi stay", "Saudiya mehmonxonangiz", "Саудия меҳмонхонангиз"),
                        detail: copy("Выберите город, даты, состав гостей и нажмите «Найти отели». Результаты загружаются через Nuitee.",
                                     "Choose a city, dates and guests. Hotel results come from Nuitee.",
                                     "Shahar, sana va mehmonlarni tanlang. Natijalar Nuitee’dan keladi.",
                                     "Шаҳар, сана ва меҳмонларни танланг. Натижалар Nuitee’дан келади.")
                    )
                } else {
                    IumrahFlightBrowseCatalog(direction: flightDirection, refreshSignal: flightSearchRevision, model: flightCatalog,
                        tripOverride: browseTrip, requestedDay: requestedFlightDay, requestedSaudiAirport: requestedSaudiAirport,
                        selectedID: pendingFlight?.id ?? (flightDirection == 0 ? manual.outbound?.id : manual.inbound?.id),
                        pairedContextID: matchingPairID,
                        onAdd: { flight in
                            IumrahHaptics.selection()
                            withAnimation(.easeInOut(duration: 0.2)) { pendingFlight = pendingFlight?.id == flight.id ? nil : flight }
                        }, onSelectionContextChange: { pendingFlight = nil }) { flight in
                        openedManualFlight = flight
                    }
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .tint(Color.primary)
                }
                }
            }
            .padding(.bottom, 115)
        })
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if (mode == .flights || mode == .weekends) && openedManualFlight == nil {
                flightConfirmationBar
            } else if mode == .hotels && manual.componentCount > 0 {
                Button(copy("Мой пакет", "My package", "Mening paketim", "Менинг пакетим")) { chrome.openHotels(board: .summary) }
                    .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
            }
        }
        .overlay(alignment: .top) {
            if let selectionMessage {
                HStack(spacing: 10) {
                    if #available(iOS 18.0, *) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                            .symbolEffect(.bounce, value: noticeRevision)
                    } else { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green) }
                    Text(selectionMessage).font(.subheadline.weight(.semibold))
                }.padding(14).background(.regularMaterial, in: Capsule())
                    .padding(.top, 12).padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
            }
        }
        .navigationDestination(item: $openedManualFlight) { flight in
            IumrahManualFlightDetail(flight: flight, onConfirm: { addManualFlight(flight) })
        }
        .navigationDestination(item: $selectedLegacyPackage) { package in
            StorefrontUmrahPackageDetailView(preview: package)
        }
        .onAppear {
            applyRequestedBoard()
            applyRequestedHotelSearch(chrome.requestedHotelTabSearch)
            openRequestedPackage(chrome.requestedPackageID)
        }
        .onChange(of: chrome.requestedHotelsBoard) { _, _ in applyRequestedBoard() }
        .onChange(of: chrome.manualBoardRevision) { _, _ in applyRequestedBoard() }
        .onChange(of: manual.scope) { _, scope in
            pendingFlight = nil
            if scope == .makkahOnly {
                flightDestination = .jeddah
                requestedSaudiAirport = "JED"
                if mode == .hotels && hotelCity != "makkah" { hotelCity = "makkah" }
            }
            if scope == .makkahAndMadinah { requestedSaudiAirport = nil }
            browseTrip.scope = scope
        }
        .onChange(of: mode) { _, _ in pendingFlight = nil }
        .onChange(of: flightSearchRevision) { _, _ in pendingFlight = nil }
        .onChange(of: chrome.requestedHotelTabSearch) { _, value in applyRequestedHotelSearch(value) }
        .onChange(of: chrome.requestedPackageID) { _, value in openRequestedPackage(value) }
        .onChange(of: hotelCity) { _, city in
            guard hotelRequest?.city != city else { return }
            let applied = hotelRequest
            if let window = manual.expectedWindow(city) {
                hotelCheckin = window.checkIn; hotelNights = window.nights
                hotelAdults = manual.adults
                hotelRequest = IumrahHotelTabSearch(city: city, checkin: window.checkIn, nights: window.nights, adults: manual.adults)
            } else {
                hotelRequest = IumrahHotelTabSearch(city: city,
                    checkin: applied?.checkin ?? hotelCheckin,
                    nights: applied?.nights ?? hotelNights, adults: applied?.adults ?? hotelAdults)
            }
            if manualQuoteRequired { Task { await loadManualHotelCatalog() } }
        }
        .onChange(of: hotelName) { _, _ in manualHotelLimit = 20 }
        .onChange(of: hotelChildren) { _, count in
            if count > childAges.count { childAges += Array(repeating: 6, count: count - childAges.count) }
            if count < childAges.count { childAges = Array(childAges.prefix(count)) }
        }
        .onChange(of: flightDirection) { _, _ in
            pendingFlight = nil
            flightDestination = SaudiArrivalAirport(rawValue: flightDirection == 0 ? manual.plannedTrip.outboundDestinationCode : manual.plannedTrip.returnOriginCode) ?? .jeddah
            if requestedFlightDay != nil { requestedSaudiAirport = flightDestination.rawValue; updateRequestedFlightDay(); flightSearchRevision += 1 }
        }
        .onChange(of: flightDeparture) { _, date in
            if flightReturn <= date {
                flightReturn = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
            }
        }
    }

    private var hotelFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel(copy("Название отеля (необязательно)", "Hotel name (optional)", "Mehmonxona nomi", "Меҳмонхона номи"))
                TextField(copy("Например, Hilton", "For example, Hilton", "Masalan, Hilton", "Масалан, Hilton"), text: $hotelName)
                    .textInputAutocapitalization(.words)
                    .padding(8)
                    .background(Color.iumrahPageBackground, in: RoundedRectangle(cornerRadius: 15))
            }
            Divider()
            DatePicker(copy("Заселение", "Check-in", "Kirish", "Кириш"), selection: $hotelCheckin, in: Date()..., displayedComponents: .date)
            Stepper(value: $hotelNights, in: 1...28) {
                Label("\(hotelNights) " + copy("ночей", "nights", "tun", "тун"), systemImage: "moon")
            }
            Divider()
            Stepper(value: $hotelRooms, in: 1...4) {
                Label("\(hotelRooms) " + copy("номеров", "rooms", "xona", "хона"), systemImage: "door.left.hand.closed")
            }
            Stepper(value: $hotelAdults, in: 1...12) {
                Label("\(hotelAdults) " + copy("взрослых", "adults", "kattalar", "катталар"), systemImage: "person.2")
            }
            Stepper(value: $hotelChildren, in: 0...4) {
                Label("\(hotelChildren) " + copy("детей", "children", "bola", "бола"), systemImage: "figure.child")
            }
            ForEach(childAges.indices, id: \.self) { index in
                Stepper(value: $childAges[index], in: 0...17) {
                    Text(copy("Ребёнок", "Child", "Bola", "Бола") + " \(index + 1): \(childAges[index])")
                        .font(.subheadline)
                }
            }
            if hotelRooms > 1 || hotelChildren > 0 || hotelAdults > 6 {
                Label(copy("Для нескольких номеров или детей требуется отдельное подтверждение цены Nuitee. Не показываем взрослый тариф как семейный.",
                           "Multiple rooms or children require a separately verified Nuitee quote.",
                           "Ko‘p xona yoki bolalar uchun narx alohida tasdiqlanishi kerak.",
                           "Кўп хона ёки болалар учун нарх алоҳида тасдиқланиши керак."), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var flightFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            AirportSelectorButton(airport: $browseTrip.originAirport, fallbackCode: $browseTrip.origin, monochrome: true, compact: true)
                .tint(.primary)
            IumrahManualScopePicker()
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel(flightDirection == 0 ? copy("Аэропорт прилёта", "Arrival airport", "Kelish aeroporti", "Келиш аэропорти") : copy("Аэропорт вылета из Саудии", "Saudi departure airport", "Saudiya jo‘nash aeroporti", "Саудия жўнаш аэропорти"))
                Picker("Arrival", selection: $flightDestination) {
                    Text(copy("Джидда", "Jeddah", "Jidda", "Жидда")).tag(SaudiArrivalAirport.jeddah)
                    if manual.scope == .makkahAndMadinah { Text(copy("Медина", "Madinah", "Madina", "Мадина")).tag(SaudiArrivalAirport.madinah) }
                }
                .pickerStyle(.segmented)
            }
            Divider()
            DatePicker(copy("Туда", "Departure", "Ketish", "Кетиш"), selection: $flightDeparture, in: Date()..., displayedComponents: .date)
            DatePicker(copy("Обратно", "Return", "Qaytish", "Қайтиш"), selection: $flightReturn, in: flightDeparture..., displayedComponents: .date)
            Divider()
            travelerControls
            Picker(copy("Класс", "Cabin", "Klass", "Класс"), selection: $flightCabin) {
                Text(copy("Эконом", "Economy", "Ekonom", "Эконом")).tag(FlightCabinClass.economy)
                Text(copy("Премиум", "Premium", "Premium", "Премиум")).tag(FlightCabinClass.premiumEconomy)
                Text(copy("Бизнес", "Business", "Biznes", "Бизнес")).tag(FlightCabinClass.business)
                Text(copy("Первый", "First", "Birinchi", "Биринчи")).tag(FlightCabinClass.first)
            }
            .pickerStyle(.menu).tint(.primary)
        }
    }

    private var weekendFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            AirportSelectorButton(airport: $browseTrip.originAirport, fallbackCode: $browseTrip.origin, monochrome: true, compact: true)
            DatePicker(copy("Дата начала", "Start date", "Boshlanish", "Бошланиш"), selection: $weekendDate, in: Date()..., displayedComponents: .date)
            Stepper(value: $weekendNights, in: 2...4) {
                Label("\(weekendNights) " + copy("ночей", "nights", "tun", "тун"), systemImage: "moon.stars")
            }
            Divider()
            travelerControls
            Text(copy("Вылет и возвращение будут проверены по наличию рейсов. Цены не гарантированы до подтверждения тарифа.",
                      "Flights and fares are subject to live availability and confirmation.",
                      "Reyslar va narxlar tasdiqlanishi kerak.",
                      "Рейслар ва нархлар тасдиқланиши керак."))
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var travelerControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Stepper(value: $flightAdults, in: 1...6) {
                Label("\(flightAdults) " + copy("взрослых", "adults", "kattalar", "катталар"), systemImage: "person.2")
            }
            Text(copy("Дети и несколько номеров — в пошаговом режиме.", "Children and multiple rooms: guided mode.", "Bolalar va bir nechta xona — bosqichma-bosqich rejimda.", "Болалар ва бир нечта хона — босқичма-босқич режимда.")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var searchAction: some View {
        Button(action: search) {
            HStack {
                Text(mode == .hotels
                    ? copy("Найти отели", "Search hotels", "Mehmonxona qidirish", "Меҳмонхона қидириш")
                    : copy("Найти авиабилеты", "Search flights", "Reyslarni qidirish", "Рейсларни қидириш"))
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discovery.search.\(mode.rawValue)")
    }

    private var manualHotelQuote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(copy("Нужна проверка размещения", "Accommodation requires confirmation", "Joylashuv tasdiqlanishi kerak", "Жойлашув тасдиқланиши керак"), systemImage: "person.crop.rectangle.stack")
                .font(.headline)
            Text(copy("Для нескольких номеров, детей или более шести взрослых цены и наличие зависят от состава каждого номера. Для точного расчёта обратитесь в iumrah Care.",
                      "Multiple rooms, children and larger groups need an individually verified room quotation.",
                      "Ko‘p xonalar va bolalar uchun individual hisob talab etiladi.",
                      "Кўп хоналар ва болалар учун индивидуал ҳисоб талаб этилади."))
                .font(.subheadline).foregroundStyle(.secondary)
            Button {
                chrome.navigate(to: .care)
            } label: {
                Label(copy("Связаться с iumrah Care", "Contact iumrah Care", "iumrah Care bilan bog‘lanish", "iumrah Care билан боғланиш"), systemImage: "phone.fill")
                    .frame(maxWidth: .infinity).frame(height: 52)
            }
            .buttonStyle(.borderedProminent).tint(.black)
            .buttonBorderShape(.capsule)
        }
        .padding(22)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, IumrahDesign.pagePadding)
    }

    private var manualHotelList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if manualHotelsBusy {
                ProgressView().frame(maxWidth: .infinity).padding(22)
            } else if let manualHotelsError {
                Text(manualHotelsError).font(.footnote).foregroundStyle(.secondary)
            } else {
                let matching = manualHotels.filter { hotelName.isEmpty || $0.name.localizedStandardContains(hotelName) }
                ForEach(Array(matching.prefix(manualHotelLimit))) { hotel in
                    Button { chrome.navigate(to: .care) } label: {
                        HStack(spacing: 12) {
                            HotelCachedImage(rawURL: hotel.coverImageURL, thumbnailPixelDimension: 768)
                                .frame(width: 74, height: 74).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(hotel.name).font(.headline).foregroundStyle(.primary)
                                Text(hotel.city).font(.caption).foregroundStyle(.secondary)
                                Text(copy("Цена для вашей семьи — по запросу", "Your group quote — on request", "Narx — so‘rov asosida", "Нарх — сўров асосида"))
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(11)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 23))
                    }
                    .buttonStyle(.plain)
                }
                IumrahLoadMoreButton(remaining: matching.count - manualHotelLimit) { manualHotelLimit += 20 }
            }
        }
        .padding(.horizontal, IumrahDesign.pagePadding)
    }

    private func discoveryPrompt(icon: String, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: icon).font(.system(size: 28, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 23, weight: .bold))
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, IumrahDesign.pagePadding)
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 22, weight: .bold)).tracking(-0.4)
    }
    private func fieldLabel(_ label: String) -> some View {
        Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
    }

    private func search() {
        IumrahHaptics.selection()
        pendingFlight = nil
        withAnimation(.easeInOut(duration: 0.22)) { searchExpanded = false }
        appliedHotelName = hotelName
        if mode == .hotels {
            manualQuoteRequired = hotelRooms != 1 || hotelChildren > 0 || hotelAdults > 6
            if !manualQuoteRequired { manual.adults = hotelAdults }
            hotelRequest = IumrahHotelTabSearch(city: hotelCity, checkin: hotelCheckin,
                nights: hotelNights, adults: hotelAdults)
            showHotelResults = true
            if manualQuoteRequired { Task { await loadManualHotelCatalog() } }
            return
        }
        guard mode == .flights || mode == .weekends else { return }
        manual.adults = flightAdults
        manual.routeConfigured = true
        manual.plannedOrigin = browseTrip.originCode
        manual.plannedDeparture = mode == .weekends ? weekendDate : flightDeparture
        manual.plannedReturn = mode == .weekends ? (Calendar.current.date(byAdding: .day, value: weekendNights, to: weekendDate) ?? weekendDate) : flightReturn
        if manual.scope == .makkahOnly { flightDestination = .jeddah }
        if flightDirection == 0 { manual.plannedArrival = flightDestination }
        browseTrip.scope = manual.scope; browseTrip.arrivalAirport = manual.plannedArrival
        manual.cabin = mode == .weekends ? .economy : flightCabin
        browseTrip.adults = manual.adults
        browseTrip.children = 0; browseTrip.infants = 0
        browseTrip.departureDate = mode == .weekends ? weekendDate : flightDeparture
        browseTrip.returnDate = mode == .weekends ? (Calendar.current.date(byAdding: .day, value: weekendNights, to: weekendDate) ?? weekendDate) : flightReturn
        var filters = browseTrip.effectiveFlightFilters; filters.cabinClass = manual.cabin; browseTrip.flightFilters = filters
        requestedSaudiAirport = flightDestination.rawValue
        updateRequestedFlightDay()
        flightSearchRevision += 1
    }

    private func updateRequestedFlightDay() {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        requestedFlightDay = f.string(from: flightDirection == 0 ? browseTrip.departureDate : browseTrip.returnDate)
    }

    @ViewBuilder private var flightConfirmationBar: some View {
        if let flight = pendingFlight {
            Button(copy("Добавить рейс в мой пакет", "Add flight to my package", "Reysni paketimga qo‘shish", "Рейсни пакетимга қўшиш")) { addManualFlight(flight) }
                .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
        } else if flightDirection == 0 && manual.outbound != nil && manual.inbound == nil {
            Button(copy("Выбрать обратный рейс", "Choose return flight", "Qaytish reysini tanlash", "Қайтиш рейсини танлаш")) {
                IumrahHaptics.selection()
                browseTrip = manual.plannedTrip
                withAnimation { flightDirection = 1; searchExpanded = false }
                requestedSaudiAirport = manual.plannedTrip.returnOriginCode
                updateRequestedFlightDay(); flightSearchRevision += 1
            }.buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
        } else if manual.componentCount > 0 {
            Button(copy("Перейти в мой пакет", "Open my package", "Paketimni ochish", "Пакетимни очиш")) { chrome.openHotels(board: .summary) }
                .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
        }
    }

    @discardableResult private func addManualFlight(_ flight: LocalJourneyFlight) -> Bool {
        guard manual.select(flight) else { IumrahHaptics.error(); return false }
        pendingFlight = nil
        showNotice(copy("Рейс добавлен в ваш пакет", "Flight added to your package", "Reys paketingizga qo‘shildi", "Рейс пакетингизга қўшилди"))
        IumrahHaptics.success()
        return true
    }

    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        withAnimation(.spring(response: 0.3)) { selectionMessage = message }
        noticeTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(120))
                noticeRevision += 1
                try await Task.sleep(for: .seconds(2.2))
            } catch { return }
            withAnimation(.easeOut(duration: 0.2)) { selectionMessage = nil }
        }
    }

    private func refreshSearch() async {
        searchExpanded = false
        if mode == .flights || mode == .weekends { flightSearchRevision += 1; return }
        guard mode == .hotels else { return }
        if mode == .hotels && showHotelResults {
            if manualQuoteRequired { await loadManualHotelCatalog() }
            else if let request = hotelRequest {
                await hotelCatalog.reload(city: request.city == "madinah" ? .madinah : .makkah,
                    checkin: request.checkin,
                    checkout: Calendar.current.date(byAdding: .day, value: request.nights, to: request.checkin) ?? request.checkin,
                    adults: request.adults, forceRefresh: true)
            }
        }
    }

    @MainActor private func loadManualHotelCatalog() async {
        manualHotelLimit = 20
        let requestID = UUID()
        manualHotelsRequestID = requestID
        manualHotelsBusy = true
        manualHotelsError = nil
        manualHotels = []
        defer { if manualHotelsRequestID == requestID { manualHotelsBusy = false } }
        do {
            // A catalogue search is allowed, but not a room rate quotation.
            // Suppress supplier prices until every room's occupancy is verified.
            let checkOut = Calendar.current.date(byAdding: .day, value: hotelNights, to: hotelCheckin) ?? hotelCheckin
            let response = try await NuiteeHotelService().hotels(
                city: hotelCity, checkin: hotelCheckin, checkout: checkOut,
                adults: min(6, hotelAdults), catalogOnly: true
            )
            guard manualHotelsRequestID == requestID, !Task.isCancelled else { return }
            manualHotels = response.hotels
        } catch {
            guard manualHotelsRequestID == requestID, !Task.isCancelled else { return }
            manualHotelsError = error.localizedDescription
        }
    }

    private func applyRequestedBoard() {
        guard let requested = chrome.requestedHotelsBoard else { return }
        noticeTask?.cancel(); selectionMessage = nil; pendingFlight = nil
        switch requested {
        case .flights:
            mode = .flights
            if let direction = chrome.requestedManualFlightDirection {
                flightDirection = direction; chrome.requestedManualFlightDirection = nil
                requestedFlightDay = nil; requestedSaudiAirport = nil; flightSearchRevision += 1
            }
            flightAdults = manual.adults; flightCabin = manual.cabin
            flightDeparture = manual.plannedTrip.departureDate; flightReturn = manual.plannedTrip.returnDate
            flightDestination = SaudiArrivalAirport(rawValue: flightDirection == 0 ? manual.plannedTrip.outboundDestinationCode : manual.plannedTrip.returnOriginCode) ?? .jeddah
            browseTrip = manual.plannedTrip
        case .sundayClub: mode = .weekends
        case .transfer: mode = .transfer
        case .summary: mode = .summary
        default:
            let switchingFromOtherBoard = mode != .hotels
            mode = .hotels
            if let city = (manual.routeConfigured && manual.scope == .makkahOnly ? "makkah" : chrome.requestedManualHotelCity) ?? (switchingFromOtherBoard && (manual.trip != nil || manual.routeConfigured) ? hotelCity : nil) {
                chrome.requestedManualHotelCity = nil
                hotelCity = city; hotelAdults = manual.adults; hotelRooms = 1; hotelChildren = 0; manualQuoteRequired = false
                if let window = manual.expectedWindow(city) { hotelCheckin = window.checkIn; hotelNights = window.nights }
                hotelRequest = IumrahHotelTabSearch(city: city, checkin: hotelCheckin, nights: hotelNights, adults: hotelAdults)
                showHotelResults = true
            }
        }
        chrome.requestedHotelsBoard = nil
    }

    private func applyRequestedHotelSearch(_ request: IumrahHotelTabSearch?) {
        guard let request else { return }
        mode = .hotels
        hotelCity = request.city == "madinah" && (!manual.routeConfigured || manual.scope == .makkahAndMadinah) ? "madinah" : "makkah"
        hotelCheckin = request.checkin
        hotelNights = request.nights
        hotelAdults = request.adults
        hotelRooms = 1
        hotelChildren = 0
        manualQuoteRequired = request.adults > 6
        hotelRequest = IumrahHotelTabSearch(city: hotelCity, checkin: request.checkin, nights: request.nights, adults: request.adults)
        hotelSearchRevision += 1
        showHotelResults = true
        if manualQuoteRequired { Task { await loadManualHotelCatalog() } }
        chrome.requestedHotelTabSearch = nil
    }

    private func openRequestedPackage(_ id: String?) {
        guard let id, id.range(of: "^\\d{10}$", options: .regularExpression) != nil else { return }
        Task { @MainActor in
            await storefront.prepareIfNeeded()
            selectedLegacyPackage = await storefront.packagePreview(id: id)
            chrome.requestedPackageID = nil
        }
    }

    private func copy(_ ru: String, _ en: String, _ uz: String, _ cyrl: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cyrl
        default: return en
        }
    }
}

