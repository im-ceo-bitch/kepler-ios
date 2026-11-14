import SwiftUI
import MapKit
import CoreLocation

enum NuiteeCopy {
    static func text(_ ru: String, _ uz: String, _ en: String, _ lang: AppSettingsStore.Language) -> String {
        switch lang {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cyrillic(uz)
        default: return en
        }
    }
    private static func cyrillic(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "[‘’ʻʼ`]", with: "'", options: .regularExpression)
        let table = ["a":"а","b":"б","d":"д","e":"е","f":"ф","g":"г","h":"ҳ","i":"и","j":"ж","k":"к","l":"л","m":"м","n":"н","o":"о","p":"п","q":"қ","r":"р","s":"с","t":"т","u":"у","v":"в","x":"х","y":"й","z":"з","sh":"ш","ch":"ч","yo":"ё","yu":"ю","ya":"я","o'":"ў","g'":"ғ","'":"ъ"]
        guard let regex = try? NSRegularExpression(pattern: "o'|g'|sh|ch|yo|yu|ya|[a-z']", options: .caseInsensitive) else { return text }
        let result = NSMutableString(string: normalized)
        for match in regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).reversed() {
            let token = (normalized as NSString).substring(with: match.range)
            let translated = table[token.lowercased()] ?? token
            result.replaceCharacters(in: match.range, with: token.first?.isUppercase == true ? translated.uppercased() : translated)
        }
        return result as String
    }

}

enum NuiteeCity: String, CaseIterable {
    case makkah, madinah
    func title(_ lang: AppSettingsStore.Language) -> String {
        self == .makkah ? NuiteeCopy.text("Мекка", "Makka", "Makkah", lang)
            : NuiteeCopy.text("Медина", "Madina", "Madinah", lang)
    }
}

@MainActor
final class NuiteeCatalogModel: ObservableObject {
    @Published var hotels: [NuiteeHotel] = [] { didSet { revision &+= 1 } }
    private(set) var revision = 0
    @Published var sandbox = true
    @Published var catalogStale = false
    @Published var rateError: String?
    @Published var busy = false
    @Published var errorMessage: String?
    private let service = NuiteeHotelService()
    private var generation = UUID()

    func reload(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int, forceRefresh: Bool = false) async {
        let version = UUID()
        generation = version
        defer { if generation == version { busy = false } }
        if !forceRefresh, let cached = await service.cachedHotels(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults) {
            guard generation == version, !Task.isCancelled else { return }
            errorMessage = nil
            applyRates(cached)
            busy = false
            return
        }
        guard generation == version, !Task.isCancelled else { return }
        busy = true
        hotels = [] // Never show old city/date prices while loading a new request.
        errorMessage = nil
        rateError = nil
        do {
            let catalog = try await service.hotels(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults, catalogOnly: true, forceRefresh: forceRefresh)
            guard generation == version, !Task.isCancelled else { return }
            hotels = catalog.hotels.map { hotel in
                var row = hotel
                row.rateStatus = row.minimumRate != nil ? "available" : "loading"
                return row
            }
            sandbox = catalog.sandbox
            catalogStale = catalog.hotelCatalogStale
            let response = try await service.hotels(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults, forceRefresh: forceRefresh)
            guard generation == version, !Task.isCancelled else { return }
            applyRates(response)
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            if hotels.isEmpty { errorMessage = error.localizedDescription }
            else {
                rateError = error.localizedDescription
                hotels = hotels.map { hotel in
                    var updated = hotel
                    updated.rateStatus = "provider_error"
                    return updated
                }
            }
        }
    }

    private func applyRates(_ response: NuiteeHotelListEnvelope) {
        // Older deployed adapters do not return rateStatus. Derive it from
        // the completed response, never from elapsed time or sandbox mode.
        hotels = response.hotels.map { hotel in
            var row = hotel
            row.rateStatus = row.minimumRate != nil ? (response.pricesStale ? "cached" : "available")
                : response.rateError != nil ? "provider_error" : "no_availability"
            return row
        }
        sandbox = response.sandbox
        catalogStale = response.hotelCatalogStale || response.pricesStale
        rateError = response.rateError
    }
}

