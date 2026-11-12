import SwiftUI

/// Same server-priced review and OTP checkout as Hotel First / Flight First.
struct LocalJourneyReviewView: View {
    var body: some View { LegacyFinalPackageView() }
}

/// Shared, localized stay summary for the hotel detail and package review.
struct IumrahHotelStaySummary: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let checkin: Date
    let checkout: Date
    let nights: Int
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    private func dateColumn(_ title: String, _ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: settings.language.localeIdentifier))))
                .font(.title3.weight(.bold))
            Text(date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: settings.language.localeIdentifier))))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(tr("Ваше проживание", "Your stay", "Sizning yashashingiz", "Сизнинг яшашингиз"), systemImage: "calendar")
                .font(.headline)
            HStack(alignment: .top, spacing: 18) {
                dateColumn(tr("Заезд", "Check-in", "Kirish", "Кириш"), checkin)
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1, height: 76)
                dateColumn(tr("Выезд", "Check-out", "Chiqish", "Чиқиш"), checkout)
            }
            Divider()
            Label(L10n.format("booking_nights_count", settings.language, nights), systemImage: "moon")
                .font(.subheadline.weight(.semibold))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct IumrahHotelMealsEditor: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var selection: HotelMealChoices
    let stars: Int
    let city: String
    let included: HotelMealChoices
    private var madinah: Bool {
        let name = city.lowercased()
        return name.contains("madin") || name.contains("medin") || name.contains("медин") || name.contains("мадин")
    }
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Питание в отеле", "Hotel meals", "Mehmonxonada ovqatlanish", "Меҳмонхонада овқатланиш"), systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
            mealRow(tr("Завтрак", "Breakfast", "Nonushta", "Нонушта"), key: \.breakfast,
                included: included.breakfast || stars >= 4, packageIncluded: !included.breakfast && stars >= 4)
            if !madinah {
                mealRow(tr("Обед", "Lunch", "Tushlik", "Тушлик"), key: \.lunch, included: included.lunch)
            }
            mealRow(tr("Ужин", "Dinner", "Kechki ovqat", "Кечки овқат"), key: \.dinner, included: included.dinner)
            Text(tr("Дополнительное питание учитывается в итоговой цене пакета для гостей этого номера на весь срок проживания.",
                "Extra meals are included in the package calculation for this room’s guests throughout the stay.",
                "Qo‘shimcha ovqatlanish ushbu xona mehmonlari uchun butun yashash muddatiga paket narxida hisoblanadi.",
                "Қўшимча овқатланиш ушбу хона меҳмонлари учун бутун яшаш муддатига пакет нархида ҳисобланади."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func mealRow(_ title: String, key: WritableKeyPath<HotelMealChoices, Bool>, included: Bool, packageIncluded: Bool = false) -> some View {
        if included {
            HStack(alignment: .top) {
                Text(title)
                Spacer()
                Text(packageIncluded ? tr("Включён в пакет iumrah", "Included by iumrah", "iumrah paketiga kiritilgan", "iumrah пакетига киритилган") : tr("Включено в тариф", "Included in rate", "Tarifga kiritilgan", "Тарифга киритилган"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
            }.font(.subheadline).padding(.vertical, 5)
        } else {
            Toggle(title, isOn: Binding(get: { selection[keyPath: key] }, set: { selection[keyPath: key] = $0 }))
                .font(.subheadline).tint(Color.iumrahInk)
        }
    }
}

/// Loads only when mounted on a concrete hotel page; never from catalogue cards.
struct IumrahHotelReviewsSection: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let hotelID: String
    let rating: Double?
    let reviewCount: Int?
    @State private var reviews: [NuiteeGuestReview] = []
    @State private var nextOffset: Int?
    @State private var total: Int?
    @State private var loading = false
    @State private var failed = false
    @State private var stale = false
    @State private var showAll = false
    @State private var generation = UUID()
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Отзывы и рейтинг", "Reviews and rating", "Sharhlar va reyting", "Шарҳлар ва рейтинг"))
                .font(.title2.bold())
            HStack(spacing: 12) {
                if let rating {
                    Text(String(format: "%.1f", rating))
                        .font(.title2.bold()).padding(14)
                        .foregroundStyle(Color.iumrahPrimaryButtonText)
                        .background(Color.iumrahPrimaryButtonBackground, in: RoundedRectangle(cornerRadius: 16))
                    Text(tr("Оценка гостей · из 10", "Guest rating · out of 10", "Mehmonlar bahosi · 10 dan", "Меҳмонлар баҳоси · 10 дан"))
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
                if let count = total ?? reviewCount {
                    Text("\(count) " + tr("отзывов", "reviews", "sharh", "шарҳ"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !reviews.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(reviews) { review in
                            Button { showAll = true } label: { reviewCard(review, compact: true).frame(width: 280) }
                                .buttonStyle(.plain)
                        }
                    }.padding(.vertical, 2)
                }
                Button(tr("Все отзывы", "All reviews", "Barcha sharhlar", "Барча шарҳлар")) { showAll = true }
                    .font(.subheadline.weight(.semibold)).tint(.primary)
            } else if loading {
                Text(tr("Загружаем отзывы…", "Loading reviews…", "Sharhlar yuklanmoqda…", "Шарҳлар юкланмоқда…"))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !failed {
                Text(tr("Поставщик пока не передал тексты отзывов.", "The supplier has not provided review text yet.", "Yetkazib beruvchi hali sharh matnlarini yubormagan.", "Етказиб берувчи ҳали шарҳ матнларини юбормаган."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if failed { retryButton }
            if stale {
                Text(tr("Показаны сохранённые отзывы", "Showing saved reviews", "Saqlangan sharhlar ko‘rsatilmoqda", "Сақланган шарҳлар кўрсатилмоқда"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: hotelID + settings.language.rawValue) { await load(reset: true) }
        .sheet(isPresented: $showAll) {
            NavigationStack {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(reviews) { review in reviewCard(review, compact: false) }
                        if failed { retryButton }
                        else if nextOffset != nil {
                            Button(tr("Ещё отзывы", "More reviews", "Yana sharhlar", "Яна шарҳлар")) {
                                Task { await load(reset: false) }
                            }.disabled(loading).tint(.primary)
                        }
                    }.padding(20)
                }
                .background(Color.iumrahPageBackground)
                .navigationTitle(tr("Отзывы гостей", "Guest reviews", "Mehmonlar sharhlari", "Меҳмонлар шарҳлари"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("Готово", "Done", "Tayyor", "Тайёр")) { showAll = false }
                    }
                }
            }.presentationDragIndicator(.visible)
        }
    }
    private var retryButton: some View {
        Button(tr("Не удалось загрузить отзывы. Повторить", "Could not load reviews. Retry", "Sharhlar yuklanmadi. Qayta urinish", "Шарҳлар юкланмади. Қайта уриниш")) {
            Task { await load(reset: reviews.isEmpty) }
        }.font(.subheadline).tint(.primary).disabled(loading)
    }
    private func reviewCard(_ review: NuiteeGuestReview, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(String(review.name.prefix(1)).uppercased())
                    .font(.headline).frame(width: 40, height: 40)
                    .background(Color.primary.opacity(0.06), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(review.name.isEmpty ? tr("Гость", "Guest", "Mehmon", "Меҳмон") : review.name).font(.subheadline.bold())
                    if !review.country.isEmpty {
                        Text(Locale(identifier: settings.language.localeIdentifier).localizedString(forRegionCode: review.country.uppercased()) ?? review.country)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let score = review.rating { Text(String(format: "%.1f", score)).font(.headline) }
            }
            if !review.headline.isEmpty { Text(review.headline).font(.subheadline.bold()).lineLimit(compact ? 2 : nil) }
            if !review.pros.isEmpty { Text(review.pros).font(.subheadline).lineLimit(compact ? 4 : nil) }
            if !review.cons.isEmpty {
                Text(tr("Что можно улучшить: ", "Could be improved: ", "Yaxshilash mumkin: ", "Яхшилаш мумкин: ") + review.cons)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(compact ? 3 : nil)
            }
            HStack {
                Text(reviewDate(review.date))
                Spacer()
                if !review.source.isEmpty { Text(review.source) }
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
    }
    private func reviewDate(_ value: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(value.prefix(10))) else { return value }
        return date.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: settings.language.localeIdentifier)))
    }
    @MainActor private func load(reset: Bool) async {
        if !reset && loading { return }
        if reset { generation = UUID(); reviews = []; nextOffset = nil; total = nil; stale = false }
        let requestGeneration = generation
        loading = true; failed = false
        do {
            let result = try await NuiteeHotelService().reviews(hotelID: hotelID, language: settings.language.hotelContentCode, offset: reset ? 0 : (nextOffset ?? 0))
            guard !Task.isCancelled, generation == requestGeneration else { return }
            var ids = Set(reviews.map(\.id))
            reviews += result.reviews.filter { ids.insert($0.id).inserted }
            nextOffset = result.nextOffset; total = result.total; stale = result.stale; loading = false
        } catch {
            guard !Task.isCancelled, generation == requestGeneration else { return }
            failed = true; loading = false
        }
    }
}
