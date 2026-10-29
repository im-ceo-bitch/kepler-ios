import SwiftUI
import MapKit
import CoreLocation

private enum NuiteeCopy {
    static func text(_ ru: String, _ uz: String, _ en: String, _ lang: AppSettingsStore.Language) -> String {
        switch lang {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return ru
        default: return en
        }
    }
}

private enum NuiteeCity: String, CaseIterable {
    case makkah, madinah
    func title(_ lang: AppSettingsStore.Language) -> String {
        self == .makkah ? NuiteeCopy.text("Мекка", "Makka", "Makkah", lang)
            : NuiteeCopy.text("Медина", "Madina", "Madinah", lang)
    }
}

@MainActor
private final class NuiteeCatalogModel: ObservableObject {
    @Published var hotels: [NuiteeHotel] = []
    @Published var sandbox = true
    @Published var catalogStale = false
    @Published var rateError: String?
    @Published var busy = false
    @Published var errorMessage: String?
    private let service = NuiteeHotelService()
    private var generation = UUID()

    func reload(city: NuiteeCity, checkin: Date, checkout: Date, adults: Int) async {
        let version = UUID()
        generation = version
        busy = true
        hotels = [] // Never show old city/date prices while loading a new request.
        errorMessage = nil
        do {
            let response = try await service.hotels(city: city.rawValue, checkin: checkin, checkout: checkout, adults: adults)
            guard generation == version, !Task.isCancelled else { return }
            hotels = response.hotels
            sandbox = response.sandbox
            catalogStale = response.hotelCatalogStale || response.pricesStale
            rateError = response.rateError
        } catch {
            guard generation == version, !Task.isCancelled else { return }
            hotels = [] // Never mix prices from a different city/date with current search.
            errorMessage = error.localizedDescription
        }
        if generation == version { busy = false }
    }
}