struct NuiteeHotelsCatalogView: View {
    let refreshSignal: Int
    var initialHotelQuery: String = ""
    var searchOverride: IumrahHotelTabSearch? = nil
    var showsSearchControls = true
    var onManualRoom: ((LocalJourneyRoom) -> Void)? = nil
    @State private var manualMeals = HotelMealChoices()
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    @StateObject private var model: NuiteeCatalogModel
    @State private var appliedHomeSearchID: UUID?
    @State private var homeSearchRevision = 0
    @State private var city: NuiteeCity = .makkah
    @State private var stars = 0
    @State private var hotelQuery = ""
    @State private var calendarPresented = false
    @FocusState private var hotelSearchFocused: Bool
    @State private var checkin = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
    @State private var nights = 1
    @State private var adults = 2
    @State private var draftCheckin = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
    @State private var draftNights = 1
    @State private var draftAdults = 2
    @State private var searchExpanded = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastLoadedDay: Date?
    @State private var visibleCount = 20
    private struct FilterKey: Equatable { let revision: Int; let stars: Int; let query: String }
    private struct FilterResult { let candidateCount: Int; let matches: [NuiteeHotel]; let alternatives: [NuiteeHotel] }
    @State private var filterMemo = IumrahViewMemo<FilterKey, FilterResult>()
    @State private var opened: NuiteeHotel?
    @State private var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "iumrah.nuitee.favorites.v1") ?? [])

    init(refreshSignal: Int, initialHotelQuery: String = "", searchOverride: IumrahHotelTabSearch? = nil,
         showsSearchControls: Bool = true, model: NuiteeCatalogModel? = nil, onManualRoom: ((LocalJourneyRoom) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model ?? NuiteeCatalogModel())
        self.refreshSignal = refreshSignal
        self.initialHotelQuery = initialHotelQuery
        self.searchOverride = searchOverride
        self.showsSearchControls = showsSearchControls
        self.onManualRoom = onManualRoom
        _hotelQuery = State(initialValue: initialHotelQuery)
        if let request = searchOverride {
            _city = State(initialValue: request.city == "madinah" ? .madinah : .makkah)
            _checkin = State(initialValue: request.checkin)
            _nights = State(initialValue: min(28, max(1, request.nights)))
            _adults = State(initialValue: min(6, max(1, request.adults)))
            _draftCheckin = State(initialValue: request.checkin)
            _draftNights = State(initialValue: min(28, max(1, request.nights)))
            _draftAdults = State(initialValue: min(6, max(1, request.adults)))
            _appliedHomeSearchID = State(initialValue: request.id)
        }
    }

    private var checkout: Date { Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin }
    private var reloadIdentity: String {
        [city.rawValue, String(checkin.timeIntervalSince1970), String(nights), String(adults), String(homeSearchRevision), String(refreshSignal)].joined(separator: ":")
    }
    private var normalizedQuery: String { hotelQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func filteredHotels() -> FilterResult {
        filterMemo.value(for: FilterKey(revision: model.revision, stars: stars, query: normalizedQuery)) {
            let candidates = model.hotels.filter { stars == 0 || $0.roundedStars == stars }
            let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            let matches = terms.isEmpty ? candidates : candidates.filter { hotel in
                let haystack = hotel.name + " " + (hotel.address ?? "")
                return terms.allSatisfy { haystack.localizedStandardContains($0) }
            }
            let alternatives = !terms.isEmpty && matches.isEmpty
                ? Array(candidates.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }.prefix(8)) : []
            return FilterResult(candidateCount: candidates.count, matches: matches, alternatives: alternatives)
        }
    }

    var body: some View {
        let snapshot = filteredHotels()
        LazyVStack(alignment: .leading, spacing: 16) {
            if showsSearchControls {
            IumrahGraphiteSearchSurface(
                isExpanded: $searchExpanded,
                summary: normalizedQuery.isEmpty ? city.title(settings.language) : normalizedQuery,
                subtitle: "\(checkin.formatted(date: .abbreviated, time: .omitted)) · \(nights) "
                    + NuiteeCopy.text("ночь · ", "tun · ", "night(s) · ", settings.language)
                    + "\(adults) " + NuiteeCopy.text("гостя", "mehmon", "guests", settings.language)
            ) {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(NuiteeCopy.text("Название отеля, например Hilton Makkah", "Mehmonxona nomi, masalan Hilton Makkah", "Hotel name, e.g. Hilton Makkah", settings.language), text: $hotelQuery)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($hotelSearchFocused)
                            .submitLabel(.search)
                            .onSubmit { hotelSearchFocused = false; searchExpanded = false }
                        if !hotelQuery.isEmpty {
                            Button { hotelQuery = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }.accessibilityLabel(NuiteeCopy.text("Очистить поиск", "Qidiruvni tozalash", "Clear search", settings.language))
                        }
                    }
                    .padding(13)
                    .background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                    HStack(spacing: 12) {
                        Label(NuiteeCopy.text("Даты проживания", "Yashash sanalari", "Stay dates", settings.language), systemImage: "calendar")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            hotelSearchFocused = false
                            calendarPresented = true
                        } label: {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(draftCheckin.formatted(date: .abbreviated, time: .omitted))
                                Text("\(draftNights) " + NuiteeCopy.text("ночь", "tun", "night(s)", settings.language))
                                    .font(.caption2)
                            }
                            .foregroundStyle(Color.primary)
                        }.buttonStyle(.plain)
                    }
                    Divider()
                    HStack(spacing: 12) {
                        Label(NuiteeCopy.text("Ночей", "Tunlar", "Nights", settings.language), systemImage: "moon")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Stepper("\(draftNights)", value: $draftNights, in: 1...28)
                            .fixedSize()
                    }
                    Divider()
                    Stepper(value: $draftAdults, in: 1...6) {
                        Label("\(draftAdults) " + NuiteeCopy.text("взрослых", "katta", "adults", settings.language), systemImage: "person.2")
                            .font(.subheadline.weight(.semibold))
                    }
                    Button {
                        checkin = draftCheckin
                        nights = draftNights
                        adults = draftAdults
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            searchExpanded = false
                        }
                        IumrahHaptics.selection()
                        // Search by name operates on the already loaded catalogue; only
                        // stay parameters trigger a supplier rate refresh.
                    } label: {
                        Label(NuiteeCopy.text("Найти отели", "Mehmonxonalarni topish", "Find hotels", settings.language), systemImage: "magnifyingglass")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity).frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            Picker("City", selection: $city) {
                ForEach(NuiteeCity.allCases, id: \.self) { item in
                    Text(item.title(settings.language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: city) { _, _ in stars = 0; visibleCount = 20; hotelQuery = "" }


            }

            Picker(NuiteeCopy.text("Звёзды", "Yulduzlar", "Stars", settings.language), selection: $stars) {
                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { star in
                    Text(star == 0 ? NuiteeCopy.text("Все", "Barchasi", "All", settings.language) : "\(star) ★").tag(star)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .onChange(of: stars) { _, _ in visibleCount = 20 }

            if model.busy && model.hotels.isEmpty {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
            } else if let error = model.errorMessage {
                VStack(spacing: 10) {
                    Text(NuiteeCopy.text("Не удалось загрузить каталог", "Katalog yuklanmadi", "Could not load hotels", settings.language))
                        .font(.headline)
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button(NuiteeCopy.text("Повторить", "Qayta", "Retry", settings.language)) {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
                }
                .frame(maxWidth: .infinity).padding(25)
            } else if snapshot.candidateCount == 0 && !model.busy {
                ContentUnavailableView(NuiteeCopy.text("Нет отелей", "Mehmonxonalar topilmadi", "No hotels", settings.language), systemImage: "building.2", description: Text(NuiteeCopy.text("Попробуйте другой фильтр или даты", "Filtr yoki sanani almashtiring", "Change stars or dates", settings.language)))
            } else {
                if !normalizedQuery.isEmpty {
                    Text(NuiteeCopy.text("Результаты поиска", "Qidiruv natijalari", "Search results", settings.language))
                        .font(.headline)
                }
                HStack {
                    Text("\(snapshot.matches.count) " + NuiteeCopy.text("отелей", "mehmonxona", "hotels", settings.language))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if snapshot.matches.isEmpty && !normalizedQuery.isEmpty {
                    Text(NuiteeCopy.text("Точных совпадений нет. Ниже — другие отели города.", "Mos mehmonxona topilmadi. Quyida boshqa variantlar.", "No matching hotels. Explore other stays below.", settings.language))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 12) {
                    ForEach(Array(snapshot.matches.prefix(visibleCount))) { hotel in
                        NuiteeHotelListingCard(
                            hotel: hotel, nights: nights, adults: adults, sandbox: model.sandbox,
                            favorite: favorites.contains(hotel.id),
                            onOpen: { opened = hotel }, onFavorite: { toggleFavorite(hotel.id) }
                        )
                    }
                    IumrahLoadMoreButton(remaining: snapshot.matches.count - visibleCount) { visibleCount += 20 }
                }
                if !snapshot.alternatives.isEmpty {
                    Text(NuiteeCopy.text("Похожие отели в городе", "Shahardagi o‘xshash mehmonxonalar", "Alternative hotels nearby", settings.language))
                        .font(.headline).padding(.top, 12)
                    LazyVStack(spacing: 12) {
                        ForEach(snapshot.alternatives) { hotel in
                            NuiteeHotelListingCard(
                                hotel: hotel, nights: nights, adults: adults, sandbox: model.sandbox,
                                favorite: favorites.contains(hotel.id),
                                onOpen: { opened = hotel }, onFavorite: { toggleFavorite(hotel.id) }
                            )
                        }
                    }
                }
            }
        }
        .task(id: reloadIdentity) { await reload() }
        .onChange(of: hotelQuery) { _, _ in visibleCount = 20 }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refreshIfNewDay() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshIfNewDay() } }
        }
        .onAppear {
            hotelQuery = initialHotelQuery
            consumeHomeSearch(searchOverride ?? chrome.requestedHotelTabSearch)
            if !initialHotelQuery.isEmpty { hotelQuery = initialHotelQuery }
        }
        .onChange(of: searchOverride) { _, search in
            consumeHomeSearch(search)
            hotelQuery = initialHotelQuery
        }
        .onChange(of: initialHotelQuery) { _, value in hotelQuery = value }
        .onChange(of: chrome.requestedHotelTabSearch) { _, request in
            consumeHomeSearch(request)
        }

        .sheet(isPresented: $calendarPresented) {
            NuiteeStayCalendarSheet(checkin: $draftCheckin, nights: $draftNights)
        }
        .navigationDestination(item: $opened) { hotel in
            if let onManualRoom {
                NuiteeHotelDetailView(hotel: hotel, checkin: checkin, nights: nights, adults: adults, sandbox: model.sandbox,
                    onSelectRate: { rate in
                        guard rate.currency == "USD", rate.price.isFinite, rate.price > 0 else { return }
                        onManualRoom(LocalJourneyRoom(id: "\(city.rawValue):0", city: city.rawValue, hotel: hotel, rate: rate, checkin: checkin, checkout: checkout, adults: adults, childrenAges: [], meals: manualMeals))
                    }, onSelectMeals: { manualMeals = $0 })
            } else {
                NuiteeHotelDetailView(hotel: hotel, checkin: checkin, nights: nights, adults: adults, sandbox: model.sandbox)
            }
        }
    }

    /// Apply Home's request in-place; this view remains the single supplier-backed
    /// search/results surface, including its existing filters and hotel details.
    private func consumeHomeSearch(_ request: IumrahHotelTabSearch?) {
        guard let request, appliedHomeSearchID != request.id else { return }
        appliedHomeSearchID = request.id
        homeSearchRevision += 1 // Repeat searches with identical dates still refresh supplier rates.
        city = request.city == "madinah" ? .madinah : .makkah
        checkin = request.checkin
        nights = min(28, max(1, request.nights))
        adults = min(6, max(1, request.adults))
        draftCheckin = checkin
        draftNights = nights
        draftAdults = adults
        hotelQuery = ""
        stars = 0
        visibleCount = 20
        searchExpanded = false
        hotelSearchFocused = false
    }

    private func refreshIfNewDay() async {
        guard let lastLoadedDay, !Calendar.current.isDateInToday(lastLoadedDay) else { return }
        await reload()
    }

    private func reload() async {
        lastLoadedDay = Date()
        visibleCount = 20
        await model.reload(city: city, checkin: checkin, checkout: checkout, adults: adults)
    }
    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "iumrah.nuitee.favorites.v1")
    }
}

