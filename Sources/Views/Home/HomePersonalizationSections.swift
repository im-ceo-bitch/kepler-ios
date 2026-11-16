import SwiftUI

/// These additive Home sections use the current app's navigation, supplier models
/// and Rewards dashboard. No price, membership tier or offer is synthesized.
private struct HomeSectionCopy {
    let language: AppSettingsStore.Language
    func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(language, ru, en, uz, cy)
    }
    func month(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: value)
    }
    func date(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateStyle = .medium; formatter.timeStyle = .none
        return formatter.string(from: value)
    }
}

private struct HomeSmallCard<Content: View>: View {
    let symbol: String
    let label: String
    var color: Color = .blue
    let content: Content
    init(symbol: String, label: String, color: Color = .blue, @ViewBuilder content: () -> Content) {
        self.symbol = symbol; self.label = label; self.color = color; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color).frame(width: 42, height: 42)
                    .iumrahGlass(in: Circle(), allowsStaticGlass: true)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
            content
            Spacer(minLength: 0)
        }
        .padding(15).frame(width: 220, height: 184, alignment: .topLeading)
        .foregroundStyle(.primary)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.primary.opacity(0.06)) }
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }
}

struct HomeRecentActivitySection: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var bookings: BookingStore
    @ObservedObject private var history = HomePersonalizationStore.shared
    let resumeSmart: (HomeSmartDraft) -> Void
    let repeatFlight: (TripDraft) -> Void
    private var c: HomeSectionCopy { .init(language: settings.language) }
    private var activity: HomeActivitySnapshot { history.snapshot(owner: HomePersonalizationStore.owner(account)) }
    private var active: StoredBookingSession? {
        guard account.isAuthenticated else { return nil }
        return bookings.homeSessions(accountToken: account.bearerToken).first { !["COMPLETED", "CANCELLED", "CANCELED"].contains($0.effectiveStatus.uppercased()) }
    }
    var body: some View {
        let data = activity
        if data.smart != nil || data.flightSearch != nil || !data.hotels.isEmpty || active != nil {
            VStack(alignment: .leading, spacing: 12) {
                IumrahHomeSectionHeader(title: c.t("Продолжите с того места, где остановились", "Pick up where you left off", "To‘xtagan joyingizdan davom eting", "Тўхтаган жойингиздан давом этинг"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        if let booking = active {
                            Button { chrome.openBooking(id: booking.id) } label: {
                                HomeSmallCard(symbol: "suitcase.fill", label: c.t("Ваша поездка", "Your journey", "Safaringiz", "Сафарингиз"), color: .green) {
                                    Text("\(booking.booking.input.originCode) → \(booking.booking.input.arrivalAirportCode)").font(.title2.bold())
                                    Text(L10n.status(booking.effectiveStatus, settings.language)).font(.subheadline).lineLimit(2)
                                    Text(booking.displayBookingNumber).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                        if let draft = data.smart {
                            Button { resumeSmart(draft) } label: {
                                HomeSmallCard(symbol: draft.wasAssembled ? "checkmark.seal.fill" : "sparkles", label: draft.wasAssembled ? c.t("Недавно собранный пакет", "Recently assembled package", "Yaqinda tuzilgan paket", "Яқинда тузилган пакет") : c.t("Незавершённая Умра", "Unfinished Umrah", "Tugallanmagan Umra", "Тугалланмаган Умра")) {
                                    Text("iumrah Smart").font(.title3.bold())
                                    Text(c.month(draft.preferences.month) + " · " + String(draft.preferences.duration) + " " + c.t("дн.", "days", "kun", "кун")).font(.caption).foregroundStyle(.secondary)
                                    if !draft.wasAssembled {
                                        ProgressView(value: Double(min(8, max(0, draft.step))), total: 8).tint(.primary)
                                    }
                                    Text(draft.wasAssembled ? c.t("Проверить пакет", "Recheck package", "Paketni tekshirish", "Пакетни текшириш") : c.t("Продолжить сборку", "Continue", "Davom etish", "Давом этиш")).font(.caption.weight(.semibold))
                                }
                            }.buttonStyle(.plain)
                        }
                        if let trip = data.flightSearch {
                            Button { repeatFlight(trip) } label: {
                                HomeSmallCard(symbol: "airplane", label: c.t("Недавний поиск", "Recent search", "So‘nggi qidiruv", "Сўнгги қидирув")) {
                                    Text("\(trip.originCode) → \(trip.outboundDestinationCode)").font(.title2.bold())
                                    Text(c.date(trip.departureDate)).font(.caption).foregroundStyle(.secondary)
                                    Text(c.t("Повторить поиск", "Search again", "Qayta qidirish", "Қайта қидириш")).font(.caption.weight(.semibold))
                                }
                            }.buttonStyle(.plain)
                        }
                        ForEach(data.hotels.prefix(4)) { visit in
                            NavigationLink {
                                HomeRecentHotelDestination(visit: visit)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HotelCachedImage(rawURL: visit.hotel.coverImageURL, thumbnailPixelDimension: 420)
                                        .frame(height: 88).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                    Text(c.t("Просмотренный отель", "Viewed hotel", "Ko‘rilgan mehmonxona", "Кўрилган меҳмонхона")).font(.caption2).foregroundStyle(.secondary)
                                    Text(visit.hotel.name).font(.subheadline.bold()).lineLimit(2)
                                    Text(String(repeating: "★", count: visit.hotel.roundedStars)).font(.caption).foregroundStyle(.secondary)
                                    Spacer(minLength: 0)
                                }.padding(10).frame(width: 220, height: 184, alignment: .topLeading)
                                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain).foregroundStyle(.primary)
                        }
                    }.padding(.vertical, 2)
                }
            }.accessibilityIdentifier("iumrah.home.recent")
        }
    }
}

private struct HomeRecentHotelDestination: View {
    let visit: HomeHotelVisit
    var body: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let checkin = max(visit.checkin, Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today)
        NuiteeHotelDetailView(hotel: visit.hotel, checkin: checkin, nights: max(1, visit.nights), adults: max(1, visit.adults), sandbox: visit.sandbox)
    }
}