struct NuiteeHotelsCatalogView: View {
    let refreshSignal: Int
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var model = NuiteeCatalogModel()
    @State private var city: NuiteeCity = .makkah
    @State private var stars = 0
    @State private var selectedTier: PackageTier? = nil
    @State private var rooms = 1
    @State private var children = 0
    @State private var infants = 0
    @State private var draftRooms = 1
    @State private var draftChildren = 0
    @State private var draftInfants = 0
    @State private var hotelQuery = ""
    @State private var calendarPresented = false
    @FocusState private var hotelSearchFocused: Bool
    @State private var checkin = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
    @State private var nights = 1
    @State private var adults = 2
    @State private var draftCheckin = Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date()
    @State private var draftNights = 1
    @State private var draftAdults = 2
    @State private var searchExpanded = true
    @State private var visibleCount = 20
    @State private var opened: NuiteeHotel?
    @State private var favorites: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "iumrah.nuitee.favorites.v1") ?? [])

    private var checkout: Date { Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin }
    private var reloadIdentity: String {
        [city.rawValue, String(checkin.timeIntervalSince1970), String(nights), String(adults)].joined(separator: ":")
    }
    private var candidateHotels: [NuiteeHotel] {
        model.hotels.filter { hotel in
            let tierMatch = selectedTier.map { $0.selectableHotelStars.contains(hotel.roundedStars) } ?? true
            return tierMatch && (stars == 0 || hotel.roundedStars == stars)
        }
    }
    private var normalizedQuery: String { hotelQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingHotels: [NuiteeHotel] {
        guard !normalizedQuery.isEmpty else { return candidateHotels }
        let terms = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return candidateHotels.filter { hotel in
            let haystack = hotel.name + " " + (hotel.address ?? "")
            return terms.allSatisfy { haystack.localizedStandardContains($0) }
        }
    }
    private var alternativeHotels: [NuiteeHotel] {
        guard !normalizedQuery.isEmpty else { return [] }
        let selected = Set(matchingHotels.map(\.id))
        let preferredStars = matchingHotels.first?.roundedStars
        return candidateHotels.filter { !selected.contains($0.id) }
            .sorted { a, b in
                let first = preferredStars.map { abs($0 - a.roundedStars) } ?? 0
                let second = preferredStars.map { abs($0 - b.roundedStars) } ?? 0
                if first != second { return first < second }
                return (a.rating ?? 0) > (b.rating ?? 0)
            }
            .prefix(8).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IumrahGraphiteSearchSurface(
                isExpanded: $searchExpanded,
                summary: searchExpanded ? NuiteeCopy.text("Название отеля", "Mehmonxona nomi", "Hotel name", settings.language) : (normalizedQuery.isEmpty ? city.title(settings.language) : normalizedQuery),
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
                            .foregroundStyle(.black)
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
                    Divider()
                    HStack(spacing: 12) {
                        Label(NuiteeCopy.text("Комнат", "Xonalar", "Rooms", settings.language), systemImage: "bed.double")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Stepper("\(draftRooms)", value: $draftRooms, in: 1...5).fixedSize()
                    }
                    Divider()
                    HStack(spacing: 12) {
                        Label(NuiteeCopy.text("Детей", "Bolalar", "Children", settings.language), systemImage: "figure.child")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Stepper("\(draftChildren)", value: $draftChildren, in: 0...6).fixedSize()
                    }
                    Divider()
                    HStack(spacing: 12) {
                        Label(NuiteeCopy.text("Младенцев", "Chaqaloqlar", "Infants", settings.language), systemImage: "figure.child.circle")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Stepper("\(draftInfants)", value: $draftInfants, in: 0...4).fixedSize()
                    }
                    if draftRooms != 1 || draftChildren > 0 || draftInfants > 0 {
                        Text(NuiteeCopy.text("Каталожная цена рассчитана только для взрослых и одного номера. Итоговая стоимость с детьми и несколькими комнатами будет проверяться отдельно.", "Katalog narxi faqat kattalar va bitta xona uchun. Yakuniy narx alohida tekshiriladi.", "Catalogue rates only cover adults in one room. Child and multi-room pricing requires separate verification.", settings.language))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        checkin = draftCheckin
                        nights = draftNights
                        adults = draftAdults
                        rooms = draftRooms
                        children = draftChildren
                        infants = draftInfants
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
                    .buttonStyle(.borderedProminent).tint(.black)
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


            // The package tiers are presentation filters, not supplier bookings.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tierChip(nil, title: NuiteeCopy.text("Все пакеты", "Barcha paketlar", "All packages", settings.language))
                    ForEach(PackageTier.allCases) { tier in
                        tierChip(tier, title: tier.title(settings.language))
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                ForEach([0, 1, 2, 3, 4, 5], id: \.self) { star in
                    Button {
                        stars = star
                        visibleCount = 20
                    } label: {
                        Text(star == 0 ? NuiteeCopy.text("Все", "Barchasi", "All", settings.language) : "\(star) ★")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(stars == star ? Color.white : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(stars == star ? Color.black : Color.iumrahCardBackground, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Label(NuiteeCopy.text("Обновить", "Yangilash", "Refresh", settings.language), systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }

            if model.sandbox {
                Label(NuiteeCopy.text("Предварительные цены · бронирование пока недоступно", "Taxminiy narxlar · bronlash hali mavjud emas", "Indicative prices · booking unavailable", settings.language), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.catalogStale {
                Label(NuiteeCopy.text("Данные обновляются, показан кеш", "Keshlangan maʼlumotlar", "Showing cached data", settings.language), systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.rateError != nil {
                Text(NuiteeCopy.text("Цены временно недоступны. Каталог можно просматривать.", "Narxlar vaqtincha mavjud emas.", "Prices temporarily unavailable; catalogue is still accessible.", settings.language))
                    .font(.caption).foregroundStyle(.secondary)
            }

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
                    .buttonStyle(.borderedProminent).tint(.black)
                }
                .frame(maxWidth: .infinity).padding(25)
            } else if candidateHotels.isEmpty && !model.busy {
                ContentUnavailableView(NuiteeCopy.text("Нет отелей", "Mehmonxonalar topilmadi", "No hotels", settings.language), systemImage: "building.2", description: Text(NuiteeCopy.text("Попробуйте другой фильтр или даты", "Filtr yoki sanani almashtiring", "Change stars or dates", settings.language)))
            } else {
                if !normalizedQuery.isEmpty {
                    Text(NuiteeCopy.text("Результаты поиска", "Qidiruv natijalari", "Search results", settings.language))
                        .font(.headline)
                }
                HStack {
                    Text("\(matchingHotels.count) " + NuiteeCopy.text("отелей", "mehmonxona", "hotels", settings.language))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                if matchingHotels.isEmpty && !normalizedQuery.isEmpty {
                    Text(NuiteeCopy.text("Точных совпадений нет. Ниже — другие отели города.", "Mos mehmonxona topilmadi. Quyida boshqa variantlar.", "No matching hotels. Explore other stays below.", settings.language))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 12) {
                    ForEach(Array(matchingHotels.prefix(visibleCount))) { hotel in
                        NuiteeHotelListingCard(
                            hotel: hotel, nights: nights, adults: adults, sandbox: model.sandbox,
                            favorite: favorites.contains(hotel.id),
                            onOpen: { opened = hotel }, onFavorite: { toggleFavorite(hotel.id) }
                        )
                    }
                    if matchingHotels.count > visibleCount {
                        Color.clear.frame(height: 1).onAppear { visibleCount += 20 }
                    }
                }
                if !alternativeHotels.isEmpty {
                    Text(NuiteeCopy.text("Похожие отели в городе", "Shahardagi o‘xshash mehmonxonalar", "Alternative hotels nearby", settings.language))
                        .font(.headline).padding(.top, 12)
                    LazyVStack(spacing: 12) {
                        ForEach(alternativeHotels) { hotel in
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
        .onChange(of: refreshSignal) { _, _ in Task { await reload() } }
        .sheet(isPresented: $calendarPresented) {
            NuiteeStayCalendarSheet(checkin: $draftCheckin, nights: $draftNights)
        }
        .navigationDestination(item: $opened) { hotel in
            NuiteeHotelDetailView(hotel: hotel, checkin: checkin, nights: nights, adults: adults, sandbox: model.sandbox)
        }
    }

    private func tierChip(_ tier: PackageTier?, title: String) -> some View {
        let isSelected = selectedTier == tier
        return Button {
            selectedTier = tier
            stars = 0
            visibleCount = 20
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.black)
                .padding(.horizontal, 15).frame(height: 38)
                .background(isSelected ? Color.black : Color.white, in: Capsule())
        }.buttonStyle(.plain)
    }

    private func reload() async {
        visibleCount = 20
        await model.reload(city: city, checkin: checkin, checkout: checkout, adults: adults)
    }
    private func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "iumrah.nuitee.favorites.v1")
    }
}

private struct NuiteeHotelListingCard: View {
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
            let width = min(max(proxy.size.width * 0.31, 108), 122)
            HStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    NuiteeCatalogPreviewCollage(hotel: hotel)
                        .frame(width: width, height: 204)
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
                VStack(alignment: .leading, spacing: 7) {
                    Text(hotel.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    HStack(spacing: 7) {
                        if hotel.roundedStars > 0 {
                            Text(String(repeating: "★", count: hotel.roundedStars))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.primary)
                        }
                        if let rating = hotel.rating { Text(String(format: "%.1f", rating)).font(.caption).foregroundStyle(.secondary) }
                    }
                    Label(hotel.city, systemImage: "mappin.and.ellipse")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let rate = hotel.minimumRate, rate.price > 0 {
                        Text(NuiteeHotelService.usd(rate.price))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text("\(nights) " + NuiteeCopy.text("ночь · 1 номер · ", "tun · 1 xona · ", "nights · 1 room · ", settings.language) + "\(adults) " + NuiteeCopy.text("гостя", "mehmon", "guests", settings.language))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text(NuiteeCopy.text("Цена недоступна", "Narx mavjud emas", "Rate unavailable", settings.language)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text(sandbox ? NuiteeCopy.text("Предварительная цена", "Taxminiy narx", "Indicative price", settings.language) : NuiteeCopy.text("Стоимость проживания", "Turar joy narxi", "Stay price", settings.language))
                            .font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: 204)
        }
        .frame(height: 204)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 27))
        .clipShape(RoundedRectangle(cornerRadius: 27))
        .contentShape(RoundedRectangle(cornerRadius: 27))
        .onTapGesture(perform: onOpen)
    }
}

private struct NuiteeHotelCollage: View {
    let images: [String]
    var body: some View {
        GeometryReader { box in
            if images.count < 2 {
                HotelCachedImage(rawURL: images.first)
                    .frame(width: box.size.width, height: box.size.height)
                    .clipped()
            } else if images.count == 2 {
                VStack(spacing: 3) {
                    HotelCachedImage(rawURL: images[0])
                        .frame(height: box.size.height * 0.64)
                        .clipped()
                    HotelCachedImage(rawURL: images[1])
                        .frame(height: box.size.height * 0.36 - 3)
                        .clipped()
                }
            } else {
            let gap: CGFloat = 3
            let upper = box.size.height * 0.64
            VStack(spacing: gap) {
                HotelCachedImage(rawURL: images.first).frame(height: upper).clipped()
                HStack(spacing: gap) {
                    HotelCachedImage(rawURL: images.count > 1 ? images[1] : nil)
                    HotelCachedImage(rawURL: images.count > 2 ? images[2] : nil)
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

    @State private var detail: NuiteeHotelDetail?
    @State private var rates: [NuiteeRoomRate] = []
    @State private var detailError: String?
    @State private var ratesError: String?
    @State private var ratesLoading = false
    @State private var ratesRequestID = UUID()
    @State private var isGalleryPresented = false
    @State private var showSaveConfirmation = false
    @State private var chosenOffer: NuiteeRoomRate?
    @State private var expandedRoomRate: NuiteeRoomRate?
    private let service = NuiteeHotelService()

    private var checkout: Date { Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin }
    private var reloadID: String { "\(hotel.id):\(checkin.timeIntervalSince1970):\(nights):\(adults)" }
    private var photos: [String] {
        let list = detail?.images ?? []
        return list.isEmpty ? [hotel.coverImageURL].compactMap { $0 } : list
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
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
                            ForEach(detail.amenities.prefix(12), id: \.self) { label in
                                Label(label, systemImage: "checkmark.circle")
                                    .font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if !detail.description.isEmpty {
                        sectionTitle(NuiteeCopy.text("Об отеле", "Mehmonxona haqida", "About this hotel", settings.language))
                        Text(detail.description).font(.subheadline)
                    }
                }
                staySelector
                sectionTitle(NuiteeCopy.text("Выберите номер", "Xona tanlang", "Choose a room", settings.language))
                if ratesLoading { ProgressView().frame(maxWidth: .infinity).padding(22) }
                else if let ratesError {
                    Label(ratesError, systemImage: "exclamationmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Повторить") { Task { await refreshRates() } }.tint(.primary)
                } else if rates.isEmpty {
                    Text(NuiteeCopy.text("На выбранные даты нет доступных тарифов.", "Bu sanalarda xona mavjud emas.", "No rooms available for these dates.", settings.language))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(rates) { rate in rateCard(rate) }
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
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: hotel.name + " — " + (hotel.address ?? hotel.city)) {
                Image(systemName: "square.and.arrow.up")
            }
        } }
        .task { await refreshDetail() }
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
        .alert("Выбор номера сохранён", isPresented: $showSaveConfirmation) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("Отель и тариф сохранены для дальнейшего расчёта. Это ещё не подтверждённая бронь и не итоговая стоимость умра-пакета. Генератор пересчитает стоимость отдельно после интеграции серверного расчёта Nuitee.")
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
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private func saveRate(_ rate: NuiteeRoomRate) {
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
            Button { saveRate(rate) } label: {
                Text(NuiteeCopy.text("Добавить в план умры", "Umra rejasiga qo‘shish", "Add to Umrah plan", settings.language))
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).frame(height: 48)
            }
            .buttonStyle(.borderedProminent).tint(.black)
            .disabled(rate.offerId.isEmpty)
        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
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
                     + entry.element.until
                     + (entry.element.amount.map {
                        NuiteeCopy.text(" · штраф ", " · jarima ", " · penalty ", settings.language)
                        + NuiteeHotelService.usd($0)
                       } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !rate.chargeOnArrival.isEmpty {
                Text(NuiteeCopy.text("Некоторые налоги/сборы оплачиваются отдельно в отеле.", "Baʼzi soliqlar va yig‘imlar mehmonxonada alohida to‘lanadi.", "Some taxes and fees are paid at the hotel.", settings.language))
                    .font(.caption).foregroundStyle(.secondary)
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
            Text(NuiteeCopy.text(
                "Для запроса цены сервер передаёт Nuitee даты проживания, количество гостей и гражданство по умолчанию (UZ). API-ключ хранится только на сервере. Данные паспортов здесь не запрашиваются.",
                "Narx so‘rovlarida sanalar, mehmonlar soni va UZ fuqaroligi yuboriladi. Pasport maʼlumotlari olinmaydi.",
                "Rate lookup sends stay dates, guest count and default nationality (UZ) to Nuitee. Passport details are not collected here.", settings.language
            )).font(.footnote).foregroundStyle(.secondary)
            if sandbox {
                Label(NuiteeCopy.text("Цены предварительные. Подтверждение и оплата пока недоступны.", "Narxlar taxminiy. Tasdiqlash va to‘lov hali mavjud emas.", "Prices are indicative. Confirmation and payment are unavailable.", settings.language), systemImage: "info.circle")
                    .font(.caption.weight(.medium))
            }
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
        do { detail = try await service.detail(hotelID: hotel.id) }
        catch { detailError = error.localizedDescription }
    }
    private func refreshRates() async {
        let requestID = UUID()
        ratesRequestID = requestID
        let requestedCheckin = checkin
        let requestedCheckout = checkout
        let requestedAdults = adults
        ratesLoading = true
        ratesError = nil
        rates = []
        do {
            let result = try await service.rates(hotelID: hotel.id, checkin: requestedCheckin, checkout: requestedCheckout, adults: requestedAdults)
            guard ratesRequestID == requestID, !Task.isCancelled else { return }
            rates = result.rates
        } catch {
            guard ratesRequestID == requestID, !Task.isCancelled else { return }
            ratesError = error.localizedDescription
        }
        if ratesRequestID == requestID { ratesLoading = false }
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

// Lazy image enrichment: request full static detail only for cards that become
// visible and have fewer than 3 real supplier photos. The server caches detail.
private actor NuiteePreviewGate {
    static let shared = NuiteePreviewGate()
    private var running = 0
    func acquire() async -> Bool {
        while running >= 3 {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(120))
        }
        guard !Task.isCancelled else { return false }
        running += 1
        return true
    }
    func release() { running = max(0, running - 1) }
}

@MainActor
private final class NuiteePreviewCache {
    static let shared = NuiteePreviewCache()
    private var photos: [String: [String]] = [:]
    func get(_ id: String) -> [String]? { photos[id] }
    func put(_ id: String, images: [String]) { photos[id] = images }
}

private struct NuiteeCatalogPreviewCollage: View {
    let hotel: NuiteeHotel
    @State private var enriched: [String] = []
    private var initial: [String] {
        let values = hotel.previewImages ?? []
        return values.isEmpty ? [hotel.coverImageURL].compactMap { $0 } : values
    }
    var body: some View {
        NuiteeHotelCollage(images: enriched.count >= 3 ? enriched : initial)
            .task(id: hotel.id) {
                guard initial.count < 3 else { return }
                if let stored = NuiteePreviewCache.shared.get(hotel.id) {
                    enriched = stored
                    return
                }
                guard await NuiteePreviewGate.shared.acquire() else { return }
                defer { Task { await NuiteePreviewGate.shared.release() } }
                guard !Task.isCancelled else { return }
                guard let detail = try? await NuiteeHotelService().detail(hotelID: hotel.id) else { return }
                var seen = Set<String>()
                let photos = (initial + detail.images).filter { !$0.isEmpty && seen.insert($0).inserted }
                NuiteePreviewCache.shared.put(hotel.id, images: photos)
                enriched = photos
            }
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
                        Text(deadline.until + (deadline.amount.map { " · " + NuiteeHotelService.usd($0) } ?? ""))
                            .font(.footnote).foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent).tint(.black)
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
                .buttonStyle(.borderedProminent).tint(.black)
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