struct NuiteeHotelListingCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let hotel: NuiteeHotel
    let nights: Int
    let adults: Int
    let sandbox: Bool
    let favorite: Bool
    let onOpen: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.43
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    NuiteeCatalogPreviewCollage(hotel: hotel)
                        .frame(width: width, height: 232)
                    HStack(spacing: 5) {
                        Button(action: onFavorite) {
                            Image(systemName: favorite ? "heart.fill" : "heart")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: hotel.name + " — " + (hotel.address ?? hotel.city)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }.padding(8)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(hotel.name)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        if hotel.roundedStars > 0 {
                            Text(String(repeating: "★", count: hotel.roundedStars))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.primary)
                        }
                        if let rating = hotel.rating { Text(String(format: "%.1f", rating)).font(.caption).foregroundStyle(.secondary) }
                    }
                    Label(L10n.city(hotel.city, settings.language), systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let rate = hotel.minimumRate, rate.price > 0 {
                        if sandbox {
                            Text(NuiteeCopy.text("Тестовый тариф", "Sinov tarifi", "Test rate", settings.language)).font(.caption2)
                        } else if hotel.rateStatus == "cached" {
                            Text(NuiteeCopy.text("Сохранённая цена", "Saqlangan narx", "Cached price", settings.language)).font(.caption2)
                        }
                        Text(NuiteeHotelService.usd(rate.price))
                            .font(.system(size: 23, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(nights) " + NuiteeCopy.text("ночь · 1 номер · ", "tun · 1 xona · ", "nights · 1 room · ", settings.language) + "\(adults) " + NuiteeCopy.text("гостя", "mehmon", "guests", settings.language))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        if hotel.rateStatus == "not_requested" || hotel.rateStatus == "loading" {
                            ProgressView().controlSize(.small)
                            Text(NuiteeCopy.text("Загружаем цену…", "Narx yuklanmoqda…", "Loading price…", settings.language)).font(.caption)
                        } else {
                            Text(hotel.rateStatus == "provider_error"
                                 ? NuiteeCopy.text("Не удалось загрузить цену", "Narxni yuklab bo‘lmadi", "Could not load price", settings.language)
                                 : NuiteeCopy.text("Нет тарифа на эти даты", "Bu sanalar uchun tarif yo‘q", "No rate for these dates", settings.language)).font(.caption)
                        }
                    }
                    HStack { Spacer(); Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary) }

                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: 232)
        }
        .frame(height: 232)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture(perform: onOpen)
    }
}

