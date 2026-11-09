import SwiftUI

// Shared source of truth for the home carousel and the service reference screen.
// Do not convert this to independent hard-coded card lists: card -> section deep links
// depend on these stable IDs.
enum IumrahServiceKind: String, CaseIterable, Identifiable {
    case visa, flights, hotels, transfer, guide, ziyarat, haramain, support, digital

    var id: String { rawValue }

    var imageName: String {
        switch self {
        case .visa: return "IumrahVisaServicesHero"
        case .flights: return "IumrahServicesFlightHero"
        case .hotels: return "MakkahBackground"
        case .transfer: return "TransferCarnival"
        case .guide: return "GiftCardJourney"
        case .ziyarat: return "ZiyaratQuba1"
        case .haramain: return "HaramainHero"
        case .support: return "ZiyaratQuba3"
        case .digital: return "IumrahESIMHomeCard"
        }
    }

    var icon: String {
        switch self {
        case .visa: return "doc.text"
        case .flights: return "airplane"
        case .hotels: return "bed.double"
        case .transfer: return "car.side"
        case .guide: return "person.2"
        case .ziyarat: return "map"
        case .haramain: return "tram"
        case .support: return "heart.text.square"
        case .digital: return "network"
        }
    }

    var isOptional: Bool { self == .haramain || self == .digital }
}

struct IumrahServiceContent {
    let name: String
    let category: String
    let short: String
    let detail: String
}

enum IumrahServicesCopy {
    static func text(_ ru: String, _ en: String, _ uz: String, _ cy: String, language: AppSettingsStore.Language) -> String {
        switch language {
        case .russian: return ru
        case .english, .turkish, .indonesian, .malay, .arabic: return en
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        }
    }

    static func sectionTitle(_ language: AppSettingsStore.Language) -> String {
        text("Сервисы iumrah", "iumrah Services", "iumrah servislar", "iumrah сервислари", language: language)
    }

    static func sectionSubtitle(_ language: AppSettingsStore.Language) -> String {
        text(
            "Всё необходимое для вашей умры собрано в одном пакете: виза, перелёт, отели, трансфер и сопровождение.",
            "Everything you need for Umrah in one package: visa, flights, hotels, transfers and personal assistance.",
            "Umra uchun kerakli barcha xizmatlar bitta paketda: viza, parvoz, mehmonxona, transfer va hamrohlik.",
            "Умра учун керакли барча хизматлар битта пакетда: виза, парвоз, меҳмонхона, трансфер ва ҳамроҳлик.",
            language: language
        )
    }

    static func pageSubtitle(_ language: AppSettingsStore.Language) -> String {
        text(
            "Всё, что мы организуем для вашей поездки. Откройте сервис, чтобы узнать подробности.",
            "Everything we organize for your journey. Tap a service to learn more.",
            "Safaringiz uchun tashkil qiladigan xizmatlarimiz. Batafsil ma’lumot uchun servisni oching.",
            "Сафарингиз учун ташкил қиладиган хизматларимиз. Батафсил маълумот учун сервисни очинг.",
            language: language
        )
    }

    static func seeAll(_ language: AppSettingsStore.Language) -> String {
        text("Все сервисы", "All services", "Barcha servislar", "Барча сервислар", language: language)
    }

    static func categoryStatus(_ kind: IumrahServiceKind, language: AppSettingsStore.Language) -> String {
        if kind.isOptional {
            return text("Зависит от пакета", "Depends on package", "Paketga bog‘liq", "Пакетга боғлиқ", language: language)
        }
        return text("Компонент поездки", "Journey component", "Safar xizmati", "Сафар хизмати", language: language)
    }

