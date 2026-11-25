import SwiftUI
import AVKit

/// Discovery and final review share the same live public team catalogue.
/// A selection is a request, never a reservation or a second billable service.
struct IumrahManualGuideCatalog: View {
    @EnvironmentObject private var manual: IumrahManualJourneyStore
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var expanded = false
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            IumrahGraphiteSearchSurface(isExpanded: $expanded, summary: t("Ваш персональный гид", "Your personal guide", "Shaxsiy gidingiz", "Шахсий гидингиз"), subtitle: manual.plannedTrip.hotelStayStartDate.formatted(date: .abbreviated, time: .omitted) + " — " + manual.plannedTrip.returnDate.formatted(date: .abbreviated, time: .omitted)) {
                VStack(alignment: .leading, spacing: 14) {
                    IumrahManualScopePicker()
                    DatePicker(t("Начало поездки", "Trip start", "Safar boshlanishi", "Сафар бошланиши"), selection: $manual.plannedDeparture, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date).disabled(manual.outbound != nil)
                    DatePicker(t("Окончание поездки", "Trip end", "Safar tugashi", "Сафар тугаши"), selection: $manual.plannedReturn, in: min(manual.plannedDeparture, manual.plannedReturn)..., displayedComponents: .date).disabled(manual.inbound != nil)
                    Stepper(t("Взрослых", "Adults", "Kattalar", "Катталар") + ": \(manual.adults)", value: $manual.adults, in: 1...6)
                    Button(t("Применить", "Apply", "Qo‘llash", "Қўллаш")) { manual.routeConfigured = true; withAnimation { expanded = false } }.buttonStyle(IumrahPrimaryButtonStyle())
                }.tint(.primary)
            }.padding(.top, -40)
            IumrahGuideCatalog(trip: manual.plannedTrip, preference: manual.guidePreference, priceText: nil, includeTeam: true) { preference in
                manual.guidePreference = preference
                chrome.openHotels(board: .summary)
            }
        }.padding(.horizontal, IumrahDesign.pagePadding)
        .onChange(of: manual.plannedDeparture) { _, date in
            if manual.plannedReturn <= date && manual.inbound == nil { manual.plannedReturn = Calendar.current.date(byAdding: .day, value: 7, to: date) ?? date }
        }
    }
}

