import SwiftUI

// A visual-only package draft. These options are deliberately NOT sent to the
// PackageEngine, booked or included in an invented price calculation.
// Real flights and hotel selections are read from the existing stores.
private enum ConfiguratorCopy {
    static func text(_ ru: String, _ en: String, _ uz: String, _ lang: AppSettingsStore.Language) -> String {
        switch lang {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return ru
        default: return en
        }
    }
}

enum IumrahDraftService: String, CaseIterable, Identifiable {
    case transfer, ziyarat, guide, visa, meals
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .transfer: return "car.side"
        case .ziyarat: return "mappin.and.ellipse"
        case .guide: return "person.crop.circle.badge.checkmark"
        case .visa: return "doc.text.viewfinder"
        case .meals: return "fork.knife"
        }
    }
    func title(_ lang: AppSettingsStore.Language) -> String {
        switch self {
        case .transfer: return ConfiguratorCopy.text("Трансфер", "Transfers", "Transfer", lang)
        case .ziyarat: return ConfiguratorCopy.text("Зияраты", "Ziyarats", "Ziyoratlar", lang)
        case .guide: return ConfiguratorCopy.text("Гид", "Guide", "Gid", lang)
        case .visa: return ConfiguratorCopy.text("Виза Саудовской Аравии", "Saudi Arabia visa", "Saudiya Arabistoni vizasi", lang)
        case .meals: return ConfiguratorCopy.text("Питание", "Meals", "Ovqatlanish", lang)
        }
    }
    func detail(_ lang: AppSettingsStore.Language) -> String {
        switch self {
        case .transfer: return ConfiguratorCopy.text("Встреча в аэропорту, междугородний переезд и трансфер к обратному рейсу", "Airport pickup, intercity journey and return airport transfer", "Aeroportda kutib olish, shaharlararo va qaytish transferi", lang)
        case .ziyarat: return ConfiguratorCopy.text("Посещения святых мест Мекки и Медины по согласованной программе", "Visits to significant sites in Makkah and Madinah", "Makka va Madinadagi ziyorat manzillari", lang)
        case .guide: return ConfiguratorCopy.text("Помощь с обрядами и сопровождение. Наличие живого гида уточняется.", "Ritual guidance and assistance. Live guide availability to be confirmed.", "Ibodatlar bo‘yicha yo‘riqnoma va yordam. Gid mavjudligi tasdiqlanadi.", lang)
        case .visa: return ConfiguratorCopy.text("Условия зависят от гражданства и правил въезда. Виза не оформляется автоматически.", "Eligibility depends on citizenship and entry rules. No visa is issued automatically.", "Talablar fuqarolikka bog‘liq. Viza avtomatik berilmaydi.", lang)
        case .meals: return ConfiguratorCopy.text("Предпочтения по питанию; уже включённые в отель блюда не добавляются повторно", "Meal preferences; hotel-included meals are not added again", "Ovqatlanish tanlovi; mehmonxonaga kiritilgan taomlar qayta qo‘shilmaydi", lang)
        }
    }
}

@MainActor
final class IumrahConfiguratorVisualDraft: ObservableObject {
    private static let selectedKey = "iumrah.visualConfigurator.services.v1"
    private static let vehicleKey = "iumrah.visualConfigurator.vehicle.v1"
    private static let esimKey = "iumrah.visualConfigurator.esim.v1"

    @Published var selected: Set<IumrahDraftService> {
        didSet { UserDefaults.standard.set(selected.map(\.rawValue), forKey: Self.selectedKey) }
    }
    @Published var vehicle: String {
        didSet { UserDefaults.standard.set(vehicle, forKey: Self.vehicleKey) }
    }
    @Published var includeESIM: Bool {
        didSet { UserDefaults.standard.set(includeESIM, forKey: Self.esimKey) }
    }

    init() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.selectedKey) ?? []
        selected = Set(raw.compactMap(IumrahDraftService.init(rawValue:)))
        vehicle = UserDefaults.standard.string(forKey: Self.vehicleKey) ?? "private"
        includeESIM = UserDefaults.standard.bool(forKey: Self.esimKey)
    }
    func enabled(_ service: IumrahDraftService) -> Bool { selected.contains(service) }
    func set(_ service: IumrahDraftService, enabled: Bool) {
        if enabled { selected.insert(service) } else { selected.remove(service) }
    }
}

enum IumrahConfiguratorServiceScope: Equatable {
    case all, visa, transfer, guide
}

