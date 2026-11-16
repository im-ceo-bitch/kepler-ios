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

    @Published private(set) var nextOffset: Int?
    @Published private(set) var total = 0
    @Published private(set) var loadingMore = false
    @Published private(set) var pageError = false
    private var activeKey = ""

    func reload(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int, stars: Int = 0,
                query: String = "", favorites: Set<String>? = nil, forceRefresh: Bool = false) async {
        let version = UUID(); generation = version
        let requestedKey = key(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: query, favorites: favorites)
        let sameSearch = activeKey == requestedKey
        activeKey = requestedKey
        busy = true; loadingMore = false; pageError = false; errorMessage = nil; rateError = nil
        if !sameSearch { hotels = []; nextOffset = nil; total = 0 }
        defer { if generation == version { busy = false } }
        do {
            let page = try await service.hotelPage(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: query, favorites: favorites)
            guard generation == version, !Task.isCancelled else { return }
            apply(page, append: false)
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            if hotels.isEmpty { errorMessage = "HOTEL_CATALOG_UNAVAILABLE" }
            else {
                hotels = hotels.map { hotel in var row = hotel; row.minimumRate = nil; row.rateStatus = "provider_error"; return row }
                rateError = "RATES_UNAVAILABLE"
            }
        }
    }

    func loadMore(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int, stars: Int = 0,
                  query: String = "", favorites: Set<String>? = nil) async {
        guard !busy, !loadingMore, let offset = nextOffset,
              activeKey == key(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: query, favorites: favorites) else { return }
        let version = generation; loadingMore = true; pageError = false
        defer { if generation == version { loadingMore = false } }
        do {
            let page = try await service.hotelPage(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults, stars: stars, offset: offset, query: query, favorites: favorites)
            guard generation == version, !Task.isCancelled else { return }
            apply(page, append: true)
        } catch { if generation == version && !Task.isCancelled { pageError = true } }
    }

    func matches(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int, stars: Int, query: String, favorites: Set<String>?) -> Bool {
        activeKey == key(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: query, favorites: favorites)
    }
    private func key(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int, stars: Int, query: String, favorites: Set<String>?) -> String {
        "\(city.rawValue)|\(checkin.timeIntervalSince1970)|\(checkout.timeIntervalSince1970)|\(adults)|\(stars)|\(query)|\(favorites?.sorted().joined(separator: ",") ?? "*")"
    }
    private func apply(_ response: NuiteeHotelListEnvelope, append: Bool) {
        let rows = response.hotels.map { hotel -> NuiteeHotel in
            var row = hotel
            if row.rateStatus == nil { row.rateStatus = row.minimumRate != nil ? (response.pricesStale ? "cached" : "available") : response.rateError != nil ? "provider_error" : "no_availability" }
            return row
        }
        if append {
            var ids = Set(hotels.map(\.id))
            hotels += rows.filter { ids.insert($0.id).inserted }
        } else { hotels = rows }
        nextOffset = response.nextOffset; total = response.total ?? hotels.count
        sandbox = response.sandbox; catalogStale = response.hotelCatalogStale || response.pricesStale
        rateError = response.rateError
    }

}