struct IumrahGuideCatalog: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let trip: TripDraft
    let preference: IumrahGuidePreference?
    let priceText: String?
    var includeTeam = false
    let onSelect: (IumrahGuidePreference?) -> Void
    @EnvironmentObject private var chrome: AppChromeStore
    @State private var guides: [IumrahPublicProfile] = []
    @State private var team: [IumrahPublicProfile] = []
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0
    @State private var opened: IumrahPublicProfile?
    @State private var search = ""
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    private var dateKey: String { IumrahGuideDates.day(trip.hotelStayStartDate) + "|" + IumrahGuideDates.day(trip.returnDate) + "|\(revision)" }
    private var visibleGuides: [IumrahPublicProfile] {
        let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? guides : guides.filter { [$0.displayName, $0.localizedBio(settings.language), $0.roleTitle].joined(separator: " ").localizedCaseInsensitiveContains(value) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            VStack(alignment: .leading, spacing: 6) {
                Text(t("Выберите своего гида", "Choose your guide", "Gidingizni tanlang", "Гидингизни танланг")).font(.system(.title, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
                Text(t("Познакомьтесь с командой до вылета. Один гид для вашей семьи.", "Meet the team before departure. One guide for your family.", "Parvozdan oldin jamoa bilan tanishing. Oilangiz uchun bitta gid.", "Парвоздан олдин жамоа билан танишинг. Оилангиз учун битта гид.")).font(.subheadline).foregroundStyle(.secondary)
            }
            if loading { HStack { Spacer(); ProgressView(); Spacer() }.padding(24) }
            if failed {
                VStack(alignment: .leading, spacing: 10) {
                    Label(t("Не удалось загрузить гидов", "Could not load guides", "Gidlar yuklanmadi", "Гидлар юкланмади"), systemImage: "wifi.exclamationmark").font(.headline)
                    Text(t("Проверьте соединение и повторите попытку.", "Check your connection and try again.", "Internetni tekshirib, qayta urinib ko‘ring.", "Интернетни текшириб, қайта уриниб кўринг.")).font(.footnote).foregroundStyle(.secondary)
                    Button(t("Повторить", "Retry", "Qayta urinish", "Қайта уриниш")) { revision += 1 }.buttonStyle(IumrahSecondaryButtonStyle())
                }.guideSurface()
            } else if !loading && guides.isEmpty {
                ContentUnavailableView(t("Нет опубликованных гидов", "No published guides", "E’lon qilingan gidlar yo‘q", "Эълон қилинган гидлар йўқ"), systemImage: "person.crop.circle.badge.questionmark")
            } else if !loading {
                if guides.count > 3 { TextField(t("Имя или описание", "Name or description", "Ism yoki tavsif", "Исм ёки тавсиф"), text: $search).textFieldStyle(.roundedBorder) }
                if visibleGuides.isEmpty { Text(t("Ничего не найдено", "No matches", "Hech narsa topilmadi", "Ҳеч нарса топилмади")).foregroundStyle(.secondary) }
                ForEach(visibleGuides, id: \.id) { guide in
                    IumrahGuideProfileCard(guide: guide, trip: trip, selected: preference?.memberID == guide.id, priceText: priceText, onDetails: { opened = guide }, onSelect: { choose(guide) })
                }
            }
            autoChoice
            if includeTeam && !team.isEmpty {
                ForEach(team.filter { $0.isOwner }) { member in
                    Text(t("Основатель проекта", "Founder", "Loyiha asoschisi", "Лойиҳа асосчиси")).font(.system(.title2, design: .rounded, weight: .bold))
                    IumrahTeamDirectoryCard(member: member) { chrome.navigate(to: .care) }
                }
                let staff = team.filter { !$0.isOwner }
                if !staff.isEmpty {
                    Text(t("Команда iumrah", "iumrah team", "iumrah jamoasi", "iumrah жамоаси")).font(.system(.title2, design: .rounded, weight: .bold))
                    ForEach(staff) { member in IumrahTeamDirectoryCard(member: member) { chrome.navigate(to: .care) } }
                }
                Label(t("Личные контакты назначенного гида доступны после подтверждения оплаты.", "Assigned guide contacts are available after payment confirmation.", "Biriktirilgan gid kontaktlari to‘lov tasdiqlangach ochiladi.", "Бириктирилган гид контактлари тўлов тасдиқлангач очилади."), systemImage: "lock.shield").font(.footnote).foregroundStyle(.secondary).guideSurface()
            }
            IumrahGuideProgram(trip: trip)
            costCard
            brandClosing
        }
        .task(id: dateKey) { await load() }
        .refreshable { revision += 1 }
        .sheet(item: $opened) { guide in
            IumrahGuideProfileSheet(guide: guide, trip: trip, selected: preference?.memberID == guide.id, priceText: priceText) {
                opened = nil
                choose(guide)
            }.environmentObject(settings)
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("AboutIumrahKaabaCorner").resizable().scaledToFill().frame(height: 210).frame(maxWidth: .infinity).clipped().accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 15) {
                Text("IUMRAH  ·  PERSONAL GUIDE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.64))
                Text(t("Ваша умра.\nВаш персональный гид.", "Your Umrah.\nYour personal guide.", "Umrangiz.\nShaxsiy gidingiz.", "Умрангиз.\nШахсий гидингиз.")).font(.system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(t("От встречи в аэропорту до завершения путешествия. Больше времени для поклонения и близких.", "From the airport welcome to the end of your journey. More time for worship and loved ones.", "Aeroportdagi uchrashuvdan safar yakunigacha. Ibodat va yaqinlaringiz uchun ko‘proq vaqt.", "Аэропортдаги учрашувдан сафар якунигача. Ибодат ва яқинларингиз учун кўпроқ вақт.")).font(.subheadline).foregroundStyle(.white.opacity(0.76))
                Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
                    heroFact("person.2", t("Один гид на семью", "One guide per family", "Oilaga bitta gid", "Оилага битта гид"))
                    heroFact("airplane.arrival", t("Встреча в аэропорту", "Airport welcome", "Aeroportda kutib olish", "Аэропортда кутиб олиш"))
                    heroFact("book", t("Обучение умре", "Umrah preparation", "Umraga tayyorgarlik", "Умрага тайёргарлик"))
                    heroFact("heart", t("Личная забота", "Personal care", "Shaxsiy g‘amxo‘rlik", "Шахсий ғамхўрлик"))
                }
            }.padding(23).foregroundStyle(.white)
        }.background(Color(white: 0.075), in: RoundedRectangle(cornerRadius: 30)).clipShape(RoundedRectangle(cornerRadius: 30))
    }
    private func heroFact(_ symbol: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Image(systemName: symbol).font(.title2.weight(.medium)); Text(title).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
    }
    private var autoChoice: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.badge.gearshape").font(.title2).frame(width: 54, height: 54).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Доверить выбор iumrah", "Let iumrah choose", "Tanlovni iumrahga topshiring", "Танловни iumrahга топширинг")).font(.headline)
                    Text(t("Подберём гида с учётом вашей поездки.", "We will match a guide to your trip.", "Safaringizga mos gid tanlaymiz.", "Сафарингизга мос гид танлаймиз.")).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if preference == nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.primary) }
            }
            Button(t("Доверить подбор", "Let iumrah select", "Tanlovni topshirish", "Танловни топшириш")) { IumrahHaptics.selection(); onSelect(nil) }.buttonStyle(IumrahSecondaryButtonStyle())
        }.guideSurface()
    }
    private var costCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(t("Прозрачная стоимость", "Transparent pricing", "Shaffof narx", "Шаффоф нарх"), systemImage: "checkmark.shield").font(.title3.bold())
            if let priceText, priceText != "—" { Text(priceText).font(.largeTitle.bold().monospacedDigit()) }
            Text(t("Стоимость персонального сопровождения учитывается в общей цене пакета. Выбор конкретного гида не добавляет вторую оплату.", "Personal accompaniment is included in the package total. Selecting a particular guide does not add a second charge.", "Shaxsiy hamrohlik paket narxiga kiradi. Muayyan gidni tanlash ikki marta to‘lov qilmaydi.", "Шахсий ҳамроҳлик пакет нархига киради. Муайян гидни танлаш икки марта тўлов қилмайди.")).font(.subheadline)
            Divider()
            Text(t("Дополнительные поездки, транспорт и расходы вне программы согласовываются отдельно. Доступность гида подтверждает команда iumrah.", "Extra trips, transport and out-of-program expenses are arranged separately. The iumrah team confirms guide availability.", "Qo‘shimcha safarlar, transport va dasturdan tashqari xarajatlar alohida kelishiladi. Gid mavjudligini iumrah tasdiqlaydi.", "Қўшимча сафарлар, транспорт ва дастурдан ташқари харажатлар алоҳида келишилади. Гид мавжудлигини iumrah тасдиқлайди.")).font(.footnote).foregroundStyle(.secondary)
        }.guideSurface()
    }
    private var brandClosing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE IUMRAH EXPERIENCE").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.white.opacity(0.6))
            Text(t("Одна семья. Один персональный гид.", "One family. One personal guide.", "Bir oila. Bir shaxsiy gid.", "Бир оила. Бир шахсий гид.")).font(.system(.title, design: .rounded, weight: .bold))
            Text(t("Путешествуйте самостоятельно, но не в одиночку.", "Travel independently, but not alone.", "Mustaqil sayohat qiling, ammo yolg‘iz emas.", "Мустақил саёҳат қилинг, аммо ёлғиз эмас.")).foregroundStyle(.white.opacity(0.75))
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            Text(t("Ближе к своим близким. Ближе к поклонению.", "Closer to loved ones. Closer to worship.", "Yaqinlaringizga yaqinroq. Ibodatga yaqinroq.", "Яқинларингизга яқинроқ. Ибодатга яқинроқ.")).font(.footnote.weight(.semibold))
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(Color.black, in: RoundedRectangle(cornerRadius: 30))
    }
    private func choose(_ guide: IumrahPublicProfile) {
        guard !loading, !failed, guides.contains(where: { $0.id == guide.id && $0.guideAvailable == true }) else { return }
        IumrahHaptics.selection(); onSelect(.init(memberID: guide.id, displayName: guide.displayName))
    }
    @MainActor private func load() async {
        loading = true; failed = false; guides = []; team = []
        do {
            let value = try await ChatService().loadGuideProfiles(start: trip.hotelStayStartDate, end: trip.returnDate, includeTeam: includeTeam)
            guard !Task.isCancelled else { return }
            guides = value.filter { !$0.isOwner && $0.roleKind == "guide" }; team = value.filter { $0.isOwner || $0.roleKind != "guide" }; loading = false
        } catch {
            guard !Task.isCancelled else { return }
            failed = true; loading = false
        }
    }
}

private struct IumrahTeamDirectoryCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let member: IumrahPublicProfile
    let onConsult: () -> Void
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    private func title(_ role: String) -> String {
        switch role {
        case "owner", "founder": return t("Основатель iumrah", "Founder", "iumrah asoschisi", "iumrah асосчиси")
        case "admin": return t("Администратор", "Administrator", "Administrator", "Администратор")
        case "support": return t("Специалист поддержки", "Care specialist", "Yordam mutaxassisi", "Ёрдам мутахассиси")
        case "manager": return t("Менеджер путешествий", "Travel manager", "Safar menejeri", "Сафар менежери")
        case "transfer": return t("Координатор трансфера", "Transfer coordinator", "Transfer koordinatori", "Трансфер координатори")
        case "guide": return t("Персональный гид", "Personal guide", "Shaxsiy gid", "Шахсий гид")
        default: return t("Организация поездок", "Operations", "Safarni tashkil etish", "Сафарни ташкил этиш")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IumrahGuidePortrait(guide: member, height: member.isOwner ? 300 : 220)
            Text(member.isOwner ? "FOUNDER OF IUMRAH" : "IUMRAH TEAM").font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            Text(member.displayName).font(.system(.title, design: .rounded, weight: .bold))
            Text((member.publicRoles ?? [member.isOwner ? "founder" : member.roleKind]).map(title).joined(separator: " · ")).font(.subheadline.weight(.semibold))
            let description = member.localizedBio(settings.language)
            if !description.isEmpty { Text(description).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            Divider()
            Button(t("Проконсультироваться через iumrah Care", "Consult through iumrah Care", "iumrah Care orqali maslahat olish", "iumrah Care орқали маслаҳат олиш"), action: onConsult).buttonStyle(IumrahSecondaryButtonStyle())
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(member.isOwner ? Color(white: 0.08) : Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28))
            .environment(\.colorScheme, member.isOwner ? .dark : colorScheme)
    }
}