private struct NuiteeHotelCollage: View {
    let images: [String]
    var body: some View {
        GeometryReader { box in
            if images.count < 2 {
                HotelCachedImage(rawURL: images.first, thumbnailPixelDimension: 512)
                    .frame(width: box.size.width, height: box.size.height)
                    .clipped()
            } else if images.count == 2 {
                VStack(spacing: 3) {
                    HotelCachedImage(rawURL: images[0], thumbnailPixelDimension: 512)
                        .frame(height: box.size.height * 0.64)
                        .clipped()
                    HotelCachedImage(rawURL: images[1], thumbnailPixelDimension: 512)
                        .frame(height: box.size.height * 0.36 - 3)
                        .clipped()
                }
            } else {
            let gap: CGFloat = 3
            let upper = box.size.height * 0.64
            VStack(spacing: gap) {
                HotelCachedImage(rawURL: images.first, thumbnailPixelDimension: 512).frame(height: upper).clipped()
                HStack(spacing: gap) {
                    HotelCachedImage(rawURL: images.count > 1 ? images[1] : nil, thumbnailPixelDimension: 512)
                    HotelCachedImage(rawURL: images.count > 2 ? images[2] : nil, thumbnailPixelDimension: 512)
                }
                .frame(height: max(0, box.size.height - upper - gap))
            }
            }
        }.clipped()
    }
}

