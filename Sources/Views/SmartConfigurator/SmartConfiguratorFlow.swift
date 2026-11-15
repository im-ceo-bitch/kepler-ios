import SwiftUI

/// One flow for first launch and the Home Smart card. A private journey is
/// deliberately isolated from any partially assembled manual configurator.
struct SmartConfiguratorFlow: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = SmartConfiguratorStore()
    @State private var step: Step = .welcome
    @State private var airportPicker = false
    @State private var showReview = false
    @State private var runID = 0
    @State private var categoryScroll: String? = PackageTier.standard.rawValue
    var firstLaunch: Bool = false
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
            .background(Color(uiColor: .systemBackground))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showReview) {
                if let journey = store.result { FinalPackageView().environmentObject(journey) }
            }
        }
        .environment(\.smartBookingDone, onExit)
        .sheet(isPresented: $airportPicker) {
            AirportPickerView(selection: $store.preferences.airport, fallbackCode: $store.preferences.origin)
                .environmentObject(settings)
        }
        .task(id: runID) {
            guard runID > 0, step == .assembly else { return }
            await store.assemble()
        }
    }
    private var topBar: some View {
        HStack {
            if step != .welcome {
                Button { previous() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }.disabled(store.busy).accessibilityLabel(t("Назад", "Back", "Orqaga", "Орқага"))
            } else {
                Menu {
                    ForEach(AppSettingsStore.Language.allCases) { language in
                        Button { settings.language = language } label: { Text(language.title) }
                    }
                } label: { Image(systemName: "globe").font(.title2).frame(width: 44, height: 44) }
            }
            Spacer()
            Text("iumrah Smart").font(.subheadline.weight(.semibold))
            Spacer()
            Button(firstLaunch ? t("Пропустить", "Skip", "O‘tkazish", "Ўтказиш") : t("Закрыть", "Close", "Yopish", "Ёпиш")) { onExit() }
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 49)
        .foregroundStyle(.primary)
    }
    private func orbitHeader(width: CGFloat) -> some View {
        let layout = largeOrbit ? AnyLayout(VStackLayout(alignment: .center, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            IumrahOrbitV5(diameter: largeOrbit ? min(330, max(200, width - 48)) : 128,
                          logo: Image("HeaderWordmarkLight"), logoWidthFraction: 0.38,
                          accessibilityTitle: "iumrah Smart", pinnedSymbol: step.symbol, mergeToCenter: step == .assembly && store.result != nil)
            VStack(alignment: largeOrbit ? .center : .leading, spacing: 9) {
                Text(title).font(.system(size: largeOrbit ? 30 : 23, weight: .bold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(largeOrbit ? .center : .leading)
            .frame(maxWidth: .infinity, alignment: largeOrbit ? .center : .leading)
        }
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case .welcome: EmptyView()
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
                    Image(systemName: "airplane.departure").font(.title2)
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
                            HStack { Image(systemName: "calendar").font(.title2); Spacer(); if selected { Image(systemName: "checkmark.circle.fill") } }
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
                Button { if !store.preferences.childAges.isEmpty { store.preferences.childAges.removeLast() } } label: { Image(systemName: "minus.circle.fill").font(.title) }.disabled(store.preferences.childAges.isEmpty)
                Button { if store.preferences.adults + store.preferences.childAges.count < 6 { store.preferences.childAges.append(6) } } label: { Image(systemName: "plus.circle.fill").font(.title) }.disabled(store.preferences.adults + store.preferences.childAges.count >= 6)
            }
            ForEach(store.preferences.childAges.indices, id: \.self) { i in
                Picker(t("Возраст ребёнка", "Child age", "Bolaning yoshi", "Боланинг ёши") + " \(i+1)", selection: $store.preferences.childAges[i]) {
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
                                HStack(spacing: 3) { ForEach(0..<tier.primaryHotelStars, id: \.self) { _ in Image(systemName: "star.fill").font(.caption) }; Spacer() }
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
                if store.preferences.tier == .comfort {
                    Text(t("Отели 4★. Расчёт по действующему тарифу Стандарт.", "4★ hotels. Existing Standard pricing rules apply.", "4★ mehmonxonalar. Standart tarif qoidalari amal qiladi.", "4★ меҳмонхоналар. Стандарт тариф қоидалари амал қилади.")).foregroundStyle(.secondary)
                }
                Label(t("Рейсы и услуги по правилам iumrah", "Flights and services under existing iumrah rules", "Reyslar va xizmatlar iumrah qoidalari bo‘yicha", "Рейслар ва хизматлар iumrah қоидалари бўйича"), systemImage: "checkmark.seal")
            }.font(.subheadline).id(store.preferences.tier).transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 8)))
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: store.preferences.tier)
    }
    private var assemblyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            progressRow(.flights, title: t("Подбираем авиарейсы", "Matching flights", "Reyslarni topamiz", "Рейсларни топамиз"), symbol: "airplane")
            progressRow(.hotels, title: t("Подбираем отели и номера", "Matching hotels and rooms", "Mehmonxona va xonalarni topamiz", "Меҳмонхона ва хоналарни топамиз"), symbol: "building.2.fill")
            progressRow(.transfer, title: t("Формируем маршрут и трансфер", "Planning route and transfer", "Yo‘nalish va transferni tuzamiz", "Йўналиш ва трансферни тузамиз"), symbol: "car.side.fill")
            progressRow(.price, title: t("Рассчитываем стоимость пакета", "Calculating package price", "Paket narxini hisoblaymiz", "Пакет нархини ҳисоблаймиз"), symbol: "checkmark.seal")
            if let journey = store.result, let quote = journey.quote {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(journey.trip.originCode) → \(journey.trip.outboundDestinationCode) · \(journey.trip.returnOriginCode) → \(journey.trip.originCode)").font(.headline)
                    Text(journey.trip.departureDate.formatted(date: .abbreviated, time: .omitted) + " — " + journey.trip.returnDate.formatted(date: .abbreviated, time: .omitted)).font(.subheadline)
                    Text(store.connecting ? t("Есть пересадка", "Includes a connection", "Ulanish reysi bor", "Уланиш рейси бор") : t("Прямые рейсы", "Nonstop flights", "To‘g‘ridan-to‘g‘ri reyslar", "Тўғридан-тўғри рейслар")).font(.subheadline.weight(.semibold))
                    Text(NSDecimalNumber(decimal: quote.totalPackagePrice).doubleValue.formatted(.currency(code: quote.currency))).font(.largeTitle.bold())
                    Text(t("Итого за всех путешественников", "Total for all travelers", "Barcha sayohatchilar uchun jami", "Барча саёҳатчилар учун жами")).font(.caption).foregroundStyle(.secondary)
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
                    Text(t("Попробуйте другой месяц, длительность или категорию. Можно повторить поиск.", "Try a different month, duration or category, or retry the search.", "Boshqa oy, muddat yoki toifani tanlang yoki qayta qidiring.", "Бошқа ой, муддат ёки тоифани танланг ёки қайта қидиринг.")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button(t("Изменить параметры", "Edit preferences", "Parametrlarni o‘zgartirish", "Параметрларни ўзгартириш")) { move(.month); store.clear() }.buttonStyle(.bordered)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: store.progress)
    }
    private func progressRow(_ progress: SmartConfiguratorStore.Progress, title: String, symbol: String) -> some View {
        let done = store.progress.rawValue > progress.rawValue
        return Group { if store.progress.rawValue >= progress.rawValue { HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 42, height: 42).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
            HStack(spacing: 5) {
                ForEach(steps, id: \.rawValue) { item in
                    Capsule().fill(item.rawValue <= step.rawValue ? Color.primary : Color.secondary.opacity(0.20)).frame(height: 4)
                }
            }.accessibilityHidden(true)
            Button {
                if step == .assembly { if store.result != nil { showReview = true } else if !store.busy { runID += 1 } }
                else { next() }
            } label: {
                Text(step == .welcome ? t("Начать", "Get started", "Boshlash", "Бошлаш") : step == .assembly ? (store.result != nil ? t("Посмотреть поездку", "Review journey", "Safarni ko‘rish", "Сафарни кўриш") : t("Повторить поиск", "Retry search", "Qayta qidirish", "Қайта қидириш")) : step == .category ? t("Собрать мою Умру", "Build my Umrah", "Umramni tayyorlash", "Умрамни тайёрлаш") : t("Продолжить", "Continue", "Davom etish", "Давом этиш"))
                    .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(Color.primary, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).disabled(step == .assembly ? store.busy : !canContinue).opacity((step == .assembly ? store.busy : !canContinue) ? 0.45 : 1)
        }.padding(.horizontal, 20).padding(.vertical, 12).frame(maxWidth: 570).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
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
        guard !store.busy, let index = steps.firstIndex(of: step), index > 0 else { return }
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
                HStack { Text("iumrah Smart").font(.headline); Spacer(); Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)) }
                IumrahOrbitV5(diameter: 240, lightOnDark: true, logo: Image("HeaderWordmarkDark"), accessibilityTitle: "iumrah Smart")
                    .frame(maxWidth: .infinity)
                Text(t("Расскажите о своих планах. Остальное сделаем мы.", "Tell us your plans. We'll do the rest.", "Rejalaringizni ayting. Qolganini biz qilamiz.", "Режаларингизни айтинг. Қолганини биз қиламиз.")).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(t("Подберём рейсы, отели и услуги в один пакет.", "We'll match flights, hotels and services in one package.", "Reyslar, mehmonxonalar va xizmatlarni bitta paketga jamlaymiz.", "Рейслар, меҳмонхоналар ва хизматларни битта пакетга жамлаймиз.")).font(.subheadline).foregroundStyle(.white.opacity(0.72))
                Text(t("Собрать мою Умру", "Build my Umrah", "Umramni tayyorlash", "Умрамни тайёрлаш")).font(.headline).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14).background(.white, in: RoundedRectangle(cornerRadius: 16))
            }.padding(20).foregroundStyle(.white).background(.black, in: RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain).accessibilityIdentifier("iumrah.smart.home")
    }
}