struct HomeDestinationsSection: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    private var c: HomeSectionCopy { .init(language: settings.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IumrahHomeSectionHeader(title: c.t("Ваше следующее путешествие", "Your next journey", "Keyingi safaringiz", "Кейинги сафарингиз"))
            HStack(spacing: 12) {
                city("makkah", image: "MakkahBackground", title: c.t("Мекка", "Makkah", "Makka", "Макка"), subtitle: c.t("Совершите Умру", "Perform Umrah", "Umra ziyorati", "Умра зиёрати"))
                city("madinah", image: "ZiyaratQuba1", title: c.t("Медина", "Madinah", "Madina", "Мадина"), subtitle: c.t("Город Пророка ﷺ", "City of the Prophet ﷺ", "Payg‘ambarimiz ﷺ shahri", "Пайғамбаримиз ﷺ шаҳри"))
            }
        }
    }
    private func city(_ city: String, image: String, title: String, subtitle: String) -> some View {
        Button {
            let day = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
            chrome.findHotels(.init(city: city, checkin: day, nights: 7, adults: 2))
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { proxy in
                    Image(image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }.frame(height: 138).clipShape(RoundedRectangle(cornerRadius: 15))
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }
}

struct HomeRewardsOffersSection: View {
    var showsRewards = true
    var showsOffers = true
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var chrome: AppChromeStore
    @Environment(\.iumrahTabIsActive) private var activeTab
    @State private var dashboard: IumrahFriendsDashboard?
    @State private var owner: String?
    @State private var loadedAt: Date?
    private var c: HomeSectionCopy { .init(language: settings.language) }
    private var live: IumrahFriendsDashboard? { account.isAuthenticated && owner == account.bearerToken ? dashboard : nil }
    private var tier: String? {
        guard let tier = live?.tier, ["member", "plus", "elite"].contains(tier.lowercased()) else { return nil }
        return tier.capitalized
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if showsRewards {
            VStack(alignment: .leading, spacing: 12) {
                IumrahHomeSectionHeader(title: c.t("Путешествуйте с преимуществами", "Travel with benefits", "Imtiyozlar bilan sayohat qiling", "Имтиёзлар билан саёҳат қилинг"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        if account.isAuthenticated {
                            NavigationLink { IumrahRewardsVisualPage(language: settings.language) } label: { tierCard }.buttonStyle(.plain)
                            NavigationLink { IumrahFriendsVisualPage(language: settings.language) } label: { referralCard }.buttonStyle(.plain)
                        } else {
                            Button { chrome.navigate(to: .account) } label: { tierCard }.buttonStyle(.plain)
                            Button { chrome.navigate(to: .account) } label: { referralCard }.buttonStyle(.plain)
                        }
                        if let tier, tier != "Elite" {
                            NavigationLink { IumrahRewardsVisualPage(language: settings.language) } label: {
                                HomeSmallCard(symbol: "lock.fill", label: c.t("Следующий уровень", "Next level", "Keyingi daraja", "Кейинги даража"), color: .secondary) {
                                    Text(tier == "Member" ? "iumrah Plus" : "iumrah Elite").font(.title3.bold())
                                    Text(c.t("Условия и ваш прогресс", "Requirements and your progress", "Shartlar va natijangiz", "Шартлар ва натижангиз")).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            }
            if showsOffers {
            VStack(alignment: .leading, spacing: 12) {
                IumrahHomeSectionHeader(title: c.t("Специальные предложения", "Special offers", "Maxsus takliflar", "Махсус таклифлар"))
                if live?.invitation != nil {
                    NavigationLink { IumrahFriendsVisualPage(language: settings.language) } label: { offerCard }.buttonStyle(.plain)
                } else if account.isAuthenticated {
                    NavigationLink { IumrahRewardsVisualPage(language: settings.language) } label: { offerCard }.buttonStyle(.plain)
                } else {
                    Button { chrome.navigate(to: .account) } label: { offerCard }.buttonStyle(.plain)
                }
            }
            }
        }
        .task(id: "\(account.iumrahID ?? "guest")-\(activeTab)") {
            guard activeTab else { return }
            await load()
        }
    }
    private var tierCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("iumrah Rewards").font(.headline); Spacer(); Image(systemName: "star.fill").foregroundStyle(.yellow).frame(width: 38, height: 38).iumrahGlass(in: Circle(), allowsStaticGlass: true) }
            Spacer(minLength: 0)
            Text(tier ?? "iumrah Rewards").font(.title2.bold())
            Text(tier != nil ? c.t("Ваш текущий уровень", "Your current level", "Joriy darajangiz", "Жорий даражангиз") : c.t("Откройте программу лояльности", "Explore loyalty rewards", "Sodiqlik dasturini oching", "Содиқлик дастурини очинг")).font(.subheadline).foregroundStyle(.white.opacity(0.75))
        }.padding(17).frame(width: 220, height: 184, alignment: .leading).foregroundStyle(.white)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 22)).environment(\.colorScheme, .dark)
    }
    private var referralCard: some View {
        HomeSmallCard(symbol: "gift.fill", label: "iumrah Friends", color: .green) {
            Text(live?.invitation != nil ? "+$100" : c.t("Пригласите друга", "Invite a friend", "Do‘stingizni taklif qiling", "Дўстингизни таклиф қилинг")).font(.title2.bold())
            Text(c.t("Вознаграждение после подтверждения оплаты его первой поездки", "Reward after confirmed payment for their first trip", "Birinchi safar to‘lovi tasdiqlangach mukofot", "Биринчи сафар тўлови тасдиқлангач мукофот")).font(.caption).foregroundStyle(.secondary).lineLimit(3)
        }
    }
    private var offerCard: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(live?.invitation != nil ? c.t("Ваши рекомендации", "Your referrals", "Tavsiyalaringiz", "Тавсияларингиз") : "iumrah Rewards").font(.caption).foregroundStyle(.secondary)
                Text(live?.invitation != nil ? c.t("$100 за успешное приглашение", "$100 per successful referral", "Muvaffaqiyatli taklif uchun $100", "Муваффақиятли таклиф учун $100") : c.t("Откройте свои преимущества", "Unlock your benefits", "Imtiyozlaringizni oching", "Имтиёзларингизни очинг")).font(.title3.bold())
                Text(live?.invitation != nil ? c.t("После подтверждённой оплаты поездки другом", "After your friend's confirmed trip payment", "Do‘stingizning safari to‘lovi tasdiqlangach", "Дўстингизнинг сафари тўлови тасдиқлангач") : c.t("Условия программы лояльности", "Loyalty program details", "Sodiqlik dasturi shartlari", "Содиқлик дастури шартлари")).font(.caption).foregroundStyle(.secondary)
                Text(c.t("Подробнее", "Learn more", "Batafsil", "Батафсил")).font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            Image(systemName: "gift.fill").font(.system(size: 32, weight: .medium)).foregroundStyle(.green).frame(width: 66, height: 66).iumrahGlass(in: Circle(), allowsStaticGlass: true)
        }.padding(17).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }
    @MainActor private func load() async {
        guard account.isAuthenticated, let token = account.bearerToken else { dashboard = nil; owner = nil; return }
        if owner != token { dashboard = nil; loadedAt = nil; owner = token }
        if let loadedAt, Date().timeIntervalSince(loadedAt) < 60 { return }
        do {
            let response = try await account.rewardsDashboard()
            guard !Task.isCancelled, account.isAuthenticated, account.bearerToken == token else { return }
            dashboard = response; loadedAt = Date()
        } catch {
            guard !Task.isCancelled, account.bearerToken == token else { return }
            dashboard = nil; loadedAt = Date()
        }
    }
}