    static func content(_ kind: IumrahServiceKind, language: AppSettingsStore.Language) -> IumrahServiceContent {
        switch kind {
        case .visa:
            return localized(language,
                ru: ("Виза в Саудовскую Аравию", "Документы", "Туристическая виза для совершения умры.", "Помогаем подготовить документы и оформить туристическую визу для поездки в Саудовскую Аравию. Такая виза разрешает совершать умру в установленные властями периоды, но не хадж. Тип визы, даты и условия выдачи определяются Саудовской Аравией."),
                en: ("Saudi Arabia visa", "Documents", "A tourist visa that permits Umrah.", "We assist with preparing documents and applying for a tourist visa to Saudi Arabia. Umrah is permitted during authorized periods, but Hajj is not. Visa type, dates and issuance terms are determined by Saudi authorities."),
                uz: ("Saudiya Arabistoni vizasi", "Hujjatlar", "Umra qilishga ruxsat beruvchi turistik viza.", "Saudiya Arabistoniga sayohat uchun hujjatlarni tayyorlash va turistik viza rasmiylashtirishda yordam beramiz. Ushbu viza ruxsat etilgan davrlarda umra qilishga imkon beradi, haj uchun esa amal qilmaydi. Viza turi va shartlarini Saudiya Arabistoni belgilaydi."),
                cy: ("Саудия Арабистони визаси", "Ҳужжатлар", "Умра қилишга рухсат берувчи туристик виза.", "Саудия Арабистонига саёҳат учун ҳужжатларни тайёрлаш ва туристик виза расмийлаштиришда ёрдам берамиз. Ушбу виза рухсат этилган даврларда умра қилишга имкон беради, ҳаж учун эса амал қилмайди. Виза тури ва шартларини Саудия Арабистони белгилайди."))
        case .flights:
            return localized(language,
                ru: ("Авиабилеты", "Перелёт", "Прежде всего прямые рейсы туда и обратно.", "Подбираем билеты в Саудовскую Аравию и обратно с учётом города вылета, дат и состава семьи. В первую очередь предлагаем доступные прямые рейсы, чтобы сократить пересадки и время в пути. Если прямых рейсов нет, показываем подходящие альтернативы."),
                en: ("Flights", "Air travel", "Nonstop round-trip flights are our priority.", "We choose outbound and return flights based on your city, dates and family size. Available nonstop flights are prioritized to reduce connections and travel time. When nonstop service is unavailable, we present suitable alternatives."),
                uz: ("Aviachiptalar", "Parvoz", "Avvalo to‘g‘ridan-to‘g‘ri borish va qaytish reyslari.", "Jo‘nash shahri, sanalar va oila tarkibiga qarab borish hamda qaytish chiptalarini tanlaymiz. Vaqt va tranzitni kamaytirish uchun avvalo mavjud to‘g‘ridan-to‘g‘ri reyslarni tavsiya qilamiz."),
                cy: ("Авиачипталар", "Парвоз", "Аввало тўғридан-тўғри бориш ва қайтиш рейслари.", "Жўнаш шаҳри, саналар ва оила таркибига қараб бориш ҳамда қайтиш чипталарини танлаймиз. Вақт ва транзитни камайтириш учун аввало мавжуд тўғридан-тўғри рейсларни тавсия қиламиз."))
        case .hotels:
            return localized(language,
                ru: ("Отели", "Проживание", "Проживание в Мекке и Медине для вашей семьи.", "Подбираем отели в Мекке и Медине с учётом класса пакета, количества гостей, удобства размещения и расстояния до мечети. Даты, тип номера и питание показываются в вашей конфигурации поездки."),
                en: ("Hotels", "Accommodation", "Stays in Makkah and Madinah for your family.", "We select hotels in Makkah and Madinah according to package tier, family size, room comfort and location. Your chosen itinerary shows dates, room type and meal terms."),
                uz: ("Mehmonxonalar", "Turar joy", "Makka va Madinada oilangiz uchun qulay yashash.", "Makka va Madinada paket darajasi, mehmonlar soni, xona qulayligi va masjidgacha masofani hisobga olib mehmonxona tanlaymiz. Sanalar va xona turi safar rejangizda ko‘rsatiladi."),
                cy: ("Меҳмонхоналар", "Турар жой", "Макка ва Мадинада оилангиз учун қулай яшаш.", "Макка ва Мадинада пакет даражаси, меҳмонлар сони, хона қулайлиги ва масжидгача масофани ҳисобга олиб меҳмонхона танлаймиз. Саналар ва хона тури сафар режангизда кўрсатилади."))
        case .transfer:
            return localized(language,
                ru: ("Трансфер", "Транспорт", "Встреча в аэропорту и переезды по маршруту.", "Организуем предусмотренные пакетом поездки из аэропорта, между отелями и важными точками маршрута. Подбираем автомобиль под количество пассажиров и багажа. Конкретный транспорт отражается в подтверждённой поездке."),
                en: ("Transfers", "Transport", "Airport pickup and planned transfers.", "We organize the transfers included in your itinerary between airports, hotels and key stops. The vehicle is chosen for passenger and luggage capacity, with details shown in the confirmed booking."),
                uz: ("Transfer", "Transport", "Aeroportda kutib olish va yo‘nalish bo‘yicha safarlar.", "Paketga kiritilgan aeroport, mehmonxona va muhim manzillar orasidagi safarlarni tashkil qilamiz. Avtomobil yo‘lovchilar va yuk soniga mos tanlanadi."),
                cy: ("Трансфер", "Транспорт", "Аэропортда кутиб олиш ва йўналиш бўйича сафарлар.", "Пакетга киритилган аэропорт, меҳмонхона ва муҳим манзиллар орасидаги сафарларни ташкил қиламиз. Автомобиль йўловчилар ва юк сонига мос танланади."))
        case .guide:
            return localized(language,
                ru: ("Личный гид", "Сопровождение", "Помощь вашей семье на протяжении поездки.", "Ваша семья путешествует своим составом, без обязательной большой туристической группы. Гид встречает по договорённости, помогает ориентироваться в Саудовской Аравии, сопровождает предусмотренные программой посещения и объясняет этапы умры."),
                en: ("Personal guide", "Assistance", "Personal support for your family during the trip.", "Your family travels privately rather than with a mandatory large tour group. A guide assists with arrival, orientation, scheduled visits and understanding the steps of Umrah."),
                uz: ("Shaxsiy gid", "Hamrohlik", "Safar davomida oilangizga shaxsiy yordam.", "Oilangiz katta majburiy turistik guruhsiz sayohat qiladi. Gid kutib olish, manzillarni topish, dasturdagi ziyoratlar va umra bosqichlarida yordam beradi."),
                cy: ("Шахсий гид", "Ҳамроҳлик", "Сафар давомида оилангизга шахсий ёрдам.", "Оилангиз катта мажбурий туристик гуруҳсиз саёҳат қилади. Гид кутиб олиш, манзилларни топиш, дастурдаги зиёратлар ва умра босқичларида ёрдам беради."))
        case .ziyarat:
            return localized(language,
                ru: ("Зияраты", "Маршруты", "Священные и исторические места Мекки и Медины.", "Посещайте значимые места Мекки и Медины в понятной последовательности. В рамках запланированных зияратов вы узнаете об истории этих мест и получите помощь гида с организацией и маршрутом."),
                en: ("Ziyarats", "Routes", "Important sites in Makkah and Madinah.", "Visit historic and sacred places in a clear, organized order. When ziyarats are part of your itinerary, the guide helps you navigate the route and understand each location."),
                uz: ("Ziyoratlar", "Yo‘nalishlar", "Makka va Madinadagi muqaddas va tarixiy joylar.", "Muhim joylarni qulay tartibda ziyorat qiling. Dasturga kiritilgan ziyoratlarda gid joylar tarixi va yo‘nalish bo‘yicha yordam beradi."),
                cy: ("Зиёратлар", "Йўналишлар", "Макка ва Мадинадаги муқаддас ва тарихий жойлар.", "Муҳим жойларни қулай тартибда зиёрат қилинг. Дастурга киритилган зиёратларда гид жойлар тарихи ва йўналиш бўйича ёрдам беради."))
        case .haramain:
            return localized(language,
                ru: ("Haramain Train", "Поезд", "Скоростной поезд, если он выбран для маршрута.", "Скоростная железная дорога Haramain соединяет ключевые города и транспортные узлы региона. Поезд можно использовать для переезда между Меккой, Джиддой и Мединой, когда это подходит вашей программе. Билет включён только при выборе этого варианта."),
                en: ("Haramain Train", "Rail", "High-speed rail when selected for your itinerary.", "Haramain high-speed rail links major cities and transport hubs in the region. It may be used for journeys among Makkah, Jeddah and Madinah. A train ticket is included only when selected in your package."),
                uz: ("Haramain poyezdi", "Poyezd", "Yo‘nalishingizda tanlangan bo‘lsa, tezyurar poyezd.", "Haramain tezyurar temiryo‘li Makka, Jidda va Madinani bog‘laydi. Poyezd chiptasi faqat ushbu variant paketga qo‘shilgan bo‘lsa kiritiladi."),
                cy: ("Haramain поезди", "Поезд", "Йўналишингизда танланган бўлса, тезюрар поезд.", "Haramain тезюрар темирйўли Макка, Жидда ва Мадинани боғлайди. Поезд чиптаси фақат ушбу вариант пакетга қўшилган бўлса киритилади."))
        case .support:
            return localized(language,
                ru: ("Поддержка iumrah", "Помощь", "Организационные вопросы — с нами.", "Помогаем разобраться с деталями поездки до вылета и во время пребывания в Саудовской Аравии: вопросы по бронированию, документам, времени встреч и предоставленным услугам. Каналы связи доступны внутри приложения."),
                en: ("iumrah Support", "Assistance", "Help with practical questions throughout your journey.", "We help with booking details, documents, meeting times and arranged services before departure and during your stay in Saudi Arabia. Contact channels are available in the app."),
                uz: ("iumrah yordami", "Yordam", "Safarga oid tashkiliy savollarda ko‘mak.", "Jo‘nashdan oldin va Saudiya Arabistonida bo‘lgan vaqtingizda bron, hujjatlar, uchrashuv va xizmatlar bo‘yicha savollaringizga yordam beramiz."),
                cy: ("iumrah ёрдами", "Ёрдам", "Сафарга оид ташкилий саволларда кўмак.", "Жўнашдан олдин ва Саудия Арабистонида бўлган вақтингизда брон, ҳужжатлар, учрашув ва хизматлар бўйича саволларингизга ёрдам берамиз."))
        case .digital:
            return localized(language,
                ru: ("Цифровые сервисы", "В приложении", "Маршруты, информация и мобильная связь.", "В приложении доступны iumrah Ziyarat с маршрутами и информацией о местах, отслеживание рейсов и инструменты помощи путешественнику. eSIM и другие дополнительные продукты подключаются по доступности и условиям выбранного пакета."),
                en: ("Digital services", "In the app", "Routes, travel details and connectivity.", "The app offers iumrah Ziyarat maps and place information, flight tracking and traveler tools. eSIM and other optional products depend on availability and the package you select."),
                uz: ("Raqamli servislar", "Ilovada", "Yo‘nalishlar, ma’lumot va mobil aloqa.", "Ilovada iumrah Ziyarat yo‘nalishlari, parvoz kuzatuvi va sayohat uchun foydali vositalar mavjud. eSIM va boshqa qo‘shimcha mahsulotlar tanlangan paket shartlariga bog‘liq."),
                cy: ("Рақамли сервислар", "Иловада", "Йўналишлар, маълумот ва мобил алоқа.", "Иловада iumrah Ziyarat йўналишлари, парвоз кузатуви ва саёҳат учун фойдали воситалар мавжуд. eSIM ва бошқа қўшимча маҳсулотлар танланган пакет шартларига боғлиқ."))
        }
    }

