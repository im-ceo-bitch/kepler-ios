import SwiftUI

/// Dedicated Flight First screen. No tab switch, basket, fabricated fare or new API contract.
/// All published and Data API rows are normalized into one visible list, then ranked.
struct IumrahGuidedFlightSelectionView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var step: LegStep = .outbound
    @State private var published: [CuratedFlightRecommendation] = []
    @State private var dataOutbound: [FlightDiscoveryOffer] = []
    @State private var dataReturn: [FlightDiscoveryOffer] = []
    @State private var outbound: FlightChoice?
    @State private var inbound: FlightChoice?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var showHotels = false
    @State private var headlineIndex = 0
    @State private var isShowingSourceHelp = false

    private enum LegStep: Hashable { case outbound, inbound }
    private enum Source: Hashable { case published, dataAPI }

    private enum FlightChoice: Hashable, Identifiable {
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
    private var flexDays: Int { min(max(0, journey.flightSearchFlexDays), 4) }
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
                    VStack(alignment: .leading, spacing: 16) {
                        searchSummary
                        stepSelector
                        resultsSection
                            .id("flight-results")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 112)
                }
            }
            .onChange(of: step) { _, _ in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("flight-results", anchor: .top)
                }
            }
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
        .background(Color.iumrahSignatureBlack.ignoresSafeArea(edges: .top))
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showHotels) {
            PrimaryHotelView(entryMode: .flightFirst)
        }
        .task { await loadFlights() }
        .task(id: scenePhase == .active && !reduceMotion) {
            guard scenePhase == .active && !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.68)) { headlineIndex = (headlineIndex + 1) % 3 }
            }
        }
        .alert(tr("Совместимость тарифов", "Fare compatibility", "Tarif mosligi", "Тариф мослиги"), isPresented: $isShowingSourceHelp) {
            Button(tr("Понятно", "OK", "Tushunarli", "Тушунарли"), role: .cancel) { }
        } message: {
            Text(tr("Для одной заявки оба рейса должны быть из совместимого источника. Выберите другую пару.",
                    "Both legs must use a compatible source for one package. Please select another pair.",
                    "Bir paketda ikkala reys ham mos manbadan bo‘lishi kerak. Boshqa juftlik tanlang.",
                    "Бир пакетда иккала рейс ҳам мос манбадан бўлиши керак. Бошқа жуфтлик танланг."))
        }
    }

    private var blackHero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(tr("Назад", "Back", "Orqaga", "Орқага"))
                Spacer()
                Image("HeaderWordmarkLight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 174, height: 54)
                    .accessibilityLabel("iumrah")
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            ZStack(alignment: .leading) {
                ForEach(0..<3, id: \.self) { index in
                    if headlineIndex == index {
                        Text(headlines[index])
                            .id(index)
                            .font(IumrahType.bold(28, relativeTo: .largeTitle))
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(reduceMotion ? .opacity : .modifier(
                                active: IumrahFlightVaporPhase(amount: 1),
                                identity: IumrahFlightVaporPhase(amount: 0)))
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            Text(tr("Выберите перелёт туда, затем обратно.", "Choose outbound, then return.",
                    "Avval borish, keyin qaytish reysini tanlang.", "Аввал бориш, кейин қайтиш рейсини танланг."))
                .font(IumrahType.regular(15, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 22)
        .background {
            IumrahWorldDotsHeaderBackground(mapOpacity: 0.30, waveSpeed: 0.55, waveIntensity: 0.7)
                .ignoresSafeArea(edges: .top)
        }
    }

    private var headlines: [String] {
        [tr("Ваш перелёт. Ваш выбор.", "Your flights. Your choice.", "Reysingiz. Tanlovingiz.", "Рейсингиз. Танловингиз."),
         tr("Вместе с близкими.", "Together with loved ones.", "Yaqinlaringiz bilan.", "Яқинларингиз билан."),
         tr("На шаг ближе к умре.", "One step closer to Umrah.", "Umraga yana bir qadam.", "Умрага яна бир қадам.")]
    }

    private var searchSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(outboundCode) → \(destinationCode)   ·   \(returnCode) → \(outboundCode)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("±\(flexDays)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.iumrahRaisedBackground, in: Capsule())
            }
            HStack {
                Text("\(journey.trip.adults) + \(journey.trip.children) + \(journey.trip.infants)")
                    .font(.caption)
                Text("·")
                Text(cabinTitle)
                    .font(.caption)
                Spacer()
                Text("\(dayText(journey.trip.departureDate)) – \(dayText(journey.trip.returnDate))")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
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
        HStack(spacing: 8) {
            stepButton(.outbound, title: tr("Туда", "Outbound", "Borish", "Бориш"), date: journey.trip.departureDate)
            stepButton(.inbound, title: tr("Обратно", "Return", "Qaytish", "Қайтиш"), date: journey.trip.returnDate)
        }
    }

    private func stepButton(_ value: LegStep, title: String, date: Date) -> some View {
        Button {
            guard value == .outbound || outbound != nil else { return }
            withAnimation(.easeInOut(duration: 0.20)) { step = value }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.bold))
                    Text(dayText(date)).font(.caption)
                }
                Spacer(minLength: 0)
                if (value == .outbound && outbound != nil) || (value == .inbound && inbound != nil) {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(step == value ? Color.white : Color.iumrahInk)
            .padding(.horizontal, 13)
            .frame(height: 61)
            .background(step == value ? Color.iumrahSignatureBlack : Color.iumrahCardBackground,
                        in: RoundedRectangle(cornerRadius: 22))
            .opacity(value == .inbound && outbound == nil ? 0.45 : 1)
        }
        .buttonStyle(.plain)
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
            flightGroup(directNearby, title: tr("Прямые · соседние даты", "Non-stop · nearby dates", "To‘g‘ri · yaqin sanalar", "Тўғри · яқин саналар"))
            flightGroup(connecting, title: tr("С пересадкой · Data API", "Connecting · Data API", "Transferli · Data API", "Трансферли · Data API"))

            if hasSelection {
                Button {
                    commitSelection()
                } label: {
                    HStack {
                        Text(tr("Далее: отели", "Next: hotels", "Keyingi: mehmonxonalar", "Кейинги: меҳмонхоналар"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 56)
                    .background(Color.iumrahSignatureBlack, in: Capsule())
                }
                .buttonStyle(.plain)
            }

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
        let offset = abs(dayOffset(for: choice))
        return Button {
            choose(choice)
        } label: {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    AirlineLogoView(airlineCode: choice.airlineCode, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(choice.airlineName).font(.headline).lineLimit(1)
                        Text([choice.airlineCode, choice.flightNumber].filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.iumrahInk : Color.iumrahMuted)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timeText(choice.departureAt)).font(.title3.weight(.bold))
                        Text(choice.origin).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Text(choice.stops == 0
                             ? tr("Без пересадок", "Non-stop", "To‘g‘ridan-to‘g‘ri", "Тўғридан-тўғри")
                             : tr("Пересадок: \(choice.stops)", "Stops: \(choice.stops)", "Transfer: \(choice.stops)", "Трансфер: \(choice.stops)"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                        if choice.duration > 0 {
                            Text("\(choice.duration / 60)h \(choice.duration % 60)m")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(dayTextFromISO(choice.departureAt)).font(.subheadline.weight(.semibold))
                        Text(choice.destination).font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text(choice.source == .published ? "iumrah" : "Data API")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if choice.source == .dataAPI {
                        Text(tr("Класс уточняется", "Cabin unverified", "Klass tekshiriladi", "Класс текширилади"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if offset > 0 {
                        Text("\(dayOffset(for: choice) > 0 ? "+" : "−")\(offset) d")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let price = choice.price {
                        Text(price.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(.headline)
                    } else {
                        Text(tr("Цена при расчёте", "Price on quote", "Narx hisobda", "Нарх ҳисобда"))
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(Color.iumrahInk)
            .padding(16)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(selected ? Color.iumrahInk : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private func choose(_ choice: FlightChoice) {
        IumrahHaptics.selection()
        switch step {
        case .outbound:
            outbound = choice
            inbound = nil
            withAnimation(.easeInOut(duration: 0.20)) { step = .inbound }
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
            if aRank == 1 && abs(dayOffset(for: a)) != abs(dayOffset(for: b)) {
                return abs(dayOffset(for: a)) < abs(dayOffset(for: b))
            }
            if a.departureAt != b.departureAt { return a.departureAt < b.departureAt }
            return a.id < b.id
        }
    }

    private var directExact: [FlightChoice] { availableCandidates.filter { $0.stops == 0 && dayOffset(for: $0) == 0 } }
    private var directNearby: [FlightChoice] { availableCandidates.filter { $0.stops == 0 && dayOffset(for: $0) != 0 } }
    private var connecting: [FlightChoice] { availableCandidates.filter { $0.stops > 0 } }

    private func rank(_ choice: FlightChoice) -> Int {
        choice.stops > 0 ? 2 : (dayOffset(for: choice) == 0 ? 0 : 1)
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
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let trip = journey.trip
        let curatedService = CuratedFlightRecommendationService.shared
        let service = AviasalesFlightDiscoveryService()
        do {
            let result = try await curatedService.load(trip: trip)
            guard !Task.isCancelled else { return }
            published = result
        } catch {
            published = []
            loadError = error.localizedDescription
        }
        if selectedCabin != .economy { return }
        let legs: [(String, String, Date)] = [(outboundCode, destinationCode, trip.departureDate),
                                              (returnCode, outboundCode, trip.returnDate)]
        for (index, route) in legs.enumerated() {
            if Task.isCancelled { return }
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
            if Task.isCancelled { return }
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
        journey.trip.saudiArrivalDate = nil
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
        IumrahHaptics.success()
        showHotels = true
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

/// Mirrors the Home marketing headline transition without a third-party animation.
private struct IumrahFlightVaporPhase: AnimatableModifier {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }
    func body(content: Content) -> some View {
        content
            .opacity(Double(max(0, 1 - amount)))
            .blur(radius: max(0, amount) * 10)
            .offset(y: -amount * 9)
    }
}