struct NuiteeHotelDetailView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    let hotel: NuiteeHotel
    @State var checkin: Date
    @State var nights: Int
    @State var adults: Int
    let sandbox: Bool
    var childrenAges: [Int] = []
    var onSelectRate: ((NuiteeRoomRate) -> Void)? = nil
    var onSelectMeals: ((HotelMealChoices) -> Void)? = nil
    @State var selectedMeals = HotelMealChoices()

    @State private var showAllAmenities = false
    @State private var detail: NuiteeHotelDetail?
    @State private var rates: [NuiteeRoomRate] = []
    @State private var detailError: String?
    @State private var ratesError: String?
    @State private var ratesLoading = true
    @State private var ratesCompleted = false
    @State private var ratesSandbox = false
    @State private var ratesRequestID = UUID()
    @State private var isGalleryPresented = false
    @State private var showSaveConfirmation = false
    @State private var chosenOffer: NuiteeRoomRate?
    @State private var expandedRoomRate: NuiteeRoomRate?
    private let service = NuiteeHotelService()

    private var checkout: Date { Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin }
    private var reloadID: String { "\(hotel.id):\(checkin.timeIntervalSince1970):\(nights):\(adults):\(settings.language.rawValue)" }
    private var photos: [String] {
        let list = detail?.images ?? []
        return list.isEmpty ? [hotel.coverImageURL].compactMap { $0 } : list
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                collage
                VStack(alignment: .leading, spacing: 9) {
                    Text(hotel.name).font(.system(size: 30, weight: .bold, design: .rounded))
                    if hotel.roundedStars > 0 {
                        Text(String(repeating: "★", count: hotel.roundedStars)).foregroundStyle(Color.primary)
                    }
                    if let rating = hotel.rating {
                        Text(String(format: "%.1f / 10", rating)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    if let address = detail?.address ?? hotel.address, !address.isEmpty {
                        Label(address, systemImage: "mappin.and.ellipse")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if let detail {
                    if !detail.amenities.isEmpty {
                        sectionTitle(NuiteeCopy.text("Удобства отеля", "Mehmonxona imkoniyatlari", "Hotel amenities", settings.language))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            ForEach(Array(showAllAmenities ? detail.amenities : Array(detail.amenities.prefix(8))), id: \.self) { label in
                                Label(label, systemImage: "checkmark.circle")
                                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if detail.amenities.count > 8 {
                        Button(NuiteeCopy.text(showAllAmenities ? "Скрыть удобства" : "Все удобства", showAllAmenities ? "Yashirish" : "Barcha qulayliklar", showAllAmenities ? "Show less" : "All amenities", settings.language)) {
                            withAnimation { showAllAmenities.toggle() }
                        }.tint(.primary)
                    }
                    if !detail.description.isEmpty {
                        sectionTitle(NuiteeCopy.text("Об отеле", "Mehmonxona haqida", "About this hotel", settings.language))
                        Text(detail.description).font(.subheadline)
                    }
                }
                IumrahHotelStaySummary(checkin: checkin, checkout: checkout, nights: nights,
                    adults: adults, children: childrenAges.count, checkinTime: detail?.checkin,
                    checkoutTime: detail?.checkout, editableStay: onSelectRate == nil ? AnyView(staySelector) : nil)
                if onSelectRate != nil {
                    IumrahHotelMealsEditor(selection: $selectedMeals, stars: hotel.roundedStars,
                        city: hotel.city, included: commonSupplierMeals)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26))
                }
                IumrahHotelReviewsSection(hotelID: hotel.id, rating: detail?.rating ?? hotel.rating,
                                          reviewCount: detail?.reviewCount ?? hotel.reviewCount)
                sectionTitle(NuiteeCopy.text("Выберите номер", "Xona tanlang", "Choose a room", settings.language))
                if ratesLoading { ProgressView().frame(maxWidth: .infinity).padding(22) }
                else if ratesError != nil {
                    Label(NuiteeCopy.text("Не удалось загрузить цены", "Narxlarni yuklab bo‘lmadi", "Could not load prices", settings.language), systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(NuiteeCopy.text("Повторить", "Qayta urinish", "Retry", settings.language)) { Task { await refreshRates() } }.tint(.primary)
                } else if rates.isEmpty {
                    Text(NuiteeCopy.text("На выбранные даты нет доступных тарифов.", "Bu sanalarda xona mavjud emas.", "No rooms available for these dates.", settings.language))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    if ratesSandbox {
                        Text(NuiteeCopy.text("Тестовые тарифы", "Sinov tariflari", "Test rates", settings.language)).font(.caption)
                    }
                    ForEach(rates) { rate in
                        rateCard(rate)
                        rateSelectionButton(rate)
                    }
                }
                cancellationAndPrivacy
                if let detail {
                    if !detail.importantInformation.isEmpty {
                        sectionTitle(NuiteeCopy.text("Важная информация", "Muhim maʼlumotlar", "Important information", settings.language))
                        Text(detail.importantInformation).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !detail.policies.isEmpty {
                        sectionTitle(NuiteeCopy.text("Правила отеля", "Mehmonxona qoidalari", "Property policies", settings.language))
                        ForEach(detail.policies) { policy in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(policy.title).font(.subheadline.weight(.semibold))
                                Text(policy.description).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let lat = detail.latitude, let lon = detail.longitude, (-90...90).contains(lat), (-180...180).contains(lon) {
                        sectionTitle(NuiteeCopy.text("Расположение", "Joylashuv", "Location", settings.language))
                        if let mosque = mosqueDistance(latitude: lat, longitude: lon) {
                            Label(mosque, systemImage: "figure.walk")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon), span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)))) {
                            Marker(detail.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                        }
                        .frame(height: 195).clipShape(RoundedRectangle(cornerRadius: 21))
                    }
                } else if let detailError {
                    Text(detailError).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 70)
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea())
        .navigationTitle(hotel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.iumrahSignatureBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: hotel.name + " — " + (hotel.address ?? hotel.city)) {
                    Image(systemName: "square.and.arrow.up")
                }
                IumrahPageHelpButton(inSystemToolbar: true)
            }
        }
        .modifier(IumrahHelpOverlayHost(enabled: true, explicitContext: IumrahHelpContext(key: ratesLoading || !ratesCompleted ? "hotel.loading" : ratesError != nil ? "hotel.rates_error" : rates.isEmpty ? (onSelectRate == nil ? "hotel.no_rates" : "hotel.package_no_rates") : chosenOffer != nil ? "hotel.saved" : "hotel.details")))
        .task(id: settings.language.rawValue) { await refreshDetail() }
        .task(id: reloadID) { await refreshRates() }
        .fullScreenCover(isPresented: $isGalleryPresented) {
            NuiteeHotelGallery(images: photos, hotelName: hotel.name)
        }
        .navigationDestination(item: $expandedRoomRate) { rate in
            NuiteeRoomDetailsPage(
                hotelName: hotel.name,
                rate: rate,
                room: detail?.rooms.first(where: { $0.id == rate.roomId }),
                nights: nights,
                onAdd: { saveRate(rate); expandedRoomRate = nil }
            )
        }
        .alert(NuiteeCopy.text("Выбор номера сохранён", "Xona tanlovi saqlandi", "Room selection saved", settings.language), isPresented: $showSaveConfirmation) {
            Button(NuiteeCopy.text("Понятно", "Tushunarli", "OK", settings.language), role: .cancel) { }
        } message: {
            Text(NuiteeCopy.text("Отель добавлен в план поездки.", "Mehmonxona safar rejasiga qo‘shildi.", "Hotel added to your trip plan.", settings.language))
        }
    }

    private var collage: some View {
        let hero = Array(photos.prefix(5))
        return VStack(spacing: 4) {
            if !hero.isEmpty {
                HStack(spacing: 4) {
                    ForEach(0..<min(2, hero.count), id: \.self) { idx in
                        HotelCachedImage(rawURL: hero[idx])
                            .frame(maxWidth: .infinity)
                            .frame(height: 156)
                    }
                }
                if hero.count > 2 {
                    HStack(spacing: 4) {
                        ForEach(2..<hero.count, id: \.self) { idx in
                            ZStack {
                                HotelCachedImage(rawURL: hero[idx])
                                if idx == 4 && photos.count > 5 {
                                    Color.black.opacity(0.35)
                                    Text("+\(photos.count - 5)")
                                        .font(.title3.weight(.bold)).foregroundStyle(.white)
                                }
                            }.frame(maxWidth: .infinity).frame(height: 96)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
        .onTapGesture { if !photos.isEmpty { isGalleryPresented = true } }
        .overlay(alignment: .bottomTrailing) {
            if !photos.isEmpty {
                Label("\(photos.count)", systemImage: "photo.on.rectangle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }

    private var staySelector: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(NuiteeCopy.text("Даты проживания", "Yashash sanalari", "Stay dates", settings.language))
            HStack(spacing: 10) {
                DatePicker(NuiteeCopy.text("Заезд", "Kirish", "Check-in", settings.language), selection: $checkin, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                Spacer(minLength: 0)
                Stepper("\(nights)", value: $nights, in: 1...28)
                    .fixedSize()
            }
            Stepper("\(adults) " + NuiteeCopy.text("взрослых", "kattalar", "adults", settings.language), value: $adults, in: 1...6)
                .font(.subheadline)
            Text("\(checkin.formatted(date: .abbreviated, time: .omitted)) — \(checkout.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // An inclusion can be promised before room selection only if every offer has it.
    private var commonSupplierMeals: HotelMealChoices {
        guard !rates.isEmpty else { return HotelMealChoices() }
        return HotelMealChoices(breakfast: rates.allSatisfy { $0.supplierMeals.breakfast },
            lunch: rates.allSatisfy { $0.supplierMeals.lunch }, dinner: rates.allSatisfy { $0.supplierMeals.dinner })
    }

    private func saveRate(_ rate: NuiteeRoomRate) {
        if let onSelectRate { onSelectMeals?(selectedMeals); onSelectRate(rate); dismiss(); return }
        NuiteeStaySelectionStore.shared.save(NuiteeSelectedStay(
            provider: "nuitee", hotelId: hotel.id, hotelName: hotel.name, city: hotel.city,
            checkin: dateISO(checkin), checkout: dateISO(checkout), adults: adults,
            offerId: rate.offerId, roomId: rate.roomId, roomName: rate.roomName,
            totalUSD: rate.price, mealPlan: rate.mealPlan, cancellationTag: rate.cancellationTag,
            selectedAt: Date()
        ))
        chosenOffer = rate
        showSaveConfirmation = true
    }

    private func rateCard(_ rate: NuiteeRoomRate) -> some View {
        let room = detail?.rooms.first(where: { $0.id == rate.roomId })
        return VStack(alignment: .leading, spacing: 12) {
            NuiteeRoomPhotoCarousel(images: room?.images ?? [], height: 176)
            Text(rate.roomName).font(.headline)
            if let room {
                if let capacity = room.maxOccupancy, capacity > 0 {
                    Label("\(capacity) " + NuiteeCopy.text("гостя", "mehmon", "guests", settings.language), systemImage: "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !room.amenities.isEmpty {
                    Text(room.amenities.prefix(3).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            if !rate.mealPlan.isEmpty {
                Label(rate.mealPlan, systemImage: "fork.knife")
                    .font(.caption).foregroundStyle(.secondary)
            }
            cancellationView(rate)
            Text(NuiteeHotelService.usd(rate.price))
                .font(.title2.weight(.bold))
            Text("\(nights) " + NuiteeCopy.text("ночей · за номер", "tun · xona uchun", "nights · per room", settings.language))
                .font(.caption).foregroundStyle(.secondary)
            Button {
                expandedRoomRate = rate
            } label: {
                HStack {
                    Text(NuiteeCopy.text("Подробнее о номере", "Xona haqida batafsil", "Room details", settings.language))
                    Spacer()
                    Image(systemName: "chevron.right")
                }.font(.subheadline.weight(.semibold)).padding(.vertical, 8)
            }
            .buttonStyle(.plain)

        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private func rateSelectionButton(_ rate: NuiteeRoomRate) -> some View {
            Button { saveRate(rate) } label: {
                Text(NuiteeCopy.text("Добавить в план умры", "Umra rejasiga qo‘shish", "Add to Umrah plan", settings.language))
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
            .disabled(rate.offerId.isEmpty)
    }

    private func cancellationView(_ rate: NuiteeRoomRate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(rate.refundable
                  ? NuiteeCopy.text("Возвратный тариф — проверьте сроки", "Qaytariladigan tarif — muddatlarni tekshiring", "Refundable — check deadline", settings.language)
                  : NuiteeCopy.text("Невозвратный тариф", "Qaytarilmaydigan tarif", "Non-refundable rate", settings.language), systemImage: rate.refundable ? "arrow.uturn.backward.circle" : "exclamationmark.circle")
                .font(.subheadline.weight(.semibold))
            if !rate.cancellationDescription.isEmpty { Text(rate.cancellationDescription).font(.footnote) }
            ForEach(Array(rate.cancellationDeadlines.enumerated()), id: \.offset) { entry in
                Text(NuiteeCopy.text("Срок отмены: ", "Bekor qilish muddati: ", "Cancel by: ", settings.language)
                     + NuiteeHotelService.deadlineText(entry.element.until, locale: settings.language.localeIdentifier)
                     + (entry.element.amount.map {
                        NuiteeCopy.text(" · штраф ", " · jarima ", " · penalty ", settings.language)
                        + NuiteeHotelService.usd($0)
                       } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !rate.chargeOnArrival.isEmpty {
                Text(NuiteeCopy.text("Некоторые налоги/сборы оплачиваются отдельно в отеле.", "Baʼzi soliqlar va yig‘imlar mehmonxonada alohida to‘lanadi.", "Some taxes and fees are paid at the hotel.", settings.language))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(Array(rate.chargeOnArrival.enumerated()), id: \.offset) { entry in
                    if let amount = entry.element.amount {
                        Text(amount.formatted(.currency(code: entry.element.currency)))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    // Coordinates provide an approximate straight-line distance, never a walking ETA.
    private func mosqueDistance(latitude: Double, longitude: Double) -> String? {
        let cityKey = hotel.city.lowercased()
        let makkah = cityKey.contains("makk") || cityKey.contains("mecc") || cityKey.contains("مكة")
        let madinah = cityKey.contains("madin") || cityKey.contains("medin") || cityKey.contains("المدينة")
        guard makkah || madinah else { return nil }
        let mosque = makkah
            ? CLLocation(latitude: 21.4225, longitude: 39.8262)
            : CLLocation(latitude: 24.4672, longitude: 39.6111)
        let kms = CLLocation(latitude: latitude, longitude: longitude).distance(from: mosque) / 1000
        guard kms.isFinite else { return nil }
        let name = makkah
            ? NuiteeCopy.text("Харама", "Masjidul Harom", "Masjid al-Haram", settings.language)
            : NuiteeCopy.text("Мечети Пророка", "Masjidun Nabaviy", "Prophet's Mosque", settings.language)
        let prefix = NuiteeCopy.text("По прямой до", "To‘g‘ri masofa:", "Straight-line to", settings.language)
        return "\(prefix) \(name): \(String(format: "%.1f", kms)) "
            + NuiteeCopy.text("км", "km", "km", settings.language)
    }

    private var cancellationAndPrivacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(NuiteeCopy.text("Возврат и конфиденциальность", "Qaytarish va maxfiylik", "Cancellation & privacy", settings.language))
            Text(NuiteeCopy.text(
                "Условия возврата различаются по номерам и тарифам. Точные сроки отмены и штрафы указаны у каждого предложения. Перед оплатой условия повторно проверяются поставщиком.",
                "Bekor qilish shartlari tarifga bog‘liq. To‘lovdan oldin shartlarni tekshiring.",
                "Cancellation and refund rules differ by room and rate. Recheck them before payment.", settings.language
            )).font(.footnote).foregroundStyle(.secondary)

        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
    }
    private func dateISO(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    private func refreshDetail() async {
        do { detail = try await service.detail(hotelID: hotel.id, language: settings.language.hotelContentCode) }
        catch { detailError = error.localizedDescription }
    }
    private func refreshRates() async {
        let requestID = UUID()
        ratesRequestID = requestID
        let requestedCheckin = checkin
        let requestedCheckout = checkout
        let requestedAdults = adults
        ratesLoading = true
        ratesCompleted = false
        ratesError = nil
        rates = []
        do {
            let result = try await service.rates(hotelID: hotel.id, checkin: requestedCheckin, checkout: requestedCheckout, adults: requestedAdults, childrenAges: childrenAges, language: settings.language.hotelContentCode)
            guard ratesRequestID == requestID, !Task.isCancelled else { return }
            rates = result.rates
            ratesSandbox = result.sandbox
        } catch {
            guard ratesRequestID == requestID, !Task.isCancelled else { return }
            ratesError = error.localizedDescription
        }
        if ratesRequestID == requestID { ratesLoading = false; ratesCompleted = true }
    }
}

private struct NuiteeHotelGallery: View {
    @Environment(\.dismiss) private var dismiss
    let images: [String]
    let hotelName: String
    @State private var index = 0
    var body: some View {
        NavigationStack {
            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    HotelCachedImage(rawURL: images[i], contentMode: .fit)
                        .background(.black)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .background(.black)
            .navigationTitle(hotelName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Готово") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) {
                Text("\(index + 1) / \(images.count)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding().background(.black.opacity(0.45), in: Capsule()).padding(.bottom, 22)
            }
        }
    }
}

// Catalogue rows use only already returned media. Full hotel details and photo
// galleries are fetched when the user opens the hotel, not while scrolling.
private struct NuiteeCatalogPreviewCollage: View {
    let hotel: NuiteeHotel
    var body: some View {
        let source = IumrahHotelPhotoIdentity.unique((hotel.previewImages ?? []) + [hotel.coverImageURL].compactMap { $0 })
        NuiteeHotelCollage(images: Array(source.prefix(3)))
    }
}

private struct NuiteeRoomPhotoCarousel: View {
    let images: [String]
    let height: CGFloat
    @State private var selected = 0
    var body: some View {
        Group {
            if !images.isEmpty {
                TabView(selection: $selected) {
                    ForEach(images.indices, id: \.self) { index in
                        HotelCachedImage(rawURL: images[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 17))
                .overlay(alignment: .topTrailing) {
                    Text("\(selected + 1)/\(images.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(9)
                }
            }
        }
    }
}

private struct NuiteeRoomDetailsPage: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let hotelName: String
    let rate: NuiteeRoomRate
    let room: NuiteeRoomDescription?
    let nights: Int
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                    IumrahPageHelpCard("hotel.rate_details")
                    NuiteeRoomPhotoCarousel(images: room?.images ?? [], height: 260)
                    Text(rate.roomName).font(.title2.bold())
                    Text(hotelName).font(.subheadline).foregroundStyle(.secondary)
                    if let room {
                        if !room.description.isEmpty { Text(room.description).font(.body) }
                        if let maxOccupancy = room.maxOccupancy {
                            Label("\(maxOccupancy) " + NuiteeCopy.text("гостей", "mehmon", "guests", settings.language), systemImage: "person.2")
                        }
                        ForEach(room.amenities, id: \.self) { amenity in
                            Label(amenity, systemImage: "checkmark.circle")
                                .font(.subheadline)
                        }
                    }
                    if !rate.mealPlan.isEmpty {
                        Label(rate.mealPlan, systemImage: "fork.knife")
                    }
                    Divider()
                    Text(rate.refundable ?
                        NuiteeCopy.text("Возвратный тариф", "Qaytariladigan tarif", "Refundable rate", settings.language) :
                        NuiteeCopy.text("Невозвратный тариф", "Qaytarilmaydigan tarif", "Non-refundable rate", settings.language))
                        .font(.headline)
                    if !rate.cancellationDescription.isEmpty { Text(rate.cancellationDescription) }
                    ForEach(rate.cancellationDeadlines, id: \.until) { deadline in
                        Text(NuiteeHotelService.deadlineText(deadline.until, locale: settings.language.localeIdentifier) + (deadline.amount.map { " · " + NuiteeHotelService.usd($0) } ?? ""))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if !rate.chargeOnArrival.isEmpty {
                        Text(NuiteeCopy.text("Оплачивается в отеле", "Mehmonxonada to‘lanadi", "Pay at property", settings.language)).font(.headline)
                        ForEach(Array(rate.chargeOnArrival.enumerated()), id: \.offset) { entry in
                            if let amount = entry.element.amount { Text(amount.formatted(.currency(code: entry.element.currency))) }
                        }
                    }
                    Text(NuiteeHotelService.usd(rate.price))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("\(nights) " + NuiteeCopy.text("ночей · 1 номер", "tun · 1 xona", "nights · 1 room", settings.language))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(NuiteeCopy.text("Предварительная стоимость, не подтверждённое бронирование", "Taxminiy narx, tasdiqlangan bron emas", "Indicative price, not a confirmed reservation", settings.language))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: onAdd) {
                    Text(NuiteeCopy.text("Добавить в план умры", "Umra rejasiga qo‘shish", "Add to Umrah plan", settings.language))
                        .frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
                .disabled(rate.offerId.isEmpty)
                .padding(.horizontal, 20).padding(.vertical, 8)
                .background(.regularMaterial)
            }
            .navigationTitle(NuiteeCopy.text("Номер", "Xona", "Room", settings.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.iumrahSignatureBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
    }
}

private struct NuiteeStayCalendarSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var checkin: Date
    @Binding var nights: Int
    @State private var proposedStart: Date = .now
    @State private var proposedEnd: Date = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var choosingEnd = false
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(choosingEnd
                        ? NuiteeCopy.text("Выберите дату выезда", "Chiqish sanasini tanlang", "Select check-out", settings.language)
                        : NuiteeCopy.text("Выберите дату заезда", "Kirish sanasini tanlang", "Select check-in", settings.language))
                        .font(.headline)
                    HStack {
                        Label(proposedStart.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        Spacer()
                        Image(systemName: "arrow.right")
                        Spacer()
                        Label(proposedEnd.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    }
                    .font(.subheadline.weight(.semibold))
                    ForEach(0..<6, id: \.self) { offset in
                        monthGrid(offset: offset)
                    }
                }
                .padding(20)
            }
            .navigationTitle(NuiteeCopy.text("Даты проживания", "Yashash sanalari", "Stay dates", settings.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(NuiteeCopy.text("Отмена", "Bekor qilish", "Cancel", settings.language)) { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Button {
                    checkin = proposedStart
                    nights = max(1, min(28, calendar.dateComponents([.day], from: proposedStart, to: proposedEnd).day ?? 1))
                    dismiss()
                } label: {
                    Text(NuiteeCopy.text("Выбрать даты", "Sanalarni tanlash", "Select dates", settings.language)
                         + " · \(max(1, calendar.dateComponents([.day], from: proposedStart, to: proposedEnd).day ?? 1)) "
                         + NuiteeCopy.text("ночей", "tun", "nights", settings.language))
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                }
                .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .onAppear {
            proposedStart = calendar.startOfDay(for: checkin)
            proposedEnd = calendar.date(byAdding: .day, value: nights, to: proposedStart) ?? proposedStart
        }
    }

    private func monthGrid(offset: Int) -> some View {
        let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let month = calendar.date(byAdding: .month, value: offset, to: firstMonth) ?? firstMonth
        let range = calendar.range(of: .day, in: .month, for: month) ?? 1..<29
        let weekday = calendar.component(.weekday, from: month)
        let firstOffset = (weekday - calendar.firstWeekday + 7) % 7
        return VStack(alignment: .leading, spacing: 12) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 7) {
                ForEach(0..<firstOffset, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(Array(range), id: \.self) { day in
                    if let date = calendar.date(byAdding: .day, value: day - 1, to: month) {
                        let today = calendar.startOfDay(for: Date())
                        let maxStayEnd = calendar.date(byAdding: .day, value: 28, to: proposedStart) ?? proposedStart
                        let selectable = date >= today && date <= (calendar.date(byAdding: .day, value: 730, to: today) ?? today)
                            && (!choosingEnd || date <= maxStayEnd || date <= proposedStart)
                        let isEdge = calendar.isDate(date, inSameDayAs: proposedStart) || calendar.isDate(date, inSameDayAs: proposedEnd)
                        let inside = date > proposedStart && date < proposedEnd
                        Button {
                            if !choosingEnd || date <= proposedStart {
                                proposedStart = date
                                proposedEnd = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                                choosingEnd = true
                            } else {
                                proposedEnd = date
                                choosingEnd = false
                            }
                        } label: {
                            Text("\(day)")
                                .font(.subheadline.weight(isEdge ? .bold : .regular))
                                .foregroundStyle(isEdge ? Color.white : selectable ? Color.primary : Color.secondary.opacity(0.45))
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(isEdge ? Color.black : inside ? Color.black.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!selectable)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}