struct NuiteeHotelsCatalogView: View {
    let refreshSignal: Int
    var initialHotelQuery: String = ""
    var searchOverride: IumrahHotelTabSearch? = nil
    var showsSearchControls = true
    let favoritesOnly: Bool
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
    @State private var opened: NuiteeHotel?
    @State private var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "iumrah.nuitee.favorites.v1") ?? [])

    init(refreshSignal: Int, initialHotelQuery: String = "", searchOverride: IumrahHotelTabSearch? = nil,
         showsSearchControls: Bool = true, model: NuiteeCatalogModel? = nil, favoritesOnly: Bool = false, onManualRoom: ((LocalJourneyRoom) -> Void)? = nil) {
        _model = StateObject(wrappedValue: model ?? NuiteeCatalogModel())
        self.refreshSignal = refreshSignal
        self.initialHotelQuery = initialHotelQuery
        self.searchOverride = searchOverride
        self.showsSearchControls = showsSearchControls
        self.favoritesOnly = favoritesOnly
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
        [city.rawValue, String(checkin.timeIntervalSince1970), String(nights), String(adults), String(homeSearchRevision), String(refreshSignal), String(stars), normalizedQuery, favoritesOnly ? favorites.sorted().joined(separator: ",") : "*"].joined(separator: ":")
    }
    private var normalizedQuery: String { hotelQuery.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let matches = model.hotels
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
            .onChange(of: city) { _, _ in stars = 0; hotelQuery = "" }


            }

            Picker(NuiteeCopy.text("Звёзды", "Yulduzlar", "Stars", settings.language), selection: $stars) {
                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { star in
                    Text(star == 0 ? NuiteeCopy.text("Все", "Barchasi", "All", settings.language) : "\(star) ★").tag(star)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)

            if (model.busy && model.hotels.isEmpty) || !model.matches(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: normalizedQuery, favorites: favoritesOnly ? favorites : nil) {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
            } else if model.errorMessage != nil {
                VStack(spacing: 10) {
                    Text(NuiteeCopy.text("Не удалось загрузить каталог", "Katalog yuklanmadi", "Could not load hotels", settings.language))
                        .font(.headline)
                    Text(NuiteeCopy.text("Попробуйте ещё раз", "Qayta urinib ko‘ring", "Please try again", settings.language)).font(.footnote).foregroundStyle(.secondary)
                    Button(NuiteeCopy.text("Повторить", "Qayta", "Retry", settings.language)) {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground)
                }
                .frame(maxWidth: .infinity).padding(25)
            } else if favoritesOnly && model.total == 0 && !model.busy {
                ContentUnavailableView(NuiteeCopy.text("Нет сохранённых отелей в этом городе", "Bu shaharda saqlangan mehmonxonalar yo‘q", "No saved hotels in this city", settings.language), systemImage: "heart", description: Text(NuiteeCopy.text("Отмечайте понравившиеся отели сердечком в каталоге.", "Katalogda yoqqan mehmonxonalarni yurakcha bilan belgilang.", "Tap the heart on hotels you like in the catalog.", settings.language)))
            } else if model.total == 0 && !model.busy {
                ContentUnavailableView(NuiteeCopy.text("Нет отелей", "Mehmonxonalar topilmadi", "No hotels", settings.language), systemImage: "building.2", description: Text(NuiteeCopy.text("Попробуйте другой фильтр или даты", "Filtr yoki sanani almashtiring", "Change stars or dates", settings.language)))
                if !normalizedQuery.isEmpty {
                    Button(NuiteeCopy.text("Показать все отели города", "Shahardagi barcha mehmonxonalar", "Show all hotels in this city", settings.language)) { hotelQuery = "" }
                        .buttonStyle(IumrahSecondaryButtonStyle())
                }
            } else {
                if !normalizedQuery.isEmpty {
                    Text(NuiteeCopy.text("Результаты поиска", "Qidiruv natijalari", "Search results", settings.language))
                        .font(.headline)
                }
                if model.rateError != nil {
                    HStack {
                        Text(NuiteeCopy.text("Не удалось проверить наличие", "Mavjudlikni tekshirib bo‘lmadi", "Could not check availability", settings.language)).font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button(NuiteeCopy.text("Повторить", "Qayta", "Retry", settings.language)) { Task { await reload() } }.font(.footnote.weight(.semibold)).tint(.primary)
                    }
                }
                HStack {
                    Text("\(model.total) " + NuiteeCopy.text("отелей", "mehmonxona", "hotels", settings.language))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                LazyVStack(spacing: 12) {
                    ForEach(matches) { hotel in
                        NuiteeHotelListingCard(
                            hotel: hotel, nights: nights, adults: adults, sandbox: model.sandbox,
                            favorite: favorites.contains(hotel.id),
                            onOpen: { opened = hotel }, onFavorite: { toggleFavorite(hotel.id) }
                        )
                    }
                    IumrahHotelPageButton(remaining: max(0, model.total - model.hotels.count), loading: model.loadingMore, failed: model.pageError, hasMore: model.nextOffset != nil) {
                        Task { await model.loadMore(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: normalizedQuery, favorites: favoritesOnly ? favorites : nil) }
                    }
                }

            }
        }
        .task(id: reloadIdentity) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }; await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await refreshIfNewDay() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshIfNewDay() } }
        }
        .onAppear {
            favorites = Set(UserDefaults.standard.stringArray(forKey: "iumrah.nuitee.favorites.v1") ?? [])
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
        guard !favoritesOnly, let request, appliedHomeSearchID != request.id else { return }
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
        searchExpanded = false
        hotelSearchFocused = false
    }

    private func refreshIfNewDay() async {
        guard let lastLoadedDay, !Calendar.current.isDateInToday(lastLoadedDay) else { return }
        await reload()
    }

    private func reload() async {
        lastLoadedDay = Date()
        await model.reload(city: city, checkin: checkin, checkout: checkout, adults: adults, stars: stars, query: normalizedQuery, favorites: favoritesOnly ? favorites : nil)
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
    @State private var additionalPhotos: [String] = []

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.43
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    NuiteeCatalogPreviewCollage(hotel: hotel, additionalPhotos: additionalPhotos)
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
                    if let rate = hotel.minimumRate, rate.currency.uppercased() == "USD", rate.price.isFinite, rate.price > 0 {
                        if sandbox {
                            Text(NuiteeCopy.text("Ориентировочная цена", "Taxminiy narx", "Indicative price", settings.language)).font(.caption2).foregroundStyle(.secondary)
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
                            Text(hotel.rateStatus == "no_availability"
                                 ? (sandbox ? NuiteeCopy.text("Стоимость и наличие уточняются", "Narx va mavjudlik aniqlashtiriladi", "Price and availability to be confirmed", settings.language) : NuiteeCopy.text("На эти даты распродано", "Bu sanalarga barcha xonalar band", "Sold out for these dates", settings.language))
                                 : NuiteeCopy.text("Не удалось проверить наличие", "Mavjudlikni tekshirib bo‘lmadi", "Could not check availability", settings.language)).font(.caption)
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
        .task(id: hotel.id) {
            additionalPhotos = []
            let existing = IumrahHotelPhotoIdentity.unique((hotel.previewImages ?? []) + [hotel.coverImageURL].compactMap { $0 })
            guard existing.count < 3 else { return }
            let result = await NuiteePreviewPhotoLoader.shared.photos(hotelID: hotel.id)
            guard !Task.isCancelled else { return }
            additionalPhotos = result
        }
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
    @EnvironmentObject private var account: IumrahAccountStore
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
    @State private var galleryScrollToRooms = false
    private let service = NuiteeHotelService()

    private var checkout: Date { Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin }
    private var reloadID: String { "\(hotel.id):\(checkin.timeIntervalSince1970):\(nights):\(adults):\(settings.language.rawValue)" }
    private var photos: [String] {
        let hotelPhotos = detail?.images ?? []
        let roomPhotos = detail?.rooms.flatMap(\.images) ?? []
        let preview = hotel.previewImages ?? []
        let cover = [hotel.coverImageURL].compactMap { $0 }
        return IumrahHotelPhotoIdentity.unique(hotelPhotos + roomPhotos + preview + cover)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
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
                sectionTitle(NuiteeCopy.text("Выберите номер", "Xona tanlang", "Choose a room", settings.language)).id("nuitee.rooms")
                if ratesLoading { ProgressView().frame(maxWidth: .infinity).padding(22) }
                else if ratesError != nil {
                    Label(NuiteeCopy.text("Не удалось загрузить цены", "Narxlarni yuklab bo‘lmadi", "Could not load prices", settings.language), systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(NuiteeCopy.text("Повторить", "Qayta urinish", "Retry", settings.language)) { Task { await refreshRates() } }.tint(.primary)
                } else if rates.isEmpty {
                    Text(ratesSandbox ? NuiteeCopy.text("Стоимость и наличие уточняются", "Narx va mavjudlik aniqlashtiriladi", "Price and availability to be confirmed", settings.language) : NuiteeCopy.text("На эти даты распродано.", "Bu sanalarda xona mavjud emas.", "No rooms available for these dates.", settings.language))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(rates) { rate in
                        rateCard(rate)
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
                } else if detailError != nil {
                    Text(NuiteeCopy.text("Не удалось загрузить информацию об отеле", "Mehmonxona haqida ma’lumot yuklanmadi", "Could not load hotel information", settings.language)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 70)
        }
        .onChange(of: galleryScrollToRooms) { _, value in
            if value { withAnimation(.snappy) { scrollProxy.scrollTo("nuitee.rooms", anchor: .top) }; galleryScrollToRooms = false }
        }
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
        .onAppear {
            HomePersonalizationStore.shared.visitHotel(.init(hotel: hotel, checkin: checkin, nights: nights, adults: adults, sandbox: sandbox), owner: HomePersonalizationStore.owner(account))
        }
        .task(id: settings.language.rawValue) { await refreshDetail() }
        .task(id: reloadID) { await refreshRates() }
        .fullScreenCover(isPresented: $isGalleryPresented) {
            NuiteeHotelGallery(images: photos, hotelName: hotel.name, rooms: detail?.rooms ?? [], onChooseRooms: { isGalleryPresented = false; galleryScrollToRooms = true })
        }
        .navigationDestination(item: $expandedRoomRate) { rate in
            NuiteeRoomDetailsPage(
                hotelName: hotel.name,
                rate: rate,
                room: detail?.rooms.first(where: { $0.id == rate.roomId }),
                nights: nights,
                indicative: ratesSandbox,
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
            if ratesSandbox {
                Text(NuiteeCopy.text("Стоимость, наличие и условия уточним перед оплатой.", "Narx, mavjudlik va shartlar to‘lovdan oldin tasdiqlanadi.", "Price, availability and terms will be confirmed before payment.", settings.language)).font(.caption).foregroundStyle(.secondary)
            } else { cancellationView(rate) }
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
            rateSelectionButton(rate)
        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private func rateSelectionButton(_ rate: NuiteeRoomRate) -> some View {
            Button { saveRate(rate) } label: {
                Text(NuiteeCopy.text("Добавить в пакет Умры", "Umra paketiga qo‘shish", "Add to Umrah package", settings.language))
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
                "Условия проживания, отмены и возврата уточняются перед оплатой.",
                "Yashash, bekor qilish va qaytarish shartlari to‘lovdan oldin aniqlashtiriladi.",
                "Stay, cancellation and refund terms will be confirmed before payment.", settings.language
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
            ratesSandbox = result.sandbox
            guard result.ok else { throw APIError.invalidResponse }
            rates = result.rates.filter { $0.currency.uppercased() == "USD" && $0.price.isFinite && $0.price > 0 && !$0.offerId.isEmpty && !$0.roomId.isEmpty }
            if rates.isEmpty && !result.rates.isEmpty { throw APIError.invalidResponse }
        } catch {
            guard ratesRequestID == requestID, !Task.isCancelled else { return }
            ratesError = error.localizedDescription
        }
        if ratesRequestID == requestID { ratesLoading = false; ratesCompleted = true }
    }
}

private struct NuiteeHotelGallery: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    let images: [String]
    let hotelName: String
    var rooms: [NuiteeRoomDescription] = []
    var onChooseRooms: (() -> Void)? = nil
    @State private var selection = "all"
    @State private var viewer: PhotoSelection?
    private struct PhotoSelection: Identifiable { let id = UUID(); let index: Int }
    private struct Album: Identifiable { let id: String; let title: String; let images: [String] }
    private var albums: [Album] {
        [Album(id: "all", title: NuiteeCopy.text("Все фотографии", "Barcha suratlar", "All photos", settings.language), images: IumrahHotelPhotoIdentity.unique(images + rooms.flatMap(\.images)))] + rooms.filter { !$0.images.isEmpty }.map { Album(id: $0.id, title: $0.name, images: IumrahHotelPhotoIdentity.unique($0.images)) }
    }
    private var current: [String] { (albums.first(where: { $0.id == selection }) ?? albums[0]).images }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(albums) { album in
                                Button { selection = album.id } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        HotelCachedImage(rawURL: album.images.first, thumbnailPixelDimension: 320)
                                            .frame(width: 108, height: 82).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                                        Text(album.title).font(.caption.weight(.semibold)).lineLimit(2).frame(width: 108, alignment: .leading)
                                        Text("\(album.images.count)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .padding(8).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 15))
                                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(selection == album.id ? Color.primary : Color.clear, lineWidth: 2))
                                }.buttonStyle(.plain).accessibilityAddTraits(selection == album.id ? .isSelected : [])
                            }
                        }.padding(2)
                    }
                    Text("\(current.count) · " + (albums.first(where: { $0.id == selection })?.title ?? "")).font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        ForEach(current.indices, id: \.self) { index in
                            Button { viewer = PhotoSelection(index: index) } label: {
                                Color.clear.aspectRatio(1, contentMode: .fit).overlay {
                                    HotelCachedImage(rawURL: current[index], thumbnailPixelDimension: 640)
                                }.clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(16)
            }
            .background(Color.iumrahPageBackground)
            .navigationTitle(NuiteeCopy.text("Фотографии", "Suratlar", "Photos", settings.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.iumrahSignatureBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } }; ToolbarItem(placement: .topBarTrailing) { ShareLink(item: hotelName) { Image(systemName: "square.and.arrow.up") } } }
            .safeAreaInset(edge: .bottom) {
                if let onChooseRooms {
                    Button(action: onChooseRooms) { Text(NuiteeCopy.text("Выбрать номера", "Xonalarni tanlash", "Choose rooms", settings.language)).font(.headline).frame(maxWidth: .infinity).frame(height: 50) }
                        .buttonStyle(.borderedProminent).tint(Color.iumrahPrimaryButtonBackground).padding(16).background(.regularMaterial)
                }
            }
            .fullScreenCover(item: $viewer) { value in NuiteePhotoViewer(images: current, initialIndex: value.index) }
        }
    }
}

private struct NuiteePhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let images: [String]
    @State private var index: Int
    init(images: [String], initialIndex: Int) { self.images = images; _index = State(initialValue: initialIndex) }
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    HotelCachedImage(rawURL: images[i], contentMode: .fit).tag(i)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline).padding(14).foregroundStyle(.white).background(.white.opacity(0.18), in: Circle()) }.padding()
        }.overlay(alignment: .bottom) { Text("\(index + 1) / \(images.count)").foregroundStyle(.white).padding() }
    }
}