private struct IumrahGuideProfileCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let guide: IumrahPublicProfile
    let trip: TripDraft
    let selected: Bool
    let priceText: String?
    let onDetails: () -> Void
    let onSelect: () -> Void
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onDetails) { IumrahGuidePortrait(guide: guide, height: 260) }.buttonStyle(.plain)
            IumrahGuideIdentity(guide: guide)
            if !guide.localizedBio(settings.language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(guide.localizedBio(settings.language)).font(.subheadline).foregroundStyle(.secondary).lineLimit(3) }
            Divider()
            Label(t("Индивидуальное сопровождение семьи", "Private family accompaniment", "Oilaga shaxsiy hamrohlik", "Оилага шахсий ҳамроҳлик"), systemImage: "person.2").font(.subheadline)
            Label(trip.scope.title(settings.language), systemImage: "mappin.and.ellipse").font(.subheadline)
            IumrahGuideAvailability(guide: guide)
            if let priceText, priceText != "—" { HStack { Text(t("Сопровождение в пакете", "Accompaniment in package", "Paketdagi hamrohlik", "Пакетдаги ҳамроҳлик")).font(.footnote).foregroundStyle(.secondary); Spacer(); Text(priceText).font(.headline.monospacedDigit()) } }
            Button(t("Подробнее", "View profile", "Batafsil", "Батафсил"), action: onDetails).buttonStyle(IumrahSecondaryButtonStyle())
            Button(selected ? t("✓ Выбран", "✓ Selected", "✓ Tanlangan", "✓ Танланган") : t("Выбрать гида", "Choose guide", "Gid tanlash", "Гид танлаш"), action: onSelect).buttonStyle(IumrahPrimaryButtonStyle()).disabled(guide.guideAvailable != true)
        }.guideSurface()
    }
}