    private static func localized(
        _ language: AppSettingsStore.Language,
        ru: (String, String, String, String),
        en: (String, String, String, String),
        uz: (String, String, String, String),
        cy: (String, String, String, String)
    ) -> IumrahServiceContent {
        let values: (String, String, String, String)
        switch language {
        case .russian: values = ru
        case .english, .turkish, .indonesian, .malay, .arabic: values = en
        case .uzbek: values = uz
        case .uzbekCyrillic: values = cy
        }
        return IumrahServiceContent(name: values.0, category: values.1, short: values.2, detail: values.3)
    }
}

private struct IumrahServicesPhoto: View {
    let kind: IumrahServiceKind
    var body: some View {
        GeometryReader { geo in
            Image(kind.imageName)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .accessibilityHidden(true)
        }
    }
}

struct IumrahServicesCarouselCard: View {
    let kind: IumrahServiceKind
    let language: AppSettingsStore.Language

    private var content: IumrahServiceContent { IumrahServicesCopy.content(kind, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IumrahServicesPhoto(kind: kind)
                .frame(height: 164)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(content.category)
                        .font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.black.opacity(0.50))

                Text(content.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .tracking(-0.45)
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(content.short)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.black.opacity(0.60))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct IumrahServicesView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var expanded: IumrahServiceKind?
    private let initialService: IumrahServiceKind

    init(initialService: IumrahServiceKind = .visa) {
        self.initialService = initialService
        _expanded = State(initialValue: initialService)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(IumrahServicesCopy.sectionTitle(settings.language))
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.7)
                            .foregroundStyle(.primary)
                        Text(IumrahServicesCopy.pageSubtitle(settings.language))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                    ForEach(IumrahServiceKind.allCases) { service in
                        serviceSection(service)
                            .id(service)
                    }
                }
                .padding(.horizontal, IumrahDesign.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.iumrahPageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Wait for the first layout pass: deep link must land on the selected
                // section, including when the entry point is the last carousel card.
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(initialService, anchor: .top)
                }
            }
        }
    }

    private func serviceSection(_ kind: IumrahServiceKind) -> some View {
        let content = IumrahServicesCopy.content(kind, language: settings.language)
        let isExpanded = expanded == kind

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                IumrahHaptics.selection()
                withAnimation(.smooth(duration: 0.32)) {
                    expanded = isExpanded ? nil : kind
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: kind.icon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 37, height: 37)
                        .background(Color.iumrahPageBackground, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(content.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(content.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 3)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(content.name)
            .accessibilityHint(isExpanded
                ? IumrahServicesCopy.text("Свернуть описание", "Collapse details", "Tafsilotni yopish", "Тафсилотни ёпиш", language: settings.language)
                : IumrahServicesCopy.text("Развернуть описание", "Expand details", "Tafsilotni ochish", "Тафсилотни очиш", language: settings.language))

            if isExpanded {
                VStack(alignment: .leading, spacing: 14) {
                    IumrahServicesPhoto(kind: kind)
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Text(content.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if kind == .visa { visaInformation }

                    Label(IumrahServicesCopy.categoryStatus(kind, language: settings.language), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.75)
        }
    }

    private var visaInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                visaType(
                    title: IumrahServicesCopy.text("Однократная", "Single entry", "Bir martalik", "Бир марталик", language: settings.language),
                    duration: IumrahServicesCopy.text("90 дней", "90 days", "90 kun", "90 кун", language: settings.language)
                )
                visaType(
                    title: IumrahServicesCopy.text("Многократная", "Multiple entry", "Ko‘p martalik", "Кўп марталик", language: settings.language),
                    duration: IumrahServicesCopy.text("1 год", "1 year", "1 yil", "1 йил", language: settings.language)
                )
            }

            Text(IumrahServicesCopy.text(
                "Это сроки действия визы. Разрешённое пребывание — до 90 дней согласно условиям выданной визы. Однократная виза допускает один въезд, многократная — несколько въездов в течение срока её действия.",
                "These are visa validity periods. Permitted stay is up to 90 days according to the issued visa. A single-entry visa permits one entry, while a multiple-entry visa permits repeated entries during its validity.",
                "Bu vizalarning amal qilish muddati. Ruxsat etilgan qolish muddati berilgan viza shartlariga ko‘ra 90 kungacha. Bir martalik viza bitta, ko‘p martalik viza esa bir necha kirishga ruxsat beradi.",
                "Бу визаларнинг амал қилиш муддати. Рухсат этилган қолиш муддати берилган виза шартларига кўра 90 кунгача. Бир марталик виза битта, кўп марталик виза эса бир неча киришга рухсат беради.",
                language: settings.language
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Text(IumrahServicesCopy.text(
                "Выбор типа визы не всегда доступен. Выдачу, условия въезда и сезонные ограничения (включая период хаджа) устанавливают власти Саудовской Аравии. iumrah не гарантирует выдачу визы.",
                "Visa type may not be selectable. Saudi authorities determine approval, entry conditions and seasonal restrictions, including Hajj. iumrah cannot guarantee visa issuance.",
                "Viza turini har doim tanlab bo‘lmaydi. Berish, kirish shartlari va haj davridagi cheklovlarni Saudiya Arabistoni belgilaydi. iumrah viza berilishini kafolatlamaydi.",
                "Виза турини ҳар доим танлаб бўлмайди. Бериш, кириш шартлари ва ҳаж давридаги чекловларни Саудия Арабистони белгилайди. iumrah виза берилишини кафолатламайди.",
                language: settings.language
            ))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let url = URL(string: "https://ksavisa.sa/visa/tourism/details") {
                Link(destination: url) {
                    HStack(spacing: 7) {
                        Text(IumrahServicesCopy.text("Официальные условия KSA Visa", "Official KSA Visa terms", "KSA Visa rasmiy shartlari", "KSA Visa расмий шартлари", language: settings.language))
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private func visaType(title: String, duration: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(duration)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(IumrahServicesCopy.text("Срок действия", "Visa validity", "Amal qilish muddati", "Амал қилиш муддати", language: settings.language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(11)
        .background(Color.iumrahPageBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
