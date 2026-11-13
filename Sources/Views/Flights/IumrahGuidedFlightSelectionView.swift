import SwiftUI

/// Dedicated Flight First screen. No tab switch, basket, fabricated fare or new API contract.
/// All published and Data API rows are normalized into one visible list, then ranked.
struct IumrahGuidedFlightSelectionView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var filters = IumrahFlightFilterState()
    @State private var visibleCount = 20
    @State private var editingSearch = false
    @State private var step: LegStep = .outbound
    @State private var published: [CuratedFlightRecommendation] = []
    @State private var dataOutbound: [FlightDiscoveryOffer] = []
    @State private var dataReturn: [FlightDiscoveryOffer] = []
    @State private var outboundCalendar: [FlightDiscoveryCalendarDay] = []
    @State private var returnCalendar: [FlightDiscoveryCalendarDay] = []
    @State private var calendarCache: [String: CalendarCacheEntry] = [:]
    private struct CalendarCacheEntry { let days: [FlightDiscoveryCalendarDay]; let expires: Date }
    @State private var outbound: FlightChoice?
    @State private var inbound: FlightChoice?
    @State private var isLoading = false
    @State private var loadingRequestID = UUID()
    @State private var loadError: String?
    @State private var advanceAfterFlightDetail = false
    @State private var selectedDetail: FlightChoice?
    @State private var showTransferPicker = false
    @State private var isFlightHeaderVisible = true
    @State private var isShowingSourceHelp = false

    private enum LegStep: Hashable { case outbound, inbound }
    fileprivate enum Source: Hashable { case published, dataAPI }

    fileprivate enum FlightChoice: Hashable, Identifiable {
        case published(CuratedFlightRecommendation, isReturn: Bool)
        case dataAPI(FlightDiscoveryOffer)

        var id: String {
            switch self {
            case .published(let item, let isReturn): return "pub:\(item.id):\(isReturn)"
            case .dataAPI(let offer): return "api:\(offer.id)"
            }
        }
        var source: Source {
            switch self { case .published: return .published; case .dataAPI: return .dataAPI }
        }
        var origin: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.origin ?? item.outbound.origin) : item.outbound.origin
            case .dataAPI(let offer): return offer.origin
            }
        }
        var destination: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.destination ?? item.outbound.destination) : item.outbound.destination
            case .dataAPI(let offer): return offer.destination
            }
        }
        var airlineCode: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.airlineCode ?? item.outbound.airlineCode) : item.outbound.airlineCode
            case .dataAPI(let offer): return offer.airlineCode
            }
        }
        var airlineName: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.airline ?? item.primaryAirlineName) : item.primaryAirlineName
            case .dataAPI(let offer): return offer.airlineName
            }
        }
        var flightNumber: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.flightNumber ?? item.outbound.flightNumber) : item.outbound.flightNumber
            case .dataAPI(let offer): return offer.flightNumber
            }
        }
        var departureAt: String {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.departureAt ?? item.outbound.departureAt) : item.outbound.departureAt
            case .dataAPI(let offer): return offer.departureAt
            }
        }
        var arrivalAt: String? {
            switch self {
            case .published(let item, let isReturn):
                return isReturn ? (item.inbound?.arrivalAt ?? item.outbound.arrivalAt) : item.outbound.arrivalAt
            case .dataAPI(let offer):
                return offer.arrivalAt ?? FlightDiscoveryItineraryValidator.verified(offer.outboundSegments,
                    origin: offer.origin, destination: offer.destination, transfers: offer.transfers)?.last?.arrivalAt
            }
        }
        var stops: Int {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.stops ?? item.outbound.stops) : item.outbound.stops
            case .dataAPI(let offer): return offer.transfers
            }
        }
        var duration: Int {
            switch self {
            case .published(let item, let isReturn): return isReturn ? (item.inbound?.durationMinutes ?? item.outbound.durationMinutes) : item.outbound.durationMinutes
            case .dataAPI(let offer): return offer.durationMinutes
            }
        }
        var price: Double? {
            switch self { case .published: return nil; case .dataAPI(let offer): return offer.price > 0 ? offer.price : nil }
        }
        var dedupeKey: String {
            // Same operating flight can be represented in local time or UTC by
            // the two providers. Compare its flight number and local travel day.
            let flight = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = String(IumrahFlightClock.local(departureAt, airport: origin).prefix(10))
            return [origin.uppercased(), destination.uppercased(), airlineCode.uppercased(),
                    flight.uppercased(), date, flight.isEmpty ? String(departureAt.prefix(16)) : ""].joined(separator: "|")
        }
        var isCompletePublishedPair: Bool {
            if case .published(let item, _) = self { return item.inbound != nil }
            return false
        }
    }

    private var outboundCode: String { journey.trip.originCode.uppercased() }
    private var destinationCode: String { journey.trip.outboundDestinationCode.uppercased() }
    private var returnCode: String { journey.trip.returnOriginCode.uppercased() }
    private var flexDays: Int { min(max(3, journey.flightSearchFlexDays), 4) }
    private var selectedCabin: FlightCabinClass { journey.trip.effectiveFlightFilters.cabinClass }
    private var currentTarget: Date { step == .outbound ? journey.trip.departureDate : journey.trip.returnDate }
    private var currentOrigin: String { step == .outbound ? outboundCode : returnCode }
    private var currentDestination: String { step == .outbound ? destinationCode : outboundCode }
    private var hasSelection: Bool { outbound != nil && inbound != nil }

    private func tr(_ ru: String, _ en: String, _ uz: String, _ uzCy: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCy
        default: return en
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    blackHero
                        .id("flight-header")
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: IumrahScrollingHeroBottomKey.self,
                                    value: geo.frame(in: .named("flightFirstScroll")).maxY)
                            }
                        }
                    VStack(alignment: .leading, spacing: 16) {
                        stepSelector.id("flight-step-selector")
                        searchControls
                        resultsSection
                            .id("flight-results")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 50)
                }
                .background(IumrahFlightPalette.page)
                .background(IumrahNoVerticalBounce())
            }
            .modifier(IumrahJourneyRefresh { await loadFlights() })
            .coordinateSpace(name: "flightFirstScroll")
            .onPreferenceChange(IumrahScrollingHeroBottomKey.self) { bottom in
                isFlightHeaderVisible = bottom > 35
            }
            .onChange(of: step) { _, _ in
                visibleCount = 20
                filters = IumrahFlightFilterState()
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo("flight-header", anchor: .top)
                }
            }
        }
        .background(IumrahFlightPalette.page.ignoresSafeArea(edges: .bottom))
        .tint(Color.primary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stageContinueButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedDetail) { choice in
            IumrahGuidedFlightDetailView(
                choice: choice,
                language: settings.language,
                adults: journey.trip.adults,
                children: journey.trip.children,
                infants: journey.trip.infants,
                onChoose: { choose(choice) }
            )
            .onDisappear {
                if advanceAfterFlightDetail {
                    advanceAfterFlightDetail = false
                    advanceFlightSelection()
                }
            }
        }
        .navigationDestination(isPresented: $showTransferPicker) {
            NuiteeJourneyHotelsView()
        }
        .task { await loadFlights() }
        .onChange(of: filters) { _, _ in visibleCount = 20 }
        .alert(tr("Совместимость тарифов", "Fare compatibility", "Tarif mosligi", "Тариф мослиги"), isPresented: $isShowingSourceHelp) {
            Button(tr("Понятно", "OK", "Tushunarli", "Тушунарли"), role: .cancel) { }
        } message: {
            Text(tr("Для одной заявки оба рейса должны быть из совместимого источника. Выберите другую пару.",
                    "Both legs must use a compatible source for one package. Please select another pair.",
                    "Bir paketda ikkala reys ham mos manbadan bo‘lishi kerak. Boshqa juftlik tanlang.",
                    "Бир пакетда иккала рейс ҳам мос манбадан бўлиши керак. Бошқа жуфтлик танланг."))
        }
    }

    @ViewBuilder
    private var stageContinueButton: some View {
        if step == .outbound, outbound != nil {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { step = .inbound }
            } label: {
                HStack {
                    Text(tr("Выбрать обратный перелёт", "Choose return flight", "Qaytish reysini tanlash", "Қайтиш рейсини танлаш"))
                }
                .frame(height: IumrahDesign.controlHeight)
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.clear)
        } else if step == .inbound, hasSelection {
            Button(action: commitSelection) {
                HStack {
                    Text(tr("Выбрать отель", "Choose hotel", "Mehmonxona tanlash", "Меҳмонхона танлаш"))
                }
                .frame(height: IumrahDesign.controlHeight)
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color.clear)
        }
    }

    private var blackHero: some View {
        IumrahJourneyHeader(pageBackground: IumrahFlightPalette.page, flightHeading: .init(
            origin: currentOrigin, destination: currentDestination,
            title: step == .outbound
                ? tr("Выберите рейс туда", "Choose outbound flight", "Borish reysini tanlang", "Бориш рейсини танланг")
                : tr("Выберите обратный рейс", "Choose return flight", "Qaytish reysini tanlang", "Қайтиш рейсини танланг"))) {
            searchSummary
        }
    }

    private var searchSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { withAnimation { editingSearch.toggle() } } label: {
            VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(dayText(journey.trip.departureDate)) – \(dayText(journey.trip.returnDate))")
                    .font(IumrahType.bold(17)).monospacedDigit()
                Spacer()
                Image(systemName: editingSearch ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(IumrahFlightPalette.raised, in: Capsule())
            }
            HStack {
                Text(tr("\(journey.trip.travelerCount) чел.", "\(journey.trip.travelerCount) travelers", "\(journey.trip.travelerCount) kishi", "\(journey.trip.travelerCount) киши"))
                    .font(.caption)
                Text("·")
                Text(cabinTitle)
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if editingSearch {
                Divider()
                IumrahFlightSearchEditor {
                    outbound = nil
                    inbound = nil
                    step = .outbound
                    editingSearch = false
                    Task { await loadFlights() }
                }
            }
        }
        .padding(16)
        .background(IumrahFlightPalette.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.09), lineWidth: 1) }
        .modifier(IumrahCollapseSearchOnPull { editingSearch = false })
    }

    private var cabinTitle: String {
        switch selectedCabin {
        case .economy: return tr("Эконом", "Economy", "Ekonom", "Эконом")
        case .premiumEconomy: return tr("Премиум-эконом", "Premium economy", "Premium ekonom", "Премиум эконом")
        case .business: return tr("Бизнес", "Business", "Biznes", "Бизнес")
        case .first: return tr("Первый", "First", "Birinchi", "Биринчи")
        }
    }

    private var stepSelector: some View {
        IumrahGlassPillSelector(options: [
            .init(LegStep.outbound, tr("Туда", "Outbound", "Borish", "Бориш")),
            .init(LegStep.inbound, tr("Обратно", "Return", "Qaytish", "Қайтиш"), enabled: outbound != nil)
        ], selection: step, onSelect: { step = $0 }, height: 58)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            if isLoading { ProgressView().frame(maxWidth: .infinity) }

            if step == .inbound && outbound != nil && availableCandidates.isEmpty && !isLoading {
                Text(tr("Для выбранного рейса туда пока нет совместимых обратных вариантов. Выберите другой рейс туда или измените даты.",
                        "No compatible return flights for your outbound choice. Choose another outbound flight or change dates.",
                        "Tanlangan borish reysiga mos qaytish reysi yo‘q. Boshqa reys yoki sanani tanlang.",
                        "Танланган бориш рейсига мос қайтиш рейси йўқ. Бошқа рейс ёки санани танланг."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(IumrahFlightPalette.card, in: RoundedRectangle(cornerRadius: 18))
                Button(tr("Изменить рейс туда", "Change outbound", "Borish reysini o‘zgartirish", "Бориш рейсини ўзгартириш")) {
                    inbound = nil
                    outbound = nil
                    withAnimation(.easeInOut(duration: 0.2)) { step = .outbound }
                }
                .buttonStyle(IumrahSecondaryButtonStyle())
            }

            if let loadError, availableCandidates.isEmpty {
                Text(loadError).font(.footnote).foregroundStyle(.secondary)
                Button(tr("Повторить", "Retry", "Qayta urinish", "Қайта уриниш")) {
                    Task { await loadFlights() }
                }
                .buttonStyle(IumrahSecondaryButtonStyle())
            }

            if !isLoading && availableCandidates.isEmpty && loadError == nil {
                Label(tr("Подходящих рейсов пока нет. Попробуйте другие даты или класс.",
                         "No matching flights yet. Try different dates or cabin class.",
                         "Mos reyslar hozircha yo‘q. Boshqa sana yoki klassni tanlang.",
                         "Мос рейслар ҳозирча йўқ. Бошқа сана ёки классни танланг."), systemImage: "airplane.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .background(IumrahFlightPalette.card, in: RoundedRectangle(cornerRadius: 18))
            }

            flightGroup(Array(directExact.prefix(visibleCount)), title: tr("Прямые рейсы", "Non-stop flights", "To‘g‘ridan-to‘g‘ri reyslar", "Тўғридан-тўғри рейслар"))
            flightGroup(Array(connecting.prefix(max(0, visibleCount - directExact.count))), title: tr("Рейсы с пересадкой", "Connecting flights", "Transferli reyslar", "Трансферли рейслар"))
            flightGroup(Array(directNearby.prefix(max(0, visibleCount - directExact.count - connecting.count))), title: tr("Соседние даты", "Nearby dates", "Yaqin sanalar", "Яқин саналар"))
            IumrahLoadMoreButton(remaining: directExact.count + connecting.count + directNearby.count - visibleCount) { visibleCount += 20 }

            Text(tr("Цены Data API — предварительные. Наличие и окончательная стоимость проверяются перед бронированием.",
                    "Data API fares are indicative. Availability and final price are checked before booking.",
                    "Data API narxlari taxminiy. Mavjudlik va yakuniy narx buyurtmadan oldin tekshiriladi.",
                    "Data API нархлари тахминий. Мавжудлик ва якуний нарх буюртмадан олдин текширилади."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func flightGroup(_ flights: [FlightChoice], title: String) -> some View {
        if !flights.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                ForEach(flights) { choice in
                    flightCard(choice)
                }
            }
        }
    }

    private func flightCard(_ choice: FlightChoice) -> some View {
        IumrahFlightResultCard(airline: choice.airlineName, airlineCode: choice.airlineCode,
            flightNumber: choice.flightNumber, origin: choice.origin, destination: choice.destination,
            departureAt: choice.departureAt, arrivalAt: choice.arrivalAt, duration: choice.duration,
            stops: choice.stops, price: choice.price, isAviasales: choice.source == .dataAPI,
            selected: (step == .outbound ? outbound?.id : inbound?.id) == choice.id,
            selectedSearchDay: dayKey(IumrahFlightDiscoveryStore.dayFormatter.string(from: currentTarget)),
            onSelect: { choose(choice) }) {
                selectedDetail = choice
                IumrahHaptics.soft()
            }
    }

    private var minimumSearchDay: String {
        let today = Calendar.current.startOfDay(for: Date())
        let afterOutbound = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: journey.trip.departureDate)) ?? today
        return IumrahFlightDiscoveryStore.dayFormatter.string(from: step == .outbound ? today : max(today, afterOutbound))
    }
    private var observedFareDays: [IumrahFlightPriceDay] {
        let prices = calendarOffers.map { (IumrahFlightClock.local($0.departureAt, airport: $0.origin), Optional($0.price)) }
        return IumrahFlightSearchControls.priceDays(prices + calendarPrices)
    }
    private var searchControls: some View {
        IumrahFlightSearchControls(filters: $filters,
            airlines: Array(Set(availableCandidates.map(\.airlineCode))).sorted(),
            days: observedFareDays,
            selectedDay: dayKey(IumrahFlightDiscoveryStore.dayFormatter.string(from: currentTarget)),
            minimumDay: minimumSearchDay,
            onSelectDay: { key in
                guard let date = dateFromISODay(key), date >= Calendar.current.startOfDay(for: Date()),
                      !Calendar.current.isDate(date, inSameDayAs: currentTarget) else { return }
                if step == .outbound {
                    journey.trip.departureDate = date
                    outbound = nil; inbound = nil
                    if journey.trip.returnDate <= date {
                        journey.trip.returnDate = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date
                    }
                } else {
                    guard date > journey.trip.departureDate else { return }
                    journey.trip.returnDate = date; inbound = nil
                }
                Task { await loadFlights(preserveCalendar: true) }
            })
            .id(step)
    }
    private var calendarPrices: [(String, Double?)] {
        guard selectedCabin == .economy, filters.airline.isEmpty else { return [] }
        return (step == .outbound ? outboundCalendar : returnCalendar).filter { day in
            day.origin.uppercased() == currentOrigin && day.destination.uppercased() == currentDestination &&
            (day.returnAt ?? "").isEmpty && filters.accepts(stops: day.transfers, airline: day.airlineCode, departure: day.date, includeDay: false)
        }.map { ($0.date, Optional($0.price)) }
    }
    private var calendarOffers: [FlightDiscoveryOffer] {
        guard selectedCabin == .economy else { return [] }
        return (step == .outbound ? dataOutbound : dataReturn).filter {
            !$0.isRoundTrip && $0.origin == currentOrigin && $0.destination == currentDestination &&
            dayKey(IumrahFlightClock.local($0.departureAt, airport: $0.origin)) >= IumrahFlightDiscoveryStore.dayFormatter.string(from: Calendar.current.startOfDay(for: Date())) &&
            (step == .outbound || dayKey(IumrahFlightClock.local($0.departureAt, airport: $0.origin)) > IumrahFlightDiscoveryStore.dayFormatter.string(from: journey.trip.departureDate)) &&
            filters.accepts(stops: $0.transfers, airline: $0.airlineCode, departure: $0.departureAt, includeDay: false)
        }
    }
    private var visibleCandidates: [FlightChoice] {
        availableCandidates.filter {
            filters.accepts(stops: $0.stops, airline: $0.airlineCode, departure: $0.departureAt, includeDay: false)
        }.sorted { a, b in
            if filters.sort == 1, a.price != b.price { return (a.price ?? .infinity) < (b.price ?? .infinity) }
            if filters.sort == 2, a.duration != b.duration { return (a.duration > 0 ? a.duration : Int.max) < (b.duration > 0 ? b.duration : Int.max) }
            return a.departureAt == b.departureAt ? a.id < b.id : a.departureAt < b.departureAt
        }
    }

    private func choose(_ choice: FlightChoice) {
        IumrahHaptics.selection()
        switch step {
        case .outbound:
            if outbound?.id != choice.id { inbound = nil }
            outbound = choice

        case .inbound:
            guard let outbound, !outbound.isCompletePublishedPair || choice.isCompletePublishedPair else {
                isShowingSourceHelp = true
                return
            }
            inbound = choice
        }
        if selectedDetail != nil { advanceAfterFlightDetail = true }
        else { advanceFlightSelection() }
    }

    private func advanceFlightSelection() {
        if step == .outbound { withAnimation { step = .inbound } }
        else { commitSelection() }
    }

    private var availableCandidates: [FlightChoice] {
        var candidates: [FlightChoice] = []
        for item in published where item.nonstop && publishedCabinMatches(item) {
            if step == .outbound {
                if item.outbound.origin.uppercased() == outboundCode && item.outbound.destination.uppercased() == destinationCode {
                    // Complete published packages may only be offered when their
                    // fixed return leg matches the traveler’s selected return window.
                    if let returnLeg = item.inbound {
                        let candidateReturn = FlightChoice.published(item, isReturn: true)
                        guard returnLeg.origin.uppercased() == returnCode,
                              returnLeg.destination.uppercased() == outboundCode,
                              abs(dayOffset(for: candidateReturn, from: journey.trip.returnDate)) <= flexDays else { continue }
                    }
                    candidates.append(.published(item, isReturn: false))
                }
            } else if item.inbound != nil {
                if case .published(let selected, _) = outbound,
                   selected.outbound.origin.uppercased() == item.outbound.origin.uppercased(),
                   selected.outbound.destination.uppercased() == item.outbound.destination.uppercased(),
                   selected.outbound.flightNumber == item.outbound.flightNumber,
                   selected.outbound.departureAt == item.outbound.departureAt,
                   let inboundLeg = item.inbound,
                   inboundLeg.origin.uppercased() == returnCode && inboundLeg.destination.uppercased() == outboundCode {
                    candidates.append(.published(item, isReturn: true))
                }
            } else if item.effectiveJourneyRole == "return" &&
                      item.outbound.origin.uppercased() == returnCode &&
                      item.outbound.destination.uppercased() == outboundCode {
                candidates.append(.published(item, isReturn: true))
            }
        }
        // The Data API has no reliably verified cabin metadata. It is offered
        // only for the economy preference and explicitly rechecked later.
        if selectedCabin == .economy {
            for offer in step == .outbound ? dataOutbound : dataReturn where !offer.isRoundTrip {
                candidates.append(.dataAPI(offer))
            }
        }
        if step == .inbound, let outbound {
            if case .published(let paired, _) = outbound, paired.inbound != nil {
                candidates = candidates.filter {
                    if case .published(let item, _) = $0 {
                        return item.outbound.flightNumber == paired.outbound.flightNumber &&
                               item.outbound.departureAt == paired.outbound.departureAt
                    }
                    return false
                }
            } else {
                candidates = candidates.filter { !$0.isCompletePublishedPair }
            }
        }
        // Prefer bookable complete publications when a one-way publication
        // duplicates the same operating outbound flight.
        candidates.sort { a, b in
            if a.source != b.source { return a.source == .published }
            if a.isCompletePublishedPair != b.isCompletePublishedPair {
                return a.isCompletePublishedPair
            }
            return a.id < b.id
        }
        var seen = Set<String>()
        return candidates.filter { choice in
            guard choice.stops >= 0,
                  let flightDay = dateFromISODay(dayKey(IumrahFlightClock.local(choice.departureAt, airport: choice.origin))),
                  flightDay >= Calendar.current.startOfDay(for: Date()),
                  abs(dayOffset(for: choice)) <= flexDays,
                  !(step == .inbound && dayKey(IumrahFlightClock.local(choice.departureAt, airport: choice.origin)) <= dayKey(outbound.map { IumrahFlightClock.local($0.departureAt, airport: $0.origin) } ?? "")) else { return false }
            return seen.insert(choice.dedupeKey).inserted
        }.sorted { a, b in
            let aRank = rank(a), bRank = rank(b)
            if aRank != bRank { return aRank < bRank }
            if dayOffset(for: a) != 0 && dayOffset(for: b) != 0 && abs(dayOffset(for: a)) != abs(dayOffset(for: b)) {
                return abs(dayOffset(for: a)) < abs(dayOffset(for: b))
            }
            if a.departureAt != b.departureAt { return a.departureAt < b.departureAt }
            return a.id < b.id
        }
    }

    private var directExact: [FlightChoice] { visibleCandidates.filter { $0.stops == 0 && dayOffset(for: $0) == 0 } }
    private var directNearby: [FlightChoice] { visibleCandidates.filter { dayOffset(for: $0) != 0 } }
    private var connecting: [FlightChoice] { visibleCandidates.filter { $0.stops > 0 && dayOffset(for: $0) == 0 } }

    private func rank(_ choice: FlightChoice) -> Int {
        dayOffset(for: choice) == 0 ? (choice.stops == 0 ? 0 : 1) : 2
    }

    private func publishedCabinMatches(_ item: CuratedFlightRecommendation) -> Bool {
        let cabin = item.cabinClass.lowercased().replacingOccurrences(of: " ", with: "_")
        return cabin == selectedCabin.rawValue
    }

    private func dayOffset(for choice: FlightChoice) -> Int {
        dayOffset(for: choice, from: currentTarget)
    }
    private func dayOffset(for choice: FlightChoice, from target: Date) -> Int {
        guard let date = dateFromISODay(dayKey(IumrahFlightClock.local(choice.departureAt, airport: choice.origin))) else { return 9999 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: target),
                                               to: Calendar.current.startOfDay(for: date)).day ?? 9999
    }
    private func dayKey(_ iso: String) -> String { String(iso.prefix(10)) }
    private func dateFromISODay(_ value: String) -> Date? {
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))
    }
    private func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: settings.language.localeIdentifier)))
    }
    private func dayTextFromISO(_ iso: String) -> String {
        guard let date = dateFromISODay(dayKey(iso)) else { return dayKey(iso) }
        return dayText(date)
    }
    private func timeText(_ iso: String) -> String {
        let part = iso.split(separator: "T")
        guard part.count >= 2 else { return "—" }
        return String(part[1].prefix(5))
    }

    private func loadFlights(preserveCalendar: Bool = false) async {
        visibleCount = 20
        editingSearch = false
        let requestID = UUID()
        loadingRequestID = requestID
        if !preserveCalendar { dataOutbound = []; dataReturn = []; outboundCalendar = []; returnCalendar = [] }
        isLoading = true
        loadError = nil
        defer { if loadingRequestID == requestID { isLoading = false } }
        let trip = journey.trip
        let curatedService = CuratedFlightRecommendationService.shared
        let service = AviasalesFlightDiscoveryService()
        do {
            let result = try await curatedService.load(trip: trip)
            guard !Task.isCancelled, loadingRequestID == requestID else { return }
            published = result
        } catch {
            guard loadingRequestID == requestID else { return }
            published = []
            loadError = error.localizedDescription
        }
        if selectedCabin != .economy { dataOutbound = []; dataReturn = []; outboundCalendar = []; returnCalendar = []; return }
        let legs: [(String, String, Date)] = [(outboundCode, destinationCode, trip.departureDate),
                                              (returnCode, outboundCode, trip.returnDate)]
        let orderedLegs = step == .outbound ? [0, 1] : [1, 0]
        for index in orderedLegs {
            if Task.isCancelled || loadingRequestID != requestID { return }
            let (origin, destination, target) = legs[index]
            let selected = IumrahFlightDiscoveryStore.dayFormatter.string(from: target)
            let calendarMonths = Set((-14...14).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: target) }.map { IumrahFlightDiscoveryStore.monthFormatter.string(from: $0) })
            let offerMonths = Set((-flexDays...flexDays).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: target) }.map { IumrahFlightDiscoveryStore.monthFormatter.string(from: $0) })
            var collected: [FlightDiscoveryOffer] = []
            // Show the actual selected-date results first; calendar observations never become flight offers.
            if let value = try? await service.offers(origin: origin, destination: destination, departure: selected, direct: false, limit: 100) {
                collected += value.offers.filter { $0.origin.uppercased() == origin && $0.destination.uppercased() == destination }
                guard !Task.isCancelled, loadingRequestID == requestID else { return }
                if index == 0 { dataOutbound = collected } else { dataReturn = collected }
            }
            guard !Task.isCancelled, loadingRequestID == requestID else { return }
            var calendar: [FlightDiscoveryCalendarDay] = []
            for month in calendarMonths.sorted() {
                if Task.isCancelled || loadingRequestID != requestID { return }
                let cacheKey = "\(origin)|\(destination)|\(month)"
                if let cached = calendarCache[cacheKey], cached.expires > Date() {
                    calendar += cached.days
                } else if let value = try? await service.calendar(origin: origin, destination: destination, month: month) {
                    guard !Task.isCancelled, loadingRequestID == requestID else { return }
                    calendar += value.days
                    calendarCache = calendarCache.filter { $0.value.expires > Date() }
                    calendarCache[cacheKey] = CalendarCacheEntry(days: value.days, expires: Date().addingTimeInterval(300))
                }
                guard !Task.isCancelled, loadingRequestID == requestID else { return }
                if index == 0 { outboundCalendar = calendar } else { returnCalendar = calendar }
                if offerMonths.contains(month), let value = try? await service.offers(origin: origin, destination: destination, departure: month, direct: false, limit: 100) {
                    collected += value.offers.filter { $0.origin.uppercased() == origin && $0.destination.uppercased() == destination }
                    guard !Task.isCancelled, loadingRequestID == requestID else { return }
                    // Keep the exact date version if both endpoints returned the same offer ID.
                    var seen = Set<String>()
                    let unique = collected.filter { seen.insert($0.id).inserted }
                    if index == 0 { dataOutbound = unique } else { dataReturn = unique }
                }
            }
        }
    }

    private func commitSelection() {
        guard let outbound, let inbound else {
            isShowingSourceHelp = true
            return
        }
        guard let outboundDate = dateFromISODay(dayKey(IumrahFlightClock.local(outbound.departureAt, airport: outbound.origin))),
              let inboundDate = dateFromISODay(dayKey(IumrahFlightClock.local(inbound.departureAt, airport: inbound.origin))),
              inboundDate > outboundDate else { return }

        journey.clearStagedUmrahFlights()
        journey.trip.departureDate = outboundDate
        journey.trip.returnDate = inboundDate
        journey.trip.saudiArrivalDate = outbound.arrivalAt.flatMap { dateFromISODay(dayKey($0)) }
        journey.trip.flightTripType = .roundTrip
        journey.trip.selectedReturnAirport = inbound.origin.uppercased() == "MED" ? .madinah : .jeddah
        journey.trip.arrivalAirport = outbound.destination.uppercased() == "MED" ? .madinah : .jeddah

        if case .published(let chosenOutbound, _) = outbound,
           case .published(let chosenInbound, _) = inbound {
            journey.packageFlightPath = .publishedDirect
            if chosenOutbound.inbound != nil && chosenInbound.inbound != nil &&
               chosenOutbound.outbound.flightNumber == chosenInbound.outbound.flightNumber &&
               chosenOutbound.outbound.departureAt == chosenInbound.outbound.departureAt {
                journey.selectedPublishedCompleteID = chosenInbound.id
                journey.selectedPublishedOutboundID = nil
                journey.selectedPublishedReturnID = nil
                journey.stageUmrahFlight(makeStaged(outbound, kind: .roundTrip,
                    returnAt: inbound.departureAt, returnAirline: inbound.airlineName,
                    returnFlightNumber: inbound.flightNumber))
            } else if chosenOutbound.inbound == nil && chosenInbound.inbound == nil {
                journey.selectedPublishedCompleteID = nil
                journey.selectedPublishedOutboundID = chosenOutbound.id
                journey.selectedPublishedReturnID = chosenInbound.id
                journey.stageUmrahFlight(makeStaged(outbound, kind: .outbound))
                journey.stageUmrahFlight(makeStaged(inbound, kind: .inbound))
            } else {
                isShowingSourceHelp = true
                return
            }
        } else if case .dataAPI(let outboundOffer) = outbound,
                  case .dataAPI(let inboundOffer) = inbound {
            journey.stageUmrahFlight(makeStaged(outbound, kind: .outbound))
            journey.stageAviasalesOffer(outboundOffer, kind: .outbound)
            journey.stageUmrahFlight(makeStaged(inbound, kind: .inbound))
            journey.stageAviasalesOffer(inboundOffer, kind: .inbound)
        } else {
            guard !outbound.isCompletePublishedPair, !inbound.isCompletePublishedPair else {
                isShowingSourceHelp = true
                return
            }
            journey.stageUmrahFlight(makeStaged(outbound, kind: .outbound))
            journey.stageUmrahFlight(makeStaged(inbound, kind: .inbound))
            journey.clearPublishedFlightSelection()
            journey.mixedFlightIdentity = "mixed:" + independentIdentity(outbound) + "~" + independentIdentity(inbound)
        }
        guard journey.hasCompleteStagedFlightSelection else { return }
        journey.prepareFlightFirstHotelStage()
        journey.usesLocalJourney = true
        journey.localJourneyRooms = [:]
        journey.localJourneyFlights = [outbound, inbound].map { flight in
            LocalJourneyFlight(id: flight.id, origin: flight.origin, destination: flight.destination,
                airline: flight.airlineName, flightNumber: flight.flightNumber, airlineCode: flight.airlineCode,
                durationMinutes: flight.duration, stops: flight.stops, departureAt: flight.departureAt,
                arrivalAt: flight.arrivalAt, displayedPrice: flight.price)
        }
        IumrahHaptics.success()
        showTransferPicker = true
    }

    private func independentIdentity(_ flight: FlightChoice) -> String {
        switch flight {
        case .published(let item, _): return "curated:" + item.id
        case .dataAPI(let offer):
            return ["aviasales", "ow", offer.origin.uppercased(), offer.destination.uppercased(),
                    String(offer.departureAt.prefix(10)), "-", offer.airlineCode.uppercased(),
                    offer.flightNumber.uppercased().filter { $0.isLetter || $0.isNumber }, "-", "-"].joined(separator: ":")
        }
    }

    private func makeStaged(_ flight: FlightChoice, kind: StagedUmrahFlightKind,
                            returnAt: String? = nil, returnAirline: String? = nil,
                            returnFlightNumber: String? = nil) -> StagedUmrahFlight {
        StagedUmrahFlight(id: flight.id, kind: kind, origin: flight.origin, destination: flight.destination,
                          airline: flight.airlineName,
                          flightNumber: [flight.airlineCode, flight.flightNumber].filter { !$0.isEmpty }.joined(separator: " "),
                          departureAt: flight.departureAt, returnAt: returnAt,
                          returnAirline: returnAirline, returnFlightNumber: returnFlightNumber,
                          source: flight.source == .published ? "iumrah" : "Aviasales")
    }
}