private struct IumrahGuidePortrait: View {
    let guide: IumrahPublicProfile
    let height: CGFloat
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            HotelCachedImage(rawURL: guide.photoURL, placeholderSystemName: "person.crop.circle", thumbnailPixelDimension: 1100).frame(height: height)
            if guide.photoURL == nil {
                Text(String(guide.displayName.prefix(1)).uppercased()).font(.system(size: 100, weight: .bold, design: .rounded)).foregroundStyle(.secondary.opacity(0.15)).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(guide.roleKind == "guide" && !guide.isOwner ? "iumrah · GUIDE" : "iumrah · TEAM").font(.caption2.bold()).tracking(1.2).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7).background(Color.black.opacity(0.72), in: Capsule()).padding(12)
        }.frame(height: height).clipShape(RoundedRectangle(cornerRadius: 24)).accessibilityLabel(guide.displayName)
    }
}

private struct IumrahGuideIdentity: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let guide: IumrahPublicProfile
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(guide.displayName).font(.system(.title, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).accessibilityLabel(t("Профиль команды iumrah", "iumrah team profile", "iumrah jamoasi profili", "iumrah жамоаси профили"))
            }
            Text(guide.isHeadGuide == true ? t("Главный гид iumrah", "Head guide", "iumrah bosh gidi", "iumrah бош гиди") : t("Персональный гид iumrah", "Personal guide", "iumrah shaxsiy gidi", "iumrah шахсий гиди")).font(.subheadline).foregroundStyle(.secondary)
            if let years = guide.experienceYears, years > 0 { Label(t("Опыт: \(years) г.", "Experience: \(years) years", "Tajriba: \(years) yil", "Тажриба: \(years) йил"), systemImage: "clock").font(.footnote) }
            if let languages = guide.languages, !languages.isEmpty { Label(languages.joined(separator: " · "), systemImage: "globe").font(.footnote) }
        }
    }
}