struct IumrahConfiguratorServicesView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject var draft: IumrahConfiguratorVisualDraft
    var scope: IumrahConfiguratorServiceScope = .all

    private var visibleServices: [IumrahDraftService] {
        switch scope {
        case .all: return IumrahDraftService.allCases
        case .visa: return [.visa]
        case .transfer: return [.transfer]
        case .guide: return [.guide, .ziyarat, .meals]
        }
    }

    private func t(_ ru: String, _ en: String, _ uz: String) -> String {
        ConfiguratorCopy.text(ru, en, uz, settings.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t("Дополнительные услуги", "Additional services", "Qo‘shimcha xizmatlar"))
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text(t("Выберите нужное. Это визуальный черновик: стоимость и подтверждение будут подключены позже.", "Choose what you need. Pricing and confirmation are not connected yet.", "Kerakli xizmatlarni tanlang. Narx va tasdiqlash keyin ulanadi."))
                .font(.subheadline).foregroundStyle(.secondary)

            ForEach(visibleServices) { service in
                serviceCard(service)
            }
            if scope == .guide || scope == .all {
                supportCard
            }
        }
        .padding(.top, 18)
    }

    private func serviceCard(_ service: IumrahDraftService) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: service.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 46, height: 46)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.title(settings.language)).font(.headline)
                    Text(draft.enabled(service) ? t("Добавлено в черновик", "Added to draft", "Qoralamaga qo‘shildi")
                         : t("По желанию", "Optional", "Ixtiyoriy"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle(service.title(settings.language), isOn: Binding(
                    get: { draft.enabled(service) },
                    set: { draft.set(service, enabled: $0) }
                ))
                .labelsHidden().tint(.black)
            }
            Text(service.detail(settings.language))
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if service == .transfer && draft.enabled(.transfer) {
                HStack(spacing: 8) {
                    vehicleButton("private", title: t("Личный", "Private", "Shaxsiy"))
                    vehicleButton("group", title: t("Групповой", "Shared", "Guruhli"))
                }
            }
            if service == .visa && draft.enabled(.visa) {
                Label(t("Документы и возможность оформления проверяются перед подтверждением.", "Documents and eligibility will be checked before confirmation.", "Hujjatlar tasdiqlashdan avval tekshiriladi."), systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }

    private func vehicleButton(_ value: String, title: String) -> some View {
        Button { draft.vehicle = value } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(draft.vehicle == value ? Color.white : Color.black)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(draft.vehicle == value ? Color.black : Color.black.opacity(0.05), in: Capsule())
        }.buttonStyle(.plain)
    }

    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "message.badge.waveform")
                    .font(.system(size: 21))
                    .frame(width: 46, height: 46)
                    .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Поддержка и связь", "Support & connectivity", "Yordam va aloqa")).font(.headline)
                    Text(t("Один раздел вместо отдельного шага eSIM", "One section, no separate eSIM step", "eSIM uchun alohida bosqich yo‘q"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(t("Помощь iumrah сопровождает подготовку и поездку. Каналы связи будут доступны в бронировании после подтверждения.", "iumrah assistance covers preparation and travel. Contact options will appear once booking is confirmed.", "iumrah safarga tayyorgarlik va safar davomida yordam beradi."))
                .font(.subheadline).foregroundStyle(.secondary)
            Divider()
            Toggle(isOn: $draft.includeESIM) {
                Label(t("Добавить eSIM в план", "Include eSIM in plan", "eSIMni rejaga qo‘shish"), systemImage: "simcard")
                    .font(.subheadline.weight(.semibold))
            }.tint(.black)
            Text(t("eSIM отмечается в черновике без покупки и активации.", "eSIM is saved as a preference, without purchase or activation.", "eSIM xarid yoki faollashtirishsiz rejaga saqlanadi."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(17)
        .background(.white, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
    }
}

struct IumrahConfiguratorSummaryView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var journey: JourneyStore
    @ObservedObject var draft: IumrahConfiguratorVisualDraft
    let onSelectStage: (HotelsShowcaseBoard) -> Void

    private func t(_ ru: String, _ en: String, _ uz: String) -> String {
        ConfiguratorCopy.text(ru, en, uz, settings.language)
    }
    private var selectedStays: [String: NuiteeSelectedStay] { NuiteeStaySelectionStore.shared.selections() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Ваша индивидуальная умра", "Your personalized Umrah", "Sizning shaxsiy umrangiz"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(t("Состав поездки · подробный предварительный просмотр", "Trip components · detailed preview", "Safar tarkibi · batafsil ko‘rish"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            summarySectionHeader(t("Авиабилеты", "Flights", "Aviachiptalar"), icon: "airplane", stage: .flights)
            if journey.stagedUmrahFlights.isEmpty && journey.selectedOutbound == nil && journey.selectedInbound == nil {
                emptySelection(t("Перелёты ещё не выбраны", "No flights selected yet", "Reyslar hali tanlanmagan"))
            } else {
                ForEach(journey.stagedUmrahFlights) { flight in
                    flightCard(route: flight.routeTitle, carrier: flight.airline, number: flight.flightNumber,
                               date: flight.departureAt, returning: nil)
                    if let returnDate = flight.returnAt, !returnDate.isEmpty {
                        flightCard(
                            route: t("Обратный рейс", "Return flight", "Qaytish reysi"),
                            carrier: flight.returnAirline ?? t("Авиакомпания уточняется", "Carrier to be confirmed", "Aviakompaniya tasdiqlanadi"),
                            number: flight.returnFlightNumber ?? t("Номер рейса уточняется", "Flight number to be confirmed", "Reys raqami tasdiqlanadi"),
                            date: returnDate,
                            returning: nil
                        )
                    }
                }
                if journey.stagedUmrahFlights.isEmpty {
                    if let flight = journey.selectedOutbound { flightCard(route: "\(flight.origin) → \(flight.destination)", carrier: flight.airline, number: flight.flightNumber, date: flight.departureAt.formatted(date: .abbreviated, time: .shortened), returning: nil) }
                    if let flight = journey.selectedInbound { flightCard(route: "\(flight.origin) → \(flight.destination)", carrier: flight.airline, number: flight.flightNumber, date: flight.departureAt.formatted(date: .abbreviated, time: .shortened), returning: nil) }
                }
            }

            summarySectionHeader(t("Гостиницы", "Hotels", "Mehmonxonalar"), icon: "building.2", stage: .hotels)
            IumrahConfiguratorStayCard(city: "makkah", stay: selectedStays["makkah"], fallback: journey.selectedHotel, lang: settings.language)
            IumrahConfiguratorStayCard(city: "madinah", stay: selectedStays["madinah"], fallback: journey.selectedMadinahHotel, lang: settings.language)

            summarySectionHeader(t("Услуги и сопровождение", "Services and assistance", "Xizmatlar va yordam"), icon: "checklist", stage: .guide)
            ForEach(IumrahDraftService.allCases) { service in
                serviceSummary(service)
            }
            supportSummary

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Итоговая стоимость", "Total package price", "Paket umumiy narxi")).font(.headline)
                Text(t("Расчёт будет подключён позже", "Price calculation is not connected yet", "Narx hisobi keyin ulanadi"))
                    .font(.title3.weight(.bold)).foregroundStyle(.secondary)
                Text(t("Все данные — предварительный план, не подтверждённая бронь. Никаких списаний и заявок не создаётся.", "This is a draft, not a confirmed booking. No payments or booking requests are submitted.", "Bu tasdiqlangan bron emas, dastlabki reja. To‘lov yoki buyurtma yaratilmaydi."))
                    .font(.caption).foregroundStyle(.secondary)
                Button {} label: {
                    Text(t("Забронировать умру · скоро", "Book Umrah · coming soon", "Umrani bron qilish · tez orada"))
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(.black).disabled(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 25))
        }
        .padding(.top, 16)
    }

    private func summarySectionHeader(_ title: String, icon: String, stage: HotelsShowcaseBoard) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer()
            Button { onSelectStage(stage) } label: {
                Label(t("Изменить", "Edit", "O‘zgartirish"), systemImage: "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }.tint(.black)
        }.padding(.top, 10)
    }

    private func emptySelection(_ text: String) -> some View {
        Label(text, systemImage: "plus.circle")
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .padding(.horizontal, 17)
            .background(.white, in: RoundedRectangle(cornerRadius: 23))
    }

    private func flightCard(route: String, carrier: String, number: String, date: String, returning: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("Перелёт", "Flight", "Parvoz"), systemImage: "airplane")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.black)
            }
            Text(route).font(.system(size: 23, weight: .bold, design: .rounded))
            Text("\(carrier) · \(number)").font(.subheadline)
            Label(date, systemImage: "calendar").font(.caption).foregroundStyle(.secondary)
            if let returning, !returning.isEmpty {
                Label(t("Обратный рейс: ", "Return: ", "Qaytish: ") + returning, systemImage: "arrow.uturn.backward")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private func serviceSummary(_ service: IumrahDraftService) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: service.symbol).font(.system(size: 21)).frame(width: 30)
                VStack(alignment: .leading, spacing: 5) {
                    Text(service.title(settings.language)).font(.headline)
                    Text(service.detail(settings.language)).font(.caption).foregroundStyle(.secondary)
                    if service == .transfer && draft.enabled(.transfer) {
                        Text(draft.vehicle == "private" ? t("Личный транспорт", "Private vehicle", "Shaxsiy transport") : t("Групповой транспорт", "Shared vehicle", "Guruhli transport"))
                            .font(.caption.weight(.semibold))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: draft.enabled(service) ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(draft.enabled(service) ? Color.black : Color.secondary)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var supportSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(t("Поддержка и связь", "Support & connectivity", "Yordam va aloqa"), systemImage: "message.circle")
                .font(.headline)
            Text(t("Поддержка iumrah — часть поездки. eSIM находится внутри этого раздела.", "iumrah support is part of the trip. eSIM belongs here, not in a separate step.", "iumrah yordami safarning bir qismi. eSIM shu bo‘limda."))
                .font(.subheadline).foregroundStyle(.secondary)
            Label(draft.includeESIM ? t("eSIM добавлена в черновик", "eSIM included in draft", "eSIM rejaga qo‘shildi") : t("eSIM не выбрана", "eSIM not selected", "eSIM tanlanmagan"), systemImage: "simcard")
                .font(.caption.weight(.medium))
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
}

private struct IumrahConfiguratorStayCard: View {
    let city: String
    let stay: NuiteeSelectedStay?
    let fallback: HotelSummary?
    let lang: AppSettingsStore.Language
    @State private var photoURL: String?
    private var name: String? { stay?.hotelName ?? fallback?.name }
    private var hotelID: String? { stay?.hotelId }
    private var cityTitle: String {
        city == "makkah" ? ConfiguratorCopy.text("Мекка", "Makkah", "Makka", lang) : ConfiguratorCopy.text("Медина", "Madinah", "Madina", lang)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let urlString = photoURL ?? fallback?.coverImageURL,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "building.2").resizable().scaledToFit().padding(29)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "building.2").resizable().scaledToFit().padding(29)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 114).background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            VStack(alignment: .leading, spacing: 7) {
                Text(cityTitle.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Text(name ?? ConfiguratorCopy.text("Отель не выбран", "No hotel selected", "Mehmonxona tanlanmagan", lang))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if let stay {
                    Label("\(stay.checkin) → \(stay.checkout)", systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(stay.roomName).font(.subheadline)
                    Text(stay.mealPlan).font(.caption).foregroundStyle(.secondary)
                    Text(stay.cancellationTag).font(.caption).foregroundStyle(.secondary)
                } else if let fallback, let stars = fallback.stars {
                    Text("\(stars) ★").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .task(id: hotelID) {
            guard let hotelID else { return }
            if let detail = try? await NuiteeHotelService().detail(hotelID: hotelID) {
                photoURL = detail.coverImageURL ?? detail.images.first
            }
        }
    }
}

/// One native-style cart surface across Flights, Hotels, Services and Summary.
/// It is a visual assembly indicator, not a checkout or a quotation.
struct IumrahConfiguratorCartBar: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject var draft: IumrahConfiguratorVisualDraft
    @ObservedObject var journey: JourneyStore
    let currentStage: HotelsShowcaseBoard
    let onOpenSummary: () -> Void

    private var hotelCount: Int {
        let stays = NuiteeStaySelectionStore.shared.selections()
        return (stays["makkah"] != nil || journey.selectedHotel != nil ? 1 : 0) + (stays["madinah"] != nil || journey.selectedMadinahHotel != nil ? 1 : 0)
    }
    private var flightCount: Int {
        if !journey.stagedUmrahFlights.isEmpty { return journey.stagedUmrahFlights.count }
        return (journey.selectedOutbound != nil ? 1 : 0) + (journey.selectedInbound != nil ? 1 : 0)
    }
    /// Keep the SwiftUI view builder small: precompute localized cart text.
    /// Large nested String concatenations previously made Xcode's type checker time out.
    private var cartSummaryText: String {
        let flights = String(flightCount)
        let hotels = String(hotelCount)
        let services = String(draft.selected.count + (draft.includeESIM ? 1 : 0) + 1)
        let flightTitle = ConfiguratorCopy.text("рейсов", "flights", "reys", settings.language)
        let hotelTitle = ConfiguratorCopy.text("отеля", "hotels", "mehmonxona", settings.language)
        let serviceTitle = ConfiguratorCopy.text("услуг", "services", "xizmat", settings.language)
        return "\(flights) \(flightTitle) · \(hotels) \(hotelTitle) · \(services) \(serviceTitle)"
    }

    var body: some View {
        Button(action: onOpenSummary) {
            HStack(spacing: 11) {
                Image(systemName: "bag.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 39, height: 39)
                    .background(.black, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(ConfiguratorCopy.text("Моя умра", "My Umrah", "Mening umram", settings.language))
                        .font(.subheadline.weight(.bold))
                    Text(cartSummaryText)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(["airplane", "building.2", "checkmark"], id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.75))
                            .frame(width: 23, height: 23)
                            .background(Color.black.opacity(0.055), in: Circle())
                    }
                }
                Image(systemName: currentStage == .summary ? "checkmark" : "chevron.up")
                    .font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).frame(height: 66)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 29))
            .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(Color.black.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ConfiguratorCopy.text("Открыть итог умры", "Open Umrah summary", "Umra yakunini ochish", settings.language))
    }
}