// Only missing catalogue media triggers a bounded, shared hotel-detail request.
private actor NuiteePreviewPhotoLoader {
    static let shared = NuiteePreviewPhotoLoader()
    private var cache: [String: [String]] = [:]
    private var inFlight: [String: Task<[String], Never>] = [:]
    func photos(hotelID: String) async -> [String] {
        if let cached = cache[hotelID] { return cached }
        if let pending = inFlight[hotelID] { return await pending.value }
        while inFlight.count >= 3 {
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return [] }
            if let cached = cache[hotelID] { return cached }
            if let pending = inFlight[hotelID] { return await pending.value }
        }
        guard !Task.isCancelled else { return [] }
        let task = Task<[String], Never> {
            guard let detail = try? await NuiteeHotelService().detail(hotelID: hotelID) else { return [] }
            return Array(IumrahHotelPhotoIdentity.unique(detail.images + detail.rooms.flatMap(\.images)).prefix(3))
        }
        inFlight[hotelID] = task
        let result = await task.value
        inFlight[hotelID] = nil
        if !result.isEmpty { cache[hotelID] = result }
        return result
    }
}

private struct NuiteeCatalogPreviewCollage: View {
    let hotel: NuiteeHotel
    var additionalPhotos: [String] = []
    var body: some View {
        let source = IumrahHotelPhotoIdentity.unique((hotel.previewImages ?? []) + [hotel.coverImageURL].compactMap { $0 } + additionalPhotos)
        NuiteeHotelCollage(images: Array(source.prefix(3)))
    }
}