private struct IumrahGuideAvailability: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let guide: IumrahPublicProfile
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        let status = guide.availabilityStatus
        let label = status == "unavailable" ? t("Временно недоступен", "Temporarily unavailable", "Vaqtincha mavjud emas", "Вақтинча мавжуд эмас") : status == "busy" ? t("Занят", "Busy", "Band", "Банд") : guide.guideAvailable == false ? t("Занят на выбранные даты", "Busy on selected dates", "Tanlangan sanalarda band", "Танланган саналарда банд") : guide.guideAvailable == true ? t("Доступен для заявок · требуется подтверждение", "Available for requests · confirmation required", "So‘rov uchun ochiq · tasdiqlash kerak", "Сўров учун очиқ · тасдиқлаш керак") : t("Доступность уточняется", "Availability to be confirmed", "Mavjudlik aniqlanadi", "Мавжудлик аниқланади")
        Label(label, systemImage: guide.guideAvailable == true ? "calendar.badge.clock" : "calendar.badge.exclamationmark")
            .font(.footnote.weight(.medium)).foregroundStyle(guide.guideAvailable == true ? Color.green : Color.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct IumrahGuideProfileSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    let guide: IumrahPublicProfile
    let trip: TripDraft
    let selected: Bool
    let priceText: String?
    let onSelect: () -> Void
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    IumrahGuidePortrait(guide: guide, height: 360)
                    VStack(alignment: .leading, spacing: 14) {
                        IumrahGuideIdentity(guide: guide)
                        IumrahGuideAvailability(guide: guide)
                        if !guide.localizedBio(settings.language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Divider(); Text(t("О гиде", "About the guide", "Gid haqida", "Гид ҳақида")).font(.headline); Text(guide.localizedBio(settings.language)).font(.body).fixedSize(horizontal: false, vertical: true)
                        }
                        if let url = AppConfig.absoluteURL(guide.introVideoURL), url.scheme == "https" {
                            Divider(); Text(t("Знакомство с гидом", "Meet your guide", "Gid bilan tanishuv", "Гид билан танишув")).font(.headline)
                            IumrahGuideIntroVideo(url: url).frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    }.guideSurface()
                    IumrahGuideProgram(trip: trip)
                    if let reviews = guide.guideReviews, !reviews.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(t("Отзывы паломников", "Pilgrim reviews", "Ziyoratchilar fikri", "Зиёратчилар фикри")).font(.title3.bold())
                            ForEach(reviews, id: \.id) { review in VStack(alignment: .leading, spacing: 5) { Text(review.author).font(.headline); Text(review.text).font(.subheadline) }; Divider() }
                        }.guideSurface()
                    }
                    Text(t("Конкретное назначение подтвердит команда iumrah после проверки дат. Дополнительные расходы согласовываются заранее.", "The iumrah team confirms assignment after checking dates. Additional expenses are agreed in advance.", "Gid sanalar tekshirilgach tasdiqlanadi. Qo‘shimcha xarajatlar oldindan kelishiladi.", "Гид саналар текширилгач тасдиқланади. Қўшимча харажатлар олдиндан келишилади.")).font(.footnote).foregroundStyle(.secondary)
                }.padding(18)
            }.background(Color.iumrahPageBackground)
            .navigationTitle(t("Профиль гида", "Guide profile", "Gid profili", "Гид профили")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Закрыть", "Close", "Yopish", "Ёпиш")) { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 7) {
                    if let priceText, priceText != "—" { Text(priceText + " · " + t("в пакете", "in package", "paketda", "пакетда")).font(.footnote.weight(.semibold)) }
                    Button(selected ? t("✓ Выбран", "✓ Selected", "✓ Tanlangan", "✓ Танланган") : t("Добавить в мой пакет", "Add to my package", "Paketimga qo‘shish", "Пакетимга қўшиш"), action: onSelect).buttonStyle(IumrahPrimaryButtonStyle()).disabled(guide.guideAvailable != true)
                }.padding(14).background(.regularMaterial)
            }
        }
    }
}

private struct IumrahGuideIntroVideo: View {
    let url: URL
    @State private var player: AVPlayer?
    var body: some View {
        VideoPlayer(player: player).task(id: url) { player = AVPlayer(url: url) }.onDisappear { player?.pause(); player = nil }
    }
}