struct HomeAvailablePackagesSection: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var journey: JourneyStore
    @Environment(\.iumrahTabIsActive) private var activeTab
    @State private var packages: [StorefrontServerPackageSnapshot] = []
    @State private var loadedOrigin: String?
    let startSmart: () -> Void
    private var c: HomeSectionCopy { .init(language: settings.language) }
    var body: some View {
        let points = loadedOrigin == journey.trip.originCode ? packages.filter { String($0.startDate.prefix(10)) >= SmartConfiguratorPreferences.key(Date()) } : []
        VStack(alignment: .leading, spacing: 12) {
            IumrahHomeSectionHeader(title: c.t("Актуальные пакеты Умры", "Umrah packages", "Umra paketlari", "Умра пакетлари"))
            if points.isEmpty {
                Button(action: startSmart) {
                    HStack(spacing: 13) {
                        Image(systemName: "suitcase.fill").font(.title2).frame(width: 48, height: 48).iumrahGlass(in: Circle(), allowsStaticGlass: true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(c.t("Подобрать пакет по вашим датам", "Find a package for your dates", "Sanalaringizga mos paket", "Саналарингизга мос пакет")).font(.headline)
                            Text(c.t("Рейсы, отели и услуги — единая стоимость", "Flights, hotels and services — one total", "Reys, mehmonxona va xizmatlar — bitta narx", "Рейс, меҳмонхона ва хизматлар — битта нарх")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }.padding(16).foregroundStyle(.primary).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(points) { point in
                            Button { chrome.openPackage(id: point.id) } label: {
                                HomeSmallCard(symbol: "calendar", label: String(point.startDate.prefix(10))) {
                                    Text(point.hotelName).font(.subheadline.bold()).lineLimit(2)
                                    Text(point.pricePerPerson?.formatted(.currency(code: "USD")) ?? "—").font(.title2.bold())
                                    Text(c.t("На одного паломника", "Per traveler", "Bir ziyoratchiga", "Бир зиёратчига")).font(.caption).foregroundStyle(.secondary)
                                    Text(c.t("Тариф требует проверки", "Subject to recheck", "Tarif tekshiriladi", "Тариф текширилади")).font(.caption2).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task(id: "\(journey.trip.originCode)-\(activeTab)") {
            guard activeTab else { return }
            let origin = journey.trip.originCode
            let values = await HomePublicContentCache.shared.packages(origin: origin)
            guard !Task.isCancelled, origin == journey.trip.originCode else { return }
            packages = values; loadedOrigin = origin
        }
    }
}

struct HomeRecommendedHotelsSection: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var history = HomePersonalizationStore.shared
    @Environment(\.iumrahTabIsActive) private var activeTab
    @State private var recommendations: [HomeHotelVisit] = []
    @State private var loadedKey: String?
    private var c: HomeSectionCopy { .init(language: settings.language) }
    private var recent: HomeHotelVisit? { history.snapshot(owner: HomePersonalizationStore.owner(account)).hotels.first }
    private var city: String { recent?.hotel.city.lowercased() == "madinah" ? "madinah" : "makkah" }
    private var key: String { (HomePersonalizationStore.owner(account) ?? "unknown") + "-" + city + "-" + (recent?.id ?? "default") }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            IumrahHomeSectionHeader(title: c.t("Рекомендуемые отели", "Recommended hotels", "Tavsiya etilgan mehmonxonalar", "Тавсия этилган меҳмонхоналар"))
            if loadedKey == key && !recommendations.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(recommendations) { visit in
                            NavigationLink { HomeRecentHotelDestination(visit: visit) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HotelCachedImage(rawURL: visit.hotel.coverImageURL, thumbnailPixelDimension: 420).frame(height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: 13))
                                    Text(visit.hotel.name).font(.subheadline.bold()).lineLimit(2)
                                    Text(String(repeating: "★", count: visit.hotel.roundedStars)).font(.caption).foregroundStyle(.secondary)
                                    if let rating = visit.hotel.rating { Text(rating.formatted(.number.precision(.fractionLength(1)))).font(.caption.bold()) }
                                    Spacer(minLength: 0)
                                }.padding(10).frame(width: 205, height: 202, alignment: .topLeading).foregroundStyle(.primary)
                                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Button {
                let date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
                chrome.findHotels(.init(city: city, checkin: date, nights: 7, adults: 2))
            } label: {
                HStack { Text(c.t("Посмотреть все отели", "View all hotels", "Barcha mehmonxonalar", "Барча меҳмонхоналар")).font(.subheadline.weight(.semibold)); Spacer(); Image(systemName: "chevron.right") }
                    .padding(16).foregroundStyle(.primary).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain)
        }
        .task(id: "\(key)-\(activeTab)") { if activeTab { await loadCached() } }
    }
    @MainActor private func loadCached() async {
        let requestKey = key
        guard loadedKey != requestKey else { return }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let date = max(recent?.checkin ?? Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(), tomorrow)
        let nights = recent?.nights ?? 7; let adults = recent?.adults ?? 2; let city = city
        let source = await HomePublicContentCache.shared.hotels(city: city, checkin: date, nights: nights, adults: adults)
        guard !Task.isCancelled, requestKey == key else { return }
        let hotels = (source?.hotels ?? []).filter { $0.id != recent?.id && $0.coverImageURL != nil }.sorted { ($0.rating ?? 0) > ($1.rating ?? 0) }
        recommendations = Array(hotels.prefix(4)).map { hotel in
            var clean = hotel; clean.minimumRate = nil; clean.rateStatus = nil
            return .init(hotel: clean, checkin: date, nights: nights, adults: adults, sandbox: source?.sandbox ?? true)
        }
        loadedKey = requestKey
    }
}

struct HomeWhyAndPreferencesSection: View {
    var showsWhy = true
    var showsPreferences = true
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @ObservedObject private var history = HomePersonalizationStore.shared
    @State private var expanded = false
    private var c: HomeSectionCopy { .init(language: settings.language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsWhy {
            VStack(alignment: .leading, spacing: 12) {
                IumrahHomeSectionHeader(title: c.t("Почему iumrah?", "Why iumrah?", "Nega iumrah?", "Нега iumrah?"))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        feature("person.2.fill", c.t("С семьёй, без группы", "With family, not a group", "Oila bilan, guruhsiz", "Оила билан, гуруҳсиз"), c.t("Путешествуйте в удобном темпе", "Travel at your own pace", "O‘zingizga qulay sur’atda", "Ўзингизга қулай суръатда"))
                        feature("shippingbox.fill", c.t("Единый пакет", "One package", "Bitta paket", "Битта пакет"), c.t("Рейсы, отели и услуги вместе", "Flights, hotels and services together", "Reys, mehmonxona va xizmatlar birga", "Рейс, меҳмонхона ва хизматлар бирга"))
                        feature("heart.fill", c.t("Персональная поддержка", "Personal support", "Shaxsiy yordam", "Шахсий ёрдам"), c.t("Сопровождение вашей поездки", "Support throughout your journey", "Safaringiz davomida yordam", "Сафарингиз давомида ёрдам"))
                        feature("slider.horizontal.3", c.t("Свобода выбора", "Freedom to choose", "Tanlash erkinligi", "Танлаш эркинлиги"), c.t("Уровень комфорта и маршрут на ваш выбор", "Your comfort level and route", "Qulaylik va yo‘nalishni tanlang", "Қулайлик ва йўналишни танланг"))
                    }
                }
            }
            }
            if showsPreferences {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(c.t("Персональные рекомендации", "Personal recommendations", "Shaxsiy tavsiyalar", "Шахсий тавсиялар"), isOn: Binding(get: { history.enabled }, set: { history.setEnabled($0) }))
                    Text(c.t("Недавние действия хранятся на этом устройстве. Отключение очищает историю рекомендаций, но не удаляет бронирования.", "Recent activity stays on this device. Turning it off clears recommendation history, not bookings.", "Tarix shu qurilmada saqlanadi. O‘chirish bronlarni emas, tavsiyalar tarixini tozalaydi.", "Тарих шу қурилмада сақланади. Ўчириш бронларни эмас, тавсиялар тарихини тозалайди.")).font(.caption).foregroundStyle(.secondary)
                    Button(c.t("Очистить недавние действия", "Clear recent activity", "So‘nggi harakatlarni tozalash", "Сўнгги ҳаракатларни тозалаш")) { history.clear(owner: HomePersonalizationStore.owner(account)) }.font(.subheadline.weight(.medium))
                }.padding(.top, 12)
            } label: {
                Label(c.t("Управление рекомендациями", "Manage recommendations", "Tavsiyalarni boshqarish", "Тавсияларни бошқариш"), systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
            }.tint(.primary).padding(16).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
    private func feature(_ icon: String, _ title: String, _ desc: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).frame(width: 46, height: 46).iumrahGlass(in: Circle(), allowsStaticGlass: true)
            Text(title).font(.headline)
            Text(desc).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }.padding(15).frame(width: 190, height: 168, alignment: .topLeading).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }
}
