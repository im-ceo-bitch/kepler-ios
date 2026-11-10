import SwiftUI

/// Dedicated Flight First screen. No tab switch, basket, fabricated fare or new API contract.
/// All published and Data API rows are normalized into one visible list, then ranked.
struct IumrahGuidedFlightSelectionView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var filters = IumrahFlightFilterState()
    @State private var editingSearch = false
    @State private var step: LegStep = .outbound
    @State private var published: [CuratedFlightRecommendation] = []
    @State private var dataOutbound: [FlightDiscoveryOffer] = []
    @State private var dataReturn: [FlightDiscoveryOffer] = []
    @State private var outbound: FlightChoice?
    @State private var inbound: FlightChoice?
    @State private var isLoading = false
    @State private var loadingRequestID = UUID()
    @State private var loadError: String?
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
            let date = String(departureAt.prefix(10))
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
                        .background {
                            GeometryReader { geo in
                                Color.clear.preference(key: IumrahScrollingHeroBottomKey.self,
                                    value: geo.frame(in: .named("flightFirstScroll")).maxY)
                            }
                        }
                    VStack(alignment: .leading, spacing: 16) {
                        IumrahPageHelpCard(isLoading ? "flights.loading" : loadError != nil && availableCandidates.isEmpty ? "flights.error" : availableCandidates.isEmpty ? (step == .inbound ? "flights.inbound_empty" : "flights.empty") : step == .outbound ? "flights.outbound" : "flights.inbound")
                        stepSelector
                        searchControls
                        resultsSection
                            .id("flight-results")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 50)
                }
                .background(Color.iumrahPageBackground)
                .background(IumrahNoVerticalBounce())
            }
            .modifier(IumrahJourneyRefresh { await loadFlights() })
            .coordinateSpace(name: "flightFirstScroll")
            .onPreferenceChange(IumrahScrollingHeroBottomKey.self) { bottom in
                isFlightHeaderVisible = bottom > 35
            }
            .onChange(of: step) { _, _ in
                filters = IumrahFlightFilterState()
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo("flight-results", anchor: .top)
                }
            }
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stageContinueButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(item: $selectedDetail) { choice in
            IumrahOTAFlightDetailPage(
                flight: presentation(for: choice),
                language: settings.language,
                actionTitle: tr("Выбрать авиабилет", "Select flight", "Reysni tanlash", "Рейсни танлаш"),
                onChoose: { choose(choice) },
                externalURL: ticketURL(for: choice)
            )
        }
        .navigationDestination(isPresented: $showTransferPicker) {
            NuiteeJourneyHotelsView()
        }
        .task { await loadFlights() }
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
        IumrahJourneyHeader {
            searchSummary
        }
    }

    private var searchSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { withAnimation { editingSearch.toggle() } } label: {
            VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(outboundCode) → \(destinationCode)   ·   \(returnCode) → \(outboundCode)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Image(systemName: editingSearch ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.iumrahRaisedBackground, in: Capsule())
            }
            HStack {
                Text(tr("\(journey.trip.travelerCount) чел.", "\(journey.trip.travelerCount) travelers", "\(journey.trip.travelerCount) kishi", "\(journey.trip.travelerCount) киши"))
                    .font(.caption)
                Text("·")
                Text(cabinTitle)
                    .font(.caption)
                Spacer()
                Text("\(dayText(journey.trip.departureDate)) – \(dayText(journey.trip.returnDate))")
                    .font(.caption.monospacedDigit())
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
        .modifier(IumrahAnimatedSearchBorder())
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
            .init(LegStep.outbound, tr("Туда", "Outbound", "Borish", "Бориш") + " · " + dayText(journey.trip.departureDate)),
            .init(LegStep.inbound, tr("Обратно", "Return", "Qaytish", "Қайтиш") + " · " + dayText(journey.trip.returnDate), enabled: outbound != nil)
        ], selection: step, onSelect: { step = $0 }, height: 58)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(step == .outbound
                         ? tr("Рейсы туда", "Outbound flights", "Borish reyslari", "Бориш рейслари")
                         : tr("Обратные рейсы", "Return flights", "Qaytish reyslari", "Қайтиш рейслари"))
                        .font(.title2.bold())
                    Text("\(currentOrigin) → \(currentDestination) · \(dayText(currentTarget))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading { ProgressView() }
            }

            if step == .inbound && outbound != nil && availableCandidates.isEmpty && !isLoading {
                Text(tr("Для выбранного рейса туда пока нет совместимых обратных вариантов. Выберите другой рейс туда или измените даты.",
                        "No compatible return flights for your outbound choice. Choose another outbound flight or change dates.",
                        "Tanlangan borish reysiga mos qaytish reysi yo‘q. Boshqa reys yoki sanani tanlang.",
                        "Танланган бориш рейсига мос қайтиш рейси йўқ. Бошқа рейс ёки санани танланг."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
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
                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
            }

            flightGroup(directExact, title: tr("Прямые · выбранная дата", "Non-stop · exact date", "To‘g‘ri · tanlangan sana", "Тўғри · танланган сана"))
            flightGroup(connecting, title: tr("С пересадкой · выбранная дата", "Connecting · exact date", "Transferli · tanlangan sana", "Трансферли · танланган сана"))
            flightGroup(directNearby, title: tr("Соседние даты", "Nearby dates", "Yaqin sanalar", "Яқин саналар"))

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
        let selected = (step == .outbound ? outbound?.id : inbound?.id) == choice.id
        return Button {
            selectedDetail = choice
            IumrahHaptics.soft()
        } label: {
            IumrahOTAFlightCard(flight: presentation(for: choice), language: settings.language, isSelected: selected)
        }
        .buttonStyle(.plain)
    }

    /// Visual mapping only: keeps published flights, cached fares and verified
    /// itinerary segments distinct. Search, filtering and booking remain intact.
    private func presentation(for choice: FlightChoice) -> IumrahOTAFlightSnapshot {
        var cabin: String?
        var segments: [IumrahOTAFlightLeg] = []
        if case .published(let item, let isReturn) = choice {
            let leg = isReturn ? (item.inbound ?? item.outbound) : item.outbound
            if leg.stops == 0 && !leg.arrivalAt.isEmpty {
                segments = [IumrahOTAFlightLeg(origin: leg.origin, destination: leg.destination,
                    departureAt: leg.departureAt, arrivalAt: leg.arrivalAt,
                    airlineCode: leg.airlineCode, flightNumber: leg.flightNumber)]
            }
            if !leg.cabinClass.isEmpty { cabin = leg.cabinClass.replacingOccurrences(of: "_", with: " ").capitalized }
        } else if case .dataAPI(let cached) = choice,
                  let verified = FlightDiscoveryItineraryValidator.verified(cached.outboundSegments,
                      origin: cached.origin, destination: cached.destination, transfers: cached.transfers) {
            segments = verified.map {
                IumrahOTAFlightLeg(origin: $0.originAirport, destination: $0.destinationAirport,
                    departureAt: $0.departureAt, arrivalAt: $0.arrivalAt,
                    airlineCode: $0.airlineCode, flightNumber: $0.flightNumber)
            }
        }
        return IumrahOTAFlightSnapshot(id: choice.id,
            airline: choice.airlineName, airlineCode: choice.airlineCode,
            flightNumber: choice.flightNumber,
            origin: choice.origin, destination: choice.destination,
            departureAt: choice.departureAt, arrivalAt: choice.arrivalAt,
            durationMinutes: choice.duration, stops: choice.stops,
            priceUSD: choice.price,
            source: choice.source == .published ? .published : .cachedSearch,
            cabin: cabin, segments: segments)
    }

    private func ticketURL(for choice: FlightChoice) -> URL? {
        if case .dataAPI(let cached) = choice,
           let raw = cached.bookingUrl,
           let url = URL(string: raw),
           ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
           url.host != nil {
            return url
        }
        return AviasalesSearchLinkBuilder.searchURL(
            origin: choice.origin, destination: choice.destination,
            departureAt: choice.departureAt, returnAt: nil,
            adults: journey.trip.adults, children: journey.trip.children,
            infants: journey.trip.infants
        )
    }


    private var searchControls: some View {
        IumrahFlightSearchControls(filters: $filters,
            airlines: Array(Set(availableCandidates.map(\.airlineCode))).sorted(),
            days: IumrahFlightSearchControls.priceDays(calendarOffers.map { ($0.departureAt, Optional($0.price)) }),
            selectedDay: dayKey(IumrahFlightDiscoveryStore.dayFormatter.string(from: currentTarget)),
            onSelectDay: { key in
                guard let date = dateFromISODay(key) else { return }
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
                Task { await loadFlights() }
            })
    }
    private var calendarOffers: [FlightDiscoveryOffer] {
        guard selectedCabin == .economy, step != .inbound || outbound?.source != .published else { return [] }
        return (step == .outbound ? dataOutbound : dataReturn).filter {
            !$0.isRoundTrip && $0.origin == currentOrigin && $0.destination == currentDestination &&
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
            outbound = choice
            inbound = nil
            // The next leg is opened only when the user taps the explicit CTA.
        case .inbound:
            guard let outbound, outbound.source == choice.source else {
                isShowingSourceHelp = true
                return
            }
            inbound = choice
        }
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
            candidates = candidates.filter { $0.source == outbound.source }
            if case .published(let paired, _) = outbound, paired.inbound != nil {
                candidates = candidates.filter {
                    if case .published(let item, _) = $0 {
                        return item.outbound.flightNumber == paired.outbound.flightNumber &&
                               item.outbound.departureAt == paired.outbound.departureAt
                    }
                    return false
                }
            } else if outbound.source == .published {
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
                  let flightDay = dateFromISODay(dayKey(choice.departureAt)),
                  flightDay >= Calendar.current.startOfDay(for: Date()),
                  abs(dayOffset(for: choice)) <= flexDays,
                  !(step == .inbound && dayKey(choice.departureAt) <= dayKey(outbound?.departureAt ?? "")) else { return false }
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
        guard let date = dateFromISODay(dayKey(choice.departureAt)) else { return 9999 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: target),
                                               to: Calendar.current.startOfDay(for: date)).day ?? 9999
    }
    private func dayKey(_ iso: String) -> String { String(iso.prefix(10)) }
    private func dateFromISODay(_ value: String) -> Date? {
        let components = value.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: components[0], month: components[1], day: components[2]))
    }
    private func dayText(_ date: Date) -> String { date.formatted(.dateTime.day().month(.abbreviated)) }
    private func dayTextFromISO(_ iso: String) -> String {
        guard let date = dateFromISODay(dayKey(iso)) else { return dayKey(iso) }
        return dayText(date)
    }
    private func timeText(_ iso: String) -> String {
        let part = iso.split(separator: "T")
        guard part.count >= 2 else { return "—" }
        return String(part[1].prefix(5))
    }

    private func loadFlights() async {
        editingSearch = false
        let requestID = UUID()
        loadingRequestID = requestID
        dataOutbound = []; dataReturn = []
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
        if selectedCabin != .economy { return }
        let legs: [(String, String, Date)] = [(outboundCode, destinationCode, trip.departureDate),
                                              (returnCode, outboundCode, trip.returnDate)]
        for (index, route) in legs.enumerated() {
            if Task.isCancelled || loadingRequestID != requestID { return }
            let (origin, destination, target) = route
            let range = (-flexDays...flexDays).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: target) }
            let months = Array(Set(range.map { IumrahFlightDiscoveryStore.monthFormatter.string(from: $0) })).sorted()
            var collected: [FlightDiscoveryOffer] = []
            for month in months {
                if let value = try? await service.offers(origin: origin, destination: destination,
                                                          departure: month, direct: false, limit: 100) {
                    collected += value.offers
                }
            }
            if let value = try? await service.offers(origin: origin, destination: destination,
                                                      departure: IumrahFlightDiscoveryStore.dayFormatter.string(from: target),
                                                      direct: false, limit: 100) {
                collected += value.offers
            }
            if Task.isCancelled || loadingRequestID != requestID { return }
            let filtered = collected.filter { $0.origin.uppercased() == origin && $0.destination.uppercased() == destination }
            if index == 0 { dataOutbound = filtered } else { dataReturn = filtered }
        }
    }

    private func commitSelection() {
        guard let outbound, let inbound, outbound.source == inbound.source else {
            isShowingSourceHelp = true
            return
        }
        guard let outboundDate = dateFromISODay(dayKey(outbound.departureAt)),
              let inboundDate = dateFromISODay(dayKey(inbound.departureAt)),
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
            isShowingSourceHelp = true
            return
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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 19) {
                IumrahPageHelpCard("flights.details")
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("Авиабилет", "Flight details", "Aviachipta", "Авиачипта"))
                        .font(IumrahType.bold(30, relativeTo: .largeTitle))
                    Text("\(choice.origin) → \(choice.destination)")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        AirlineLogoView(airlineCode: choice.airlineCode, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.airlineName).font(.title3.weight(.bold))
                            Text([choice.airlineCode, choice.flightNumber].filter { !$0.isEmpty }.joined(separator: " "))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(String(choice.departureAt.prefix(10)))
                                .font(.subheadline.weight(.semibold))
                            Text(timeText(choice.departureAt))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text(choice.origin).font(.headline)
                        }
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.title2)
                            .foregroundStyle(choice.stops == 0 ? Color.green : Color.iumrahInk)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(tr("Прилёт", "Arrival", "Yetib kelish", "Етиб келиш"))
                                .font(.subheadline.weight(.semibold))
                            if let actual = choice.arrivalAt {
                                Text(timeText(actual))
                                    .font(.system(size: 34, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            } else {
                                Text("—").font(.system(size: 34, weight: .bold, design: .rounded))
                            }
                            Text(choice.destination).font(.headline)
                        }
                    }
                    Label(
                        choice.stops == 0
                            ? tr("Прямой рейс", "Non-stop flight", "To‘g‘ridan-to‘g‘ri", "Тўғридан-тўғри")
                            : tr("Пересадок: \(choice.stops)", "Stops: \(choice.stops)",
                                 "Transfer: \(choice.stops)", "Трансфер: \(choice.stops)"),
                        systemImage: choice.stops == 0 ? "airplane" : "arrow.triangle.branch"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(choice.stops == 0 ? Color.green : Color.iumrahInk)
                    if choice.duration > 0 {
                        Label("\(choice.duration / 60)h \(choice.duration % 60)m", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if case .dataAPI(let offer) = choice,
                       let segments = offer.outboundSegments, !segments.isEmpty {
                        Divider()
                        Text(tr("Участки перелёта", "Flight segments", "Parvoz qismlari", "Парвоз қисмлари"))
                            .font(.headline)
                        ForEach(segments.indices, id: \.self) { index in
                            let segment = segments[index]
                            Text("\(index + 1). \(segment.originAirport) → \(segment.destinationAirport)")
                                .font(.subheadline.weight(.semibold))
                        }
                    } else if choice.stops > 0 {
                        Text(tr("Аэропорт и время пересадки уточняйте на Aviasales перед покупкой.",
                                "Check the layover airport and times on Aviasales before buying.",
                                "Transfer aeroporti va vaqtini Aviasales’da tekshiring.",
                                "Трансфер аэропорти ва вақтини Aviasales’да текширинг."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(22)
                .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 30))

                Text(tr("Предложения Data API и поиск на Aviasales не гарантируют наличие места или окончательную стоимость.",
                        "Data API offers and Aviasales searches do not guarantee availability or the final fare.",
                        "Data API va Aviasales qidiruvi mavjudlik yoki yakuniy narxni kafolatlamaydi.",
                        "Data API ва Aviasales қидируви мавжудлик ёки якуний нархни кафолатламайди."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .background(Color.iumrahPageBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Button {
                    if let ticketURL { openURL(ticketURL) }
                } label: {
                    HStack {
                        Text(tr("Купить на Aviasales", "Buy on Aviasales", "Aviasales’da sotib olish", "Aviasales’да сотиб олиш"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .frame(height: 54)
                }
                .disabled(ticketURL == nil)
                .buttonStyle(IumrahSecondaryButtonStyle())
                Button {
                    onChoose()
                    dismiss()
                } label: {
                    HStack {
                        Text(tr("Выбрать авиабилет", "Select flight", "Reysni tanlash", "Рейсни танлаш"))
                    }
                    .frame(height: 56)
                }
                .buttonStyle(IumrahPrimaryButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { IumrahPageHelpButton() } }
        .modifier(IumrahHelpOverlayHost(enabled: true))
        .navigationTitle(tr("Авиабилет", "Flight details", "Aviachipta", "Авиачипта"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeText(_ date: String) -> String {
        let parts = date.split(separator: "T")
        return parts.count > 1 ? String(parts[1].prefix(5)) : "—"
    }
}
