import SwiftUI

/// One flow for first launch and the Home Smart card. A private journey is
/// deliberately isolated from any partially assembled manual configurator.
struct SmartConfiguratorFlow: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = SmartConfiguratorStore()
    @State private var step: Step = .welcome
    @State private var airportPicker = false
    @State private var showReview = false
    @State private var runID = 0
    @State private var replacementRequest: String?
    @State private var replacementRevision = 0
    @State private var categoryScroll: String? = PackageTier.standard.rawValue
    @State private var historyInitialized = false
    @State private var historyOwner: String?
    @State private var suppressHistory = false
    var firstLaunch: Bool = false
    var resumeDraft: HomeSmartDraft? = nil
    let onExit: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, origin, month, duration, route, firstCity, party, category, assembly
        var symbol: String? {
            switch self {
            case .welcome, .assembly: return nil
            case .origin: return "airplane.departure"
            case .month: return "calendar"
            case .duration: return "clock"
            case .route: return "map.fill"
            case .firstCity: return "airplane.arrival"
            case .party: return "person.2.fill"
            case .category: return "star.fill"
            }
        }
    }
    private var largeOrbit: Bool { step == .welcome || step == .assembly }
    private var steps: [Step] { Step.allCases.filter { $0 != .firstCity || store.preferences.scope == .makkahAndMadinah } }
    private var canContinue: Bool {
        switch step {
        case .origin: return !["JED", "MED"].contains(store.preferences.origin) && store.preferences.origin.count == 3
        case .party: return store.preferences.infants <= store.preferences.adults && store.preferences.adults + store.preferences.childAges.count <= 6
        case .assembly: return store.result != nil
        default: return true
        }
    }
    private func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    private var title: String {
        switch step {
        case .welcome: return t("Ваша Умра. Ваш выбор.", "Your Umrah. Your choice.", "Sizning Umrangiz. Sizning tanlovingiz.", "Сизнинг Умрангиз. Сизнинг танловингиз.")
        case .origin: return t("Из какого города вы хотите вылететь?", "Where will you depart from?", "Qaysi shahardan uchmoqchisiz?", "Қайси шаҳардан учмоқчисиз?")
        case .month: return t("В каком месяце вы планируете совершить Умру?", "Which month would you like to travel?", "Qaysi oyda Umra safarini rejalashtiryapsiz?", "Қайси ойда Умра сафарини режалаштиряпсиз?")
        case .duration: return t("На сколько дней вы планируете поездку?", "How long would you like to travel?", "Safarni necha kunga rejalashtiryapsiz?", "Сафарни неча кунга режалаштиряпсиз?")
        case .route: return t("Какие города вы хотите посетить?", "Which cities would you like to visit?", "Qaysi shaharlarga bormoqchisiz?", "Қайси шаҳарларга бормоқчисиз?")
        case .firstCity: return t("С какого города начнём путешествие?", "Which city shall we visit first?", "Safarni qaysi shahardan boshlaymiz?", "Сафарни қайси шаҳардан бошлаймиз?")
        case .party: return t("Сколько человек отправляется на Умру?", "Who is traveling with you?", "Umraga necha kishi boradi?", "Умрага неча киши боради?")
        case .category: return t("Какой уровень комфорта вы предпочитаете?", "Choose your comfort level", "Qaysi qulaylik darajasini tanlaysiz?", "Қайси қулайлик даражасини танлайсиз?")
        case .assembly: return store.result == nil ? t("Собираем вашу Умру", "Building your Umrah", "Umrangizni tayyorlayapmiz", "Умрангизни тайёрлаяпмиз") : t("Ваша Умра собрана", "Your Umrah is ready", "Umrangiz tayyor", "Умрангиз тайёр")
        }
    }
    private var subtitle: String {
        switch step {
        case .welcome: return t("Расскажите о своих планах. Мы подберём рейсы, отели и услуги в едином пакете.", "Tell us your plans. We'll find flights, hotels and services in one package.", "Rejalaringizni ayting. Reyslar, mehmonxonalar va xizmatlarni bitta paketda topamiz.", "Режаларингизни айтинг. Рейслар, меҳмонхоналар ва хизматларни битта пакетда топамиз.")
        case .origin: return t("Подберём вылет и возвращение в этот город.", "We will match departure and return to this city.", "Shu shahardan borish va qaytish reyslarini topamiz.", "Шу шаҳардан бориш ва қайтиш рейсларини топамиз.")
        case .month: return t("Точные даты подберём автоматически. Вылет — в выбранном месяце.", "We'll find the dates automatically. Departure stays within your chosen month.", "Aniq sanalarni avtomatik topamiz. Uchish tanlangan oyda bo‘ladi.", "Аниқ саналарни автоматик топамиз. Учиш танланган ойда бўлади.")
        case .duration: return t("При необходимости расширим поиск на 3–4 дня.", "We may adjust the duration by 3–4 days to find flights.", "Zarur bo‘lsa, qidiruvni 3–4 kunga kengaytiramiz.", "Зарур бўлса, қидирувни 3–4 кунга кенгайтирамиз.")
        case .route: return t("Выберите маршрут вашей поездки.", "Choose your journey route.", "Safaringiz yo‘nalishini tanlang.", "Сафарингиз йўналишини танланг.")
        case .firstCity: return t("В Мекку — через Джидду. В Медину — через аэропорт Медины.", "Makkah via Jeddah, Madinah via Madinah airport.", "Makkaga Jidda, Madinaga Madina aeroporti orqali.", "Маккага Жидда, Мадинага Мадина аэропорти орқали.")
        case .party: return t("Возраст детей нужен для корректного тарифа.", "Children's ages help determine the right fare.", "To‘g‘ri tarif uchun bolalarning yoshi kerak.", "Тўғри тариф учун болаларнинг ёши керак.")
        case .category: return t("Прокрутите карточки, чтобы сравнить категории.", "Swipe to compare travel categories.", "Toifalarni solishtirish uchun kartalarni suring.", "Тоифаларни солиштириш учун карталарни суринг.")
        case .assembly: return store.result == nil ? t("Проверяем компоненты и рассчитываем стоимость на сервере.", "Checking components and calculating the server price.", "Qismlarni tekshirib, serverda narxni hisoblayapmiz.", "Қисмларни текшириб, серверда нархни ҳисоблаяпмиз.") : t("Проверьте все детали перед бронированием.", "Review every detail before booking.", "Bron qilishdan oldin barcha tafsilotlarni tekshiring.", "Брон қилишдан олдин барча тафсилотларни текширинг.")
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    topBar
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 22) {
                            orbitHeader(width: proxy.size.width)
                            stepContent
                                .id(step)
                                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 10)))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .frame(maxWidth: 570)
                        .frame(maxWidth: .infinity)
                    }
                    footer
                }
            }
            .background(Color.iumrahPageBackground)
            .statusBarHidden(false)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showReview) {
                if let journey = store.result { FinalPackageView().environmentObject(journey) }
            }
        }
        .statusBarHidden(false)
        .environment(\.smartBookingDone, {
            suppressHistory = true
            HomePersonalizationStore.shared.saveSmart(nil, owner: historyOwner)
            onExit()
        })
        .task {
            guard !historyInitialized else { return }
            historyOwner = HomePersonalizationStore.owner(account)
            if let resumeDraft, HomePersonalizationStore.shared.enabled {
                store.preferences = resumeDraft.preferences
                let resumed = Step(rawValue: resumeDraft.step) ?? .origin
                step = steps.contains(resumed) ? resumed : .route
                categoryScroll = store.preferences.tier.rawValue
                // A previously assembled package must get a fresh quote.
                if step == .assembly { runID += 1 }
            }
            historyInitialized = true
        }
        .onChange(of: step) { _, _ in saveActivity() }
        .onChange(of: store.preferences) { _, _ in saveActivity() }
        .onChange(of: store.result != nil) { _, _ in saveActivity() }
        .onChange(of: showReview) { _, presented in if !presented { store.syncReview() } }
        .sheet(isPresented: $airportPicker) {
            AirportPickerView(selection: $store.preferences.airport, fallbackCode: $store.preferences.origin)
                .environmentObject(settings)
        }
        .task(id: replacementRevision) {
            guard let city = replacementRequest, replacementRevision > 0 else { return }
            await store.replaceHotel(city: city)
            replacementRequest = nil
        }
        .task(id: runID) {
            guard runID > 0, step == .assembly else { return }
            await store.assemble()
        }
    }
    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                if step != .welcome {
                    Button { previous() } label: { glassIcon("chevron.left", size: 44, interactive: true) }
                        .buttonStyle(.plain).disabled(store.busy || store.replacingCity != nil)
                        .accessibilityLabel(t("Назад", "Back", "Orqaga", "Орқага"))
                } else {
                    Menu {
                        ForEach(AppSettingsStore.Language.allCases) { language in
                            Button { settings.language = language } label: { Text(language.title) }
                        }
                    } label: { glassIcon("globe", size: 44, interactive: true) }
                    .accessibilityLabel(t("Язык", "Language", "Til", "Тил"))
                }
                Spacer(minLength: 0)
                VStack(spacing: 3) {
                    Text("iumrah Smart").font(.headline)
                    Text(t("Персональная поездка", "Personal journey", "Shaxsiy safar", "Шахсий сафар"))
                        .font(.caption2).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Button { onExit() } label: { glassIcon("xmark", size: 44, interactive: true) }
                    .buttonStyle(.plain).accessibilityLabel(firstLaunch ? t("Пропустить", "Skip", "O‘tkazish", "Ўтказиш") : t("Закрыть", "Close", "Yopish", "Ёпиш"))
            }
            HStack(spacing: 4) {
                ForEach(steps, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.23)).frame(height: 3)
                }
                Text("\((steps.firstIndex(of: step) ?? 0) + 1)/\(steps.count)")
                    .font(.caption2.monospacedDigit()).padding(.leading, 5)
            }
        }
        .padding(.horizontal, 20).padding(.top, 5).padding(.bottom, 13)
        .foregroundStyle(.white)
        // The app's Info.plist uses white status-bar content; this real safe-area
        // surface ensures contrast without drawing a fake status bar.
        .background(Color.black.ignoresSafeArea(edges: .top))
        .environment(\.colorScheme, .dark)
    }

    private func glassIcon(_ symbol: String, size: CGFloat = 48, interactive: Bool = false) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.40, weight: .semibold))
            .frame(width: size, height: size)
            .iumrahGlass(in: Circle(), interactive: interactive, allowsStaticGlass: true)
            .accessibilityHidden(true)
    }

    private var orbitSymbol: String? {
        if step != .assembly { return step.symbol }
        if store.result != nil { return nil }
        switch store.progress {
        case .flights: return "airplane"
        case .hotels: return "building.2.fill"
        case .transfer: return "car.side.fill"
        case .price: return "checkmark.seal"
        case .ready: return nil
        }
    }

    private func orbitHeader(width: CGFloat) -> some View {
        let isWide = width >= 520 && !largeOrbit
        let size = step == .assembly && store.result != nil ? min(190, max(120, width - 44)) : largeOrbit ? min(340, max(160, width - 44)) : min(260, max(160, width - 64))
        let layout = isWide ? AnyLayout(HStackLayout(alignment: .center, spacing: 20)) : AnyLayout(VStackLayout(alignment: .center, spacing: 12))
        return layout {
            IumrahOrbitV5(services: store.result.map { IumrahOrbitV5Service.selectedForJourney($0) } ?? IumrahOrbitV5Service.showcase,
                          diameter: isWide ? 220 : size,
                          logo: Image("HeaderWordmarkLight"), logoWidthFraction: 0.38,
                          accessibilityTitle: "iumrah Smart", pinnedSymbol: orbitSymbol,
                          mergeToCenter: step == .assembly && store.result != nil)
                .frame(maxWidth: isWide ? nil : .infinity)
            VStack(alignment: isWide ? .leading : .center, spacing: 9) {
                Text(title).font(.system(size: largeOrbit ? 30 : 27, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).contentTransition(.opacity)
            }
            .multilineTextAlignment(isWide ? .leading : .center)
            .frame(maxWidth: .infinity, alignment: isWide ? .leading : .center)
        }.animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85), value: store.progress)
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome:
            VStack(alignment: .leading, spacing: 16) {
                welcomeFeature("airplane", t("Рейсы по вашим датам", "Flights for your dates", "Sanangizga mos reyslar", "Санангизга мос рейслар"))
                welcomeFeature("building.2.fill", t("Отели с доступными номерами", "Hotels with available rooms", "Bo‘sh xonali mehmonxonalar", "Бўш хонали меҳмонхоналар"))
                welcomeFeature("checkmark.seal", t("Один пакет и единая стоимость", "One package, one total", "Bitta paket va umumiy narx", "Битта пакет ва умумий нарх"))
            }.padding(16).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
        case .origin: originContent
        case .month: monthContent
        case .duration: durationContent
        case .route: routeContent
        case .firstCity: firstCityContent
        case .party: partyContent
        case .category: categoryContent
        case .assembly: assemblyContent
        }
    }
    private var originContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { airportPicker = true } label: {
                HStack {
                    glassIcon("airplane.departure", interactive: true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.preferences.airport?.city ?? FlightReferenceCatalog.airport(store.preferences.origin)?.city ?? store.preferences.origin).font(.title2.bold())
                        Text(store.preferences.origin).font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            }.buttonStyle(.plain)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(["TAS", "SKD", "FEG", "NMA", "BHK", "UGC", "KSQ", "TMJ"], id: \.self) { code in
                    choice(title: FlightReferenceCatalog.airport(code)?.city ?? code, subtitle: code, selected: store.preferences.origin == code) {
                        store.preferences.origin = code; store.preferences.airport = nil
                    }
                }
            }
        }
    }
    private var monthContent: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        let months = (0..<12).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(months, id: \.self) { month in
                    let selected = calendar.isDate(month, equalTo: store.preferences.month, toGranularity: .month)
                    Button {
                        store.preferences.month = month; IumrahHaptics.selection()
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack { glassIcon("calendar", size: 42); Spacer(); if selected { Image(systemName: "checkmark.circle.fill") } }
                            Spacer()
                            Text(month.formatted(.dateTime.month(.wide).locale(Locale(identifier: settings.language.localeIdentifier))).capitalized).font(.headline)
                            Text(month.formatted(.dateTime.year())).font(.subheadline).opacity(0.7)
                        }
                        .padding(15).frame(width: 146, height: 146, alignment: .leading)
                        .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                        .background(selected ? Color.primary : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 23))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.scrollTargetLayout()
        }.scrollTargetBehavior(.viewAligned)
    }
    private var durationContent: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach([3, 7, 10, 14, 20, 25], id: \.self) { days in
                choice(title: "\(days)", subtitle: t(days == 3 ? "дня" : "дней", "days", "kun", "кун"), selected: store.preferences.duration == days) { store.preferences.duration = days }
            }
        }
    }
    private var routeContent: some View {
        VStack(spacing: 14) {
            Picker(title, selection: $store.preferences.scope) {
                ForEach(JourneyScope.allCases) { scope in Text(scope.title(settings.language)).tag(scope) }
            }.pickerStyle(.segmented)
            choice(title: JourneyScope.makkahOnly.title(settings.language), subtitle: "JED → JED", selected: store.preferences.scope == .makkahOnly) { store.preferences.scope = .makkahOnly }
            choice(title: JourneyScope.makkahAndMadinah.title(settings.language), subtitle: "JED ↔ MED", selected: store.preferences.scope == .makkahAndMadinah) { store.preferences.scope = .makkahAndMadinah }
        }
    }
    private var firstCityContent: some View {
        HStack(spacing: 12) {
            choice(title: t("Мекка", "Makkah", "Makka", "Макка"), subtitle: "JED", selected: store.preferences.firstCity == .jeddah) { store.preferences.firstCity = .jeddah }
            choice(title: t("Медина", "Madinah", "Madina", "Мадина"), subtitle: "MED", selected: store.preferences.firstCity == .madinah) { store.preferences.firstCity = .madinah }
        }
    }
    private var partyContent: some View {
        VStack(spacing: 15) {
            Stepper(value: $store.preferences.adults, in: 1...max(1, 6 - store.preferences.childAges.count)) {
                Text(t("Взрослые", "Adults", "Kattalar", "Катталар") + " · \(store.preferences.adults)").font(.headline)
            }
            Divider()
            HStack {
                Text(t("Дети", "Children", "Bolalar", "Болалар") + " · \(store.preferences.childAges.count)").font(.headline)
                Spacer()
                Button { if !store.preferences.childAges.isEmpty { store.preferences.childAges.removeLast() } } label: { glassIcon("minus", size: 44, interactive: true) }.accessibilityLabel(t("Убрать ребёнка", "Remove child", "Bolani olib tashlash", "Болани олиб ташлаш")).disabled(store.preferences.childAges.isEmpty)
                Button { if store.preferences.adults + store.preferences.childAges.count < 6 { store.preferences.childAges.append(6) } } label: { glassIcon("plus", size: 44, interactive: true) }.accessibilityLabel(t("Добавить ребёнка", "Add child", "Bola qo‘shish", "Бола қўшиш")).disabled(store.preferences.adults + store.preferences.childAges.count >= 6)
            }
            ForEach(store.preferences.childAges.indices, id: \.self) { i in
                Picker(t("Возраст ребёнка", "Child age", "Bolaning yoshi", "Боланинг ёши") + " \(i+1)", selection: Binding(get: { store.preferences.childAges.indices.contains(i) ? store.preferences.childAges[i] : 0 }, set: { age in if store.preferences.childAges.indices.contains(i) { store.preferences.childAges[i] = age } })) {
                    ForEach(0..<12, id: \.self) { age in Text("\(age)").tag(age) }
                }
            }
            if !canContinue { Text(t("На каждого младенца нужен взрослый.", "Each infant needs an adult.", "Har bir chaqaloqqa katta hamroh kerak.", "Ҳар бир чақалоққа катта ҳамроҳ керак.")).font(.footnote).foregroundStyle(.red) }
        }.padding(18).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22)).tint(.primary)
    }
    private var categoryContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PackageTier.allCases) { tier in
                        Button { categoryScroll = tier.rawValue; store.preferences.tier = tier; IumrahHaptics.selection() } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 10) { glassIcon("star.fill", size: 44); Text(tier.selectableHotelStars.sorted().map(String.init).joined(separator: "–") + " ★").font(.caption.weight(.semibold)); Spacer() }
                                Spacer()
                                Text(tier.title(settings.language)).font(.title2.bold())
                                Text(tier.subtitle(settings.language)).font(.subheadline).lineLimit(3)
                            }
                            .padding(18).frame(width: 222, height: 180)
                            .foregroundStyle(store.preferences.tier == tier ? Color(uiColor: .systemBackground) : .primary)
                            .background(store.preferences.tier == tier ? Color.primary : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
                        }.buttonStyle(.plain).id(tier.rawValue)
                    }
                }.scrollTargetLayout()
            }.scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $categoryScroll)
                .onChange(of: categoryScroll) { _, id in if let id, let tier = PackageTier(rawValue: id) { store.preferences.tier = tier } }
            VStack(alignment: .leading, spacing: 10) {
                Text(store.preferences.tier.title(settings.language)).font(.title2.bold())
                Text(store.preferences.tier.subtitle(settings.language)).foregroundStyle(.secondary)
                Label(t("Категория отелей", "Hotel category", "Mehmonxona toifasi", "Меҳмонхона тоифаси") + " · " + store.preferences.tier.selectableHotelStars.map(String.init).joined(separator: " / ") + " ★", systemImage: "building.2.fill")

                Label(t("Рейсы и услуги по правилам iumrah", "Flights and services under existing iumrah rules", "Reyslar va xizmatlar iumrah qoidalari bo‘yicha", "Рейслар ва хизматлар iumrah қоидалари бўйича"), systemImage: "checkmark.seal")
            }.font(.subheadline).id(store.preferences.tier).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.preferences.tier)
    }
    private var assemblyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            progressRow(.flights, title: t("Авиабилеты", "Flights", "Aviachiptalar", "Авиа чипталар"), symbol: "airplane")
            ForEach(Array(store.flightPreview.enumerated()), id: \.offset) { _, flight in
                flightCard(flight)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
            progressRow(.hotels, title: t("Отели и номера", "Hotels and rooms", "Mehmonxonalar va xonalar", "Меҳмонхоналар ва хоналар"), symbol: "building.2.fill")
            ForEach(store.roomPreview) { room in
                hotelCard(room)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
            }
            if let city = store.hotelSearchCity, store.busy {
                Label(t("Проверяем доступные тарифы", "Checking available rates", "Tariflarni tekshiramiz", "Тарифларни текширамиз") + " · " + cityTitle(city), systemImage: "magnifyingglass")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let replacementError = store.replacementError {
                Text(errorText(replacementError, replacing: true)).font(.footnote).foregroundStyle(.secondary)
            }
            progressRow(.transfer, title: t("Маршрут и трансфер", "Route and transfer", "Yo‘nalish va transfer", "Йўналиш ва трансфер"), symbol: "car.side.fill")
            if let vehicle = store.transferPreview { welcomeFeature("car.side.fill", vehicle).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20)) }
            progressRow(.price, title: t("Стоимость пакета", "Package price", "Paket narxi", "Пакет нархи"), symbol: "checkmark.seal")
            if let journey = store.result, let quote = journey.quote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(journey.trip.originCode) → \(journey.trip.outboundDestinationCode) · \(journey.trip.returnOriginCode) → \(journey.trip.originCode)").font(.headline)
                    Text(journey.trip.departureDate.formatted(date: .abbreviated, time: .omitted) + " — " + journey.trip.returnDate.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                    Text(store.connecting ? t("Есть пересадка", "Includes a connection", "Ulanish reysi bor", "Уланиш рейси бор") : t("Прямые рейсы", "Nonstop flights", "To‘g‘ridan-to‘g‘ri reyslar", "Тўғридан-тўғри рейслар")).font(.subheadline.weight(.semibold))
                    Text(IumrahPackageDisplayPrices.money(quote.totalPackagePrice, currency: quote.currency, language: settings.language)).font(.largeTitle.bold())
                    Text(t("Итого за всех путешественников", "Total for all travelers", "Barcha sayohatchilar uchun jami", "Барча саёҳатчилар учун жами")).font(.caption).foregroundStyle(.secondary)
                    Text(IumrahPackageDisplayPrices.money(quote.pricePerPerson, currency: quote.currency, language: settings.language) + " · " + t("на одного паломника", "per pilgrim", "bir ziyoratchi uchun", "бир зиёратчи учун"))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            }
            if let error = store.error {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("Не удалось собрать пакет", "We couldn't build a package", "Paketni tayyorlab bo‘lmadi", "Пакетни тайёрлаб бўлмади")).font(.headline)
                    if error.contains("CORE_CUTOVER_PENDING") {
                        Text(t("Сервер бронирований ещё не готов. Попробуйте позже.", "The booking server is not ready yet. Try again later.", "Bronlash serveri hali tayyor emas. Keyinroq urinib ko‘ring.", "Бронлаш сервери ҳали тайёр эмас. Кейинроқ уриниб кўринг.")).font(.subheadline).foregroundStyle(.secondary)
                    } else if error.contains("SMART_AVIASALES_PARTY_FARE_UNAVAILABLE") {
                        Text(t("Для поездки с детьми пока нет подходящих опубликованных рейсов. Выберите другой месяц или длительность.", "No suitable published flights for your family yet. Try another month or duration.", "Oilaviy safar uchun mos e’lon qilingan reyslar topilmadi. Boshqa oy yoki muddatni tanlang.", "Оилавий сафар учун мос эълон қилинган рейслар топилмади. Бошқа ой ёки муддатни танланг.")).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                    Text(errorText(error)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button(t("Изменить параметры", "Edit preferences", "Parametrlarni o‘zgartirish", "Параметрларни ўзгартириш")) { move(.month); store.clear() }.buttonStyle(.bordered)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.progress)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.roomPreview.map(\.id))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: store.flightPreview.map(\.id))
    }
    private func welcomeFeature(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 12) { glassIcon(symbol, size: 44); Text(title).font(.subheadline.weight(.medium)); Spacer(minLength: 0) }
    }
    private func cityTitle(_ city: String) -> String {
        city == "madinah" ? t("Медина", "Madinah", "Madina", "Мадина") : t("Мекка", "Makkah", "Makka", "Макка")
    }
    private func flightCard(_ flight: FlightOffer) -> some View {
        let formatter = ISO8601DateFormatter()
        let leg = StorefrontFlightLeg(airline: flight.airlinesSummary, flightNumber: flight.flightNumbersSummary,
            airlineCode: flight.primaryAirlineCode ?? "", origin: flight.origin, destination: flight.destination,
            departureAt: formatter.string(from: flight.departureAt), arrivalAt: formatter.string(from: flight.arrivalAt),
            durationMinutes: flight.durationMinutes, stops: flight.stops,
            cabinClass: flight.cabinClass ?? FlightSearchFilters.default.cabinClass.rawValue)
        return VStack(alignment: .leading, spacing: 8) {
            PackageFlightLegDetailCard(leg: leg, direction: flight.direction == .outbound ? t("Туда", "Outbound", "Borish", "Бориш") : t("Обратно", "Return", "Qaytish", "Қайтиш"), language: settings.language)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Вылет", "Departure", "Uchish", "Учиш")).foregroundStyle(.secondary)
                    Text(localFlightTime(flight.departureAt, airport: flight.origin)).fontWeight(.semibold)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(t("Прилёт", "Arrival", "Kelish", "Келиш")).foregroundStyle(.secondary)
                    Text(localFlightTime(flight.arrivalAt, airport: flight.destination)).fontWeight(.semibold)
                }
            }.font(.caption).padding(.horizontal, 12)
            IumrahPackageFlightPriceLine(offer: flight,
                outbound: store.flightPreview.first { $0.direction == .outbound },
                inbound: store.flightPreview.first { $0.direction == .inbound },
                travelers: store.preferences.adults + store.preferences.childAges.count, language: settings.language)
            if let baggage = flight.baggage {
                HStack(spacing: 14) {
                    if let checked = baggage.checked { Label("\(checked) kg", systemImage: "suitcase.rolling") }
                    if let carry = baggage.carryOn { Label("\(carry) kg", systemImage: "bag") }
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
        }
    }
    private func localFlightTime(_ date: Date, airport: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: settings.language.localeIdentifier)
        f.timeZone = FlightReferenceCatalog.timeZone(for: airport) ?? TimeZone(secondsFromGMT: 0)
        f.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return f.string(from: date)
    }
    private func hotelCard(_ room: LocalJourneyRoom) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                AsyncImage(url: room.hotel.coverImageURL.flatMap(URL.init(string:))) { image in image.resizable().scaledToFill() }
                    placeholder: { Color.secondary.opacity(0.12).overlay { glassIcon("building.2", size: 44) } }
                    .frame(width: 108, height: 118).clipShape(RoundedRectangle(cornerRadius: 17))
                VStack(alignment: .leading, spacing: 6) {
                    Text(cityTitle(room.city)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(room.hotel.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(String(repeating: "★", count: room.hotel.roundedStars)).font(.caption)
                    Text(room.rate.roomName).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Label("\(room.adults + room.childrenAges.count)", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    if !room.rate.mealPlan.isEmpty { Text(room.rate.mealPlan).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            Label(room.checkin.formatted(date: .abbreviated, time: .omitted) + " – " + room.checkout.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                .font(.subheadline).foregroundStyle(.secondary)
            if let nightly = IumrahPackageDisplayPrices.nightly(room) {
                IumrahPackageUnitPriceLine(amount: nightly, currency: room.rate.currency,
                    caption: t("В среднем за номер / ночь", "Average per room / night", "Xona / tun uchun o‘rtacha", "Хона / тун учун ўртача"), language: settings.language)
            }
            if store.result != nil && room.id.hasSuffix(":0") {
                Button { replacementRequest = room.city; replacementRevision += 1 } label: {
                    HStack { Text(t("Подобрать другой отель", "Find another hotel", "Boshqa mehmonxona topish", "Бошқа меҳмонхона топиш")); Spacer(); if store.replacingCity == room.city { ProgressView() } else { glassIcon("arrow.clockwise", size: 30) } }
                        .font(.subheadline.weight(.semibold)).padding(12).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).disabled(store.replacingCity != nil)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
    }
    private func errorText(_ error: String, replacing: Bool = false) -> String {
        if replacing { return t("Не удалось подобрать и рассчитать другой отель. Текущий пакет сохранён.", "Could not price another hotel. Your current package is unchanged.", "Boshqa mehmonxona topilmadi. Joriy paket saqlandi.", "Бошқа меҳмонхона топилмади. Жорий пакет сақланди.") }
        if error.contains("SMART_HOTEL_SANDBOX") { return t("Отельный сервис сейчас в тестовом режиме. Реальный пакет недоступен.", "Hotel service is in test mode. A real package is unavailable.", "Mehmonxona xizmati test rejimida. Haqiqiy paket mavjud emas.", "Меҳмонхона хизмати тест режимида. Ҳақиқий пакет мавжуд эмас.") }
        if error.contains("SMART_HOTEL_NETWORK") { return t("Сервис тарифов временно не отвечает. Повторите поиск.", "Hotel rates are temporarily unavailable. Retry the search.", "Tarif xizmati vaqtincha ishlamayapti. Qayta urinib ko‘ring.", "Тариф хизмати вақтинча ишламаяпти. Қайта уриниб кўринг.") }
        if error.contains("SMART_ROOM") || error.contains("SMART_HOTEL") { return t("Не найден подходящий номер с доступным тарифом. Измените месяц или категорию.", "No suitable room with an available rate was found. Change the month or category.", "Mos tarifli xona topilmadi. Oy yoki toifani o‘zgartiring.", "Мос тарифли хона топилмади. Ой ёки тоифани ўзгартиринг.") }
        return t("Попробуйте другой месяц, длительность или категорию. Можно повторить поиск.", "Try another month, duration or category, or retry the search.", "Boshqa oy, muddat yoki toifani tanlang yoki qayta qidiring.", "Бошқа ой, муддат ёки тоифани танланг ёки қайта қидиринг.")
    }
    private func progressRow(_ progress: SmartConfiguratorStore.Progress, title: String, symbol: String) -> some View {
        let done = store.progress.rawValue > progress.rawValue
        return Group { if store.progress.rawValue >= progress.rawValue { HStack(spacing: 12) {
            glassIcon(symbol, size: 46)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(done || store.progress == progress ? .primary : .secondary)
            Spacer()
            if done { Image(systemName: "checkmark.circle.fill") }
            else if store.busy && store.progress == progress { ProgressView() }
            else { Image(systemName: "circle").foregroundStyle(.tertiary) }
        }.accessibilityElement(children: .combine).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8))) } }
    }
    private func choice(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); IumrahHaptics.selection() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack { Spacer(); if selected { Image(systemName: "checkmark.circle.fill") } else { Image(systemName: "circle").opacity(0.35) } }
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).opacity(0.7)
            }.padding(14).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                .foregroundStyle(selected ? Color(uiColor: .systemBackground) : .primary)
                .background(selected ? Color.primary : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var footer: some View {
        VStack(spacing: 12) {
            if step == .assembly, let journey = store.result, journey.hasFinalGeneratorQuote, let quote = journey.quote {
                HStack {
                    Text(t("Итого за всех", "Total for everyone", "Hamma uchun jami", "Ҳамма учун жами")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(IumrahPackageDisplayPrices.money(quote.totalPackagePrice, currency: quote.currency, language: settings.language)).font(.title3.bold()).monospacedDigit()
                }
                HStack {
                    Text(t("На одного паломника", "Per pilgrim", "Bir ziyoratchi uchun", "Бир зиёратчи учун")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(IumrahPackageDisplayPrices.money(quote.pricePerPerson, currency: quote.currency, language: settings.language)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
            Button {
                if step == .assembly { if store.result != nil { showReview = true } else if !store.busy { runID += 1 } }
                else { next() }
            } label: {
                Text(step == .welcome ? t("Начать", "Get started", "Boshlash", "Бошлаш") : step == .assembly ? (store.result != nil ? t("Проверить и забронировать", "Review and book", "Tekshirish va bronlash", "Текшириш ва бронлаш") : t("Повторить поиск", "Retry search", "Qayta qidirish", "Қайта қидириш")) : step == .category ? t("Собрать мою Умру", "Build my Umrah", "Umramni tayyorlash", "Умрамни тайёрлаш") : t("Продолжить", "Continue", "Davom etish", "Давом этиш"))
                    .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(step == .assembly ? (store.busy || store.replacingCity != nil) : !canContinue).opacity((step == .assembly ? (store.busy || store.replacingCity != nil) : !canContinue) ? 0.45 : 1)
        }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 570).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
    }
    private func saveActivity() {
        guard historyInitialized, !suppressHistory, step != .welcome,
              historyOwner == HomePersonalizationStore.owner(account) else { return }
        HomePersonalizationStore.shared.saveSmart(.init(preferences: store.preferences, step: step.rawValue,
            wasAssembled: store.result?.hasFinalGeneratorQuote == true), owner: historyOwner)
    }
    private func move(_ value: Step) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)) { step = value }
        IumrahHaptics.selection()
    }
    private func next() {
        guard let index = steps.firstIndex(of: step), index+1 < steps.count else { return }
        let next = steps[index+1]
        move(next)
        if next == .assembly { runID += 1 }
    }
    private func previous() {
        guard !store.busy, store.replacingCity == nil, let index = steps.firstIndex(of: step), index > 0 else { return }
        if step == .assembly { store.clear() }
        move(steps[index-1])
    }
}

/// Optional dismissal hook used only by the Smart modal after a real booking.
private struct SmartBookingDoneKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }
extension EnvironmentValues {
    var smartBookingDone: (() -> Void)? {
        get { self[SmartBookingDoneKey.self] }
        set { self[SmartBookingDoneKey.self] = newValue }
    }
}

struct SmartConfiguratorHomeCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let onOpen: () -> Void
    private func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String { IumrahFlightCopy.text(settings.language, ru, en, uz, cy) }
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("iumrah Smart").font(.headline); Spacer(); Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)).frame(width: 40, height: 40).iumrahGlass(in: Circle(), interactive: true, allowsStaticGlass: true) }
                GeometryReader { proxy in
                    IumrahOrbitV5(diameter: min(320, min(proxy.size.width, proxy.size.height)), lightOnDark: true, logo: Image("HeaderWordmarkDark"), accessibilityTitle: "iumrah Smart")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }.frame(height: 310)
                Text(t("Расскажите о своих планах. Остальное сделаем мы.", "Tell us your plans. We'll do the rest.", "Rejalaringizni ayting. Qolganini biz qilamiz.", "Режаларингизни айтинг. Қолганини биз қиламиз.")).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(t("Подберём рейсы, отели и услуги в один пакет.", "We'll match flights, hotels and services in one package.", "Reyslar, mehmonxonalar va xizmatlarni bitta paketga jamlaymiz.", "Рейслар, меҳмонхоналар ва хизматларни битта пакетга жамлаймиз.")).font(.subheadline).foregroundStyle(.white.opacity(0.72))
                Text(t("Собрать мою Умру", "Build my Umrah", "Umramni tayyorlash", "Умрамни тайёрлаш")).font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }.padding(20).foregroundStyle(.white).background(.black, in: RoundedRectangle(cornerRadius: 28)).environment(\.colorScheme, .dark)
        }.buttonStyle(.plain).accessibilityIdentifier("iumrah.smart.home")
    }
}