private struct NuiteeRoomPhotoCarousel: View {
    let images: [String]
    let height: CGFloat
    @State private var showGallery = false
    private var photos: [String] { IumrahHotelPhotoIdentity.unique(images) }
    var body: some View {
        if !photos.isEmpty {
            Button { showGallery = true } label: {
                GeometryReader { proxy in
                    HStack(spacing: 3) {
                        HotelCachedImage(rawURL: photos[0]).frame(width: photos.count > 1 ? proxy.size.width * 0.64 : proxy.size.width, height: height).clipped()
                        if photos.count > 1 {
                            VStack(spacing: 3) {
                                HotelCachedImage(rawURL: photos[1]).frame(height: photos.count > 2 ? (height - 3) / 2 : height).clipped()
                                if photos.count > 2 {
                                    HotelCachedImage(rawURL: photos[2]).frame(height: (height - 3) / 2).clipped().overlay {
                                        if photos.count > 3 { Color.black.opacity(0.45); Text("+\(photos.count - 3)").font(.title3.bold()).foregroundStyle(.white) }
                                    }
                                }
                            }.frame(width: max(1, proxy.size.width * 0.36 - 3))
                        }
                    }
                }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 17))
            }.buttonStyle(.plain)
            .fullScreenCover(isPresented: $showGallery) { NuiteeHotelGallery(images: photos, hotelName: "") }
        }
    }
}

private struct NuiteeRoomDetailsPage: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let hotelName: String
    let rate: NuiteeRoomRate
    let room: NuiteeRoomDescription?
    let nights: Int
    let indicative: Bool
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
                    if indicative {
                        Text(NuiteeCopy.text("Условия проживания и отмены уточним перед оплатой.", "Yashash va bekor qilish shartlari to‘lovdan oldin tasdiqlanadi.", "Stay and cancellation terms will be confirmed before payment.", settings.language)).font(.footnote).foregroundStyle(.secondary)
                    } else {
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
                    Text(NuiteeCopy.text("Добавить в пакет Умры", "Umra paketiga qo‘shish", "Add to Umrah package", settings.language))
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