private struct IumrahGuideProgram: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let trip: TripDraft
    private func t(_ r: String, _ e: String, _ u: String, _ c: String) -> String { IumrahFlightCopy.text(settings.language, r, e, u, c) }
    private var steps: [(String, String, String, String?)] {
        [
            ("airplane.arrival", t("Встреча в аэропорту", "Airport welcome", "Aeroportda kutib olish", "Аэропортда кутиб олиш"), t("Гид встречает семью, помогает сориентироваться и координирует трансфер до отеля.", "Your guide meets the family, helps you find your way and coordinates the transfer to the hotel.", "Gid oilani kutib oladi va mehmonxonaga transferni muvofiqlashtiradi.", "Гид оилани кутиб олади ва меҳмонхонага трансферни мувофиқлаштиради."), nil),
            ("bed.double", t("Размещение в отеле", "Hotel check-in", "Mehmonxonaga joylashish", "Меҳмонхонага жойлашиш"), t("Помощь с заселением, общением с персоналом и организационными вопросами.", "Help with check-in, communication with hotel staff and practical arrangements.", "Joylashish, xodimlar bilan muloqot va tashkiliy masalalarda yordam.", "Жойлашиш, ходимлар билан мулоқот ва ташкилий масалаларда ёрдам."), "IumrahFriendsHotelsCover"),
            ("book.closed", t("Подготовка к умре", "Umrah preparation", "Umraga tayyorgarlik", "Умрага тайёргарлик"), t("Объясняет правила ихрама, намерение, последовательность обрядов и необходимые знания до их совершения.", "Explains ihram, intention, the sequence of rituals and essential knowledge before performing them.", "Ehrom, niyat, amallar ketma-ketligi va zarur bilimlarni tushuntiradi.", "Эҳром, ният, амаллар кетма-кетлиги ва зарур билимларни тушунтиради."), nil),
            ("person.2", t("Совершение умры", "Performing Umrah", "Umra amallari", "Умра амаллари"), t("Сопровождает при тавафе, са‘и и завершении обрядов в темпе вашей семьи.", "Accompanies you through tawaf, sa‘i and completion of rituals at your family’s pace.", "Tavof, sa’y va amallar yakunida oilangizga mos sur’atda hamrohlik qiladi.", "Тавоф, саъй ва амаллар якунида оилангизга мос суръатда ҳамроҳлик қилади."), "AboutIumrahPilgrims"),
            ("map", t("Зияраты и святые места", "Ziyarats and sacred sites", "Ziyoratlar va muqaddas joylar", "Зиёратлар ва муқаддас жойлар"), trip.scope == .makkahAndMadinah ? t("Знакомство с историческими местами Мекки и Медины по согласованной программе.", "Discover historic sites in Makkah and Madinah according to the agreed program.", "Kelishilgan dastur bo‘yicha Makka va Madina tarixiy joylari.", "Келишилган дастур бўйича Макка ва Мадина тарихий жойлари.") : t("Исторические места Мекки по согласованной программе.", "Historic sites in Makkah according to the agreed program.", "Kelishilgan dastur bo‘yicha Makka tarixiy joylari.", "Келишилган дастур бўйича Макка тарихий жойлари."), trip.scope == .makkahAndMadinah ? "ZiyaratQuba1" : "AboutIumrahKaabaCorner"),
            ("heart", t("Забота до отъезда", "Care until departure", "Jo‘nashgacha g‘amxo‘rlik", "Жўнашгача ғамхўрлик"), t("Помощь с бытовыми вопросами, рекомендациями, дополнительными поездками и координацией отъезда.", "Help with everyday needs, recommendations, extra trips and departure coordination.", "Kundalik masalalar, tavsiyalar, qo‘shimcha safarlar va jo‘nashda yordam.", "Кундалик масалалар, тавсиялар, қўшимча сафарлар ва жўнашда ёрдам."), nil)
        ]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Что входит в сопровождение", "What accompaniment includes", "Hamrohlikka nimalar kiradi", "Ҳамроҳликка нималар киради")).font(.system(.title2, design: .rounded, weight: .bold)).accessibilityAddTraits(.isHeader)
            Text(t("Ваша поездка — шаг за шагом", "Your journey, step by step", "Safaringiz qadamma-qadam", "Сафарингиз қадамма-қадам")).font(.subheadline).foregroundStyle(.secondary)
            ForEach(steps.indices, id: \.self) { index in
                let step = steps[index]
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 5) {
                        Group {
                            if let asset = step.3 { Image(asset).resizable().scaledToFill().frame(width: 82, height: 96).clipped() }
                            else { ZStack { Color.iumrahRaisedBackground; Image(systemName: step.0).font(.system(size: 28, weight: .medium)) }.frame(width: 82, height: 96) }
                        }.clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                        if index < steps.count - 1 { Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 1, height: 18) }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t("ЭТАП", "STEP", "BOSQICH", "БОСҚИЧ") + String(format: " %02d", index + 1)).font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary)
                        Text(step.1).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(step.2).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if index < steps.count - 1 { Divider() }
            }
        }.guideSurface()
    }
}

private extension View {
    func guideSurface() -> some View { padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28)) }
}