/// A real flight-detail destination, rather than a tap-to-select row.
/// Supplier information is shown only when present in its returned model.
private struct IumrahGuidedFlightDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let choice: IumrahGuidedFlightSelectionView.FlightChoice
    let language: AppSettingsStore.Language
    let adults: Int
    let children: Int
    let infants: Int
    let onChoose: () -> Void

    private func tr(_ ru: String, _ en: String, _ uz: String, _ uzCyrl: String) -> String {
        switch language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCyrl
        default: return en
        }
    }

    private var ticketURL: URL? {
        if case .dataAPI(let offer) = choice,
           let raw = offer.bookingUrl,
           let url = URL(string: raw),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil {
            return url
        }
        return AviasalesSearchLinkBuilder.searchURL(
            origin: choice.origin,
            destination: choice.destination,
            departureAt: choice.departureAt,
            returnAt: nil,
            adults: adults,
            children: children,
            infants: infants
        )
    }

    private var legs: [IumrahPremiumFlightLeg] {
        if case .dataAPI(let offer) = choice,
           let segments = FlightDiscoveryItineraryValidator.verified(offer.outboundSegments, origin: choice.origin, destination: choice.destination, transfers: choice.stops) {
            return segments.map { IumrahPremiumFlightLeg($0) }
        }
        var cabin: String?
        if case .published(let item, let isReturn) = choice { cabin = isReturn ? item.inbound?.cabinClass : item.outbound.cabinClass }
        return [IumrahPremiumFlightLeg(airline: choice.airlineName, airlineCode: choice.airlineCode, number: choice.flightNumber, origin: choice.origin, destination: choice.destination, departure: choice.departureAt, arrival: choice.arrivalAt, duration: choice.duration, stops: choice.stops, cabin: cabin)]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0 { IumrahPremiumFlightConnection(previous: legs[index - 1], next: leg, language: language) }
                    IumrahPremiumFlightDetail(leg: leg, language: language, pageHeroInset: index == 0 ? IumrahDesign.pagePadding : nil)
                }
                VStack(alignment: .leading, spacing: 9) {
                    Text(tr("Тариф", "Fare", "Tarif", "Тариф")).font(IumrahType.bold(20, relativeTo: .title2))
                    if let price = choice.price, price.isFinite, price > 0 {
                        Text("$" + price.formatted(.number.precision(.fractionLength(0...2))))
                            .font(IumrahType.bold(30, relativeTo: .title)).monospacedDigit()
                        Text(tr("За пассажира · ориентир", "Per traveler · indicative", "Yo‘lovchiga · taxminiy", "Йўловчига · тахминий")).font(IumrahType.regular(12, relativeTo: .caption)).foregroundStyle(.secondary)
                    }
                    Text(tr("Цена, багаж и наличие мест подтверждаются перед оплатой.", "Fare, baggage and availability are confirmed before payment.", "Narx, bagaj va joylar to‘lovdan oldin tasdiqlanadi.", "Нарх, багаж ва жойлар тўловдан олдин тасдиқланади.")).font(IumrahType.regular(13, relativeTo: .subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.iumrahFlightCard()
            VStack(spacing: 10) {
                Button { onChoose(); dismiss() } label: {
                    Text(tr("Выбрать авиабилет", "Select flight", "Reysni tanlash", "Рейсни танлаш"))
                        .font(IumrahType.bold(16)).frame(maxWidth: .infinity).frame(height: 52)
                }.buttonStyle(IumrahPrimaryButtonStyle())
                if let ticketURL {
                    Button { openURL(ticketURL) } label: {
                        Text(tr("Проверить на Aviasales", "Check on Aviasales", "Aviasales’da tekshirish", "Aviasales’да текшириш"))
                            .font(IumrahType.bold(14)).frame(maxWidth: .infinity).frame(height: 42)
                    }.buttonStyle(IumrahSecondaryButtonStyle())
                }
            }.padding(.vertical, 10)
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.bottom, IumrahDesign.pagePadding)
        }
        .background(IumrahFlightPalette.page, ignoresSafeAreaEdges: .bottom)
        .iumrahFlightDetailChrome()
    }

    private func timeText(_ date: String) -> String {
        let parts = date.split(separator: "T")
        return parts.count > 1 ? String(parts[1].prefix(5)) : "—"
    }
}
