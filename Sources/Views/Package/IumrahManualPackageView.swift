import SwiftUI

struct IumrahManualFlightDetail: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var manual: IumrahManualJourneyStore
    @Environment(\.dismiss) private var dismiss
    let flight: LocalJourneyFlight
    private var selected: Bool { manual.outbound?.id == flight.id || manual.inbound?.id == flight.id }
    private var leg: IumrahPremiumFlightLeg {
        .init(airline: flight.airline, airlineCode: flight.airlineCode, number: flight.flightNumber,
              origin: flight.origin, destination: flight.destination, departure: flight.departureAt,
              arrival: flight.arrivalAt, duration: flight.durationMinutes, stops: flight.stops, cabin: flight.publishedCabin)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                IumrahPremiumFlightDetail(leg: leg, language: settings.language, pageHeroInset: 18, headerShareText: leg.share)
                if let price = flight.displayedPrice, price > 0 {
                    Text(NuiteeHotelService.usd(price)).font(.title.bold())
                    Text(t("Ориентировочный тариф за человека", "Indicative fare per person", "Bir kishi uchun taxminiy narx", "Бир киши учун тахминий нарх")).foregroundStyle(.secondary)
                }
                if flight.publishedIsPair == true {
                    Text(t("Этот рейс опубликован в паре. Выберите второй рейс из того же маршрута.", "This flight belongs to a published pair. Select its matching leg.", "Bu reys juft yo‘nalishda. Ikkinchi reysni shu yo‘nalishdan tanlang.", "Бу рейс жуфт йўналишда. Иккинчи рейсни шу йўналишдан танланг.")).font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    manual.select(flight); IumrahHaptics.success(); dismiss()
                } label: {
                    Text(selected ? t("Авиабилет добавлен в пакет", "Flight added to package", "Aviachipta paketga qo‘shildi", "Авиачипта пакетга қўшилди") : t("Добавить в мой пакет", "Add to my package", "Paketimga qo‘shish", "Пакетимга қўшиш"))
                        .frame(maxWidth: .infinity)
                }.buttonStyle(IumrahPrimaryButtonStyle())
            }.padding(.horizontal, 18).padding(.bottom, 30)
        }.background(Color.iumrahPageBackground)
            .toolbar(.hidden, for: .navigationBar).toolbar(.hidden, for: .tabBar)
    }
    private func t(_ ru: String,_ en: String,_ uz: String,_ cy: String) -> String { IumrahFlightCopy.text(settings.language, ru, en, uz, cy) }
}

struct IumrahManualTransferCatalog: View {
    @EnvironmentObject private var manual: IumrahManualJourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    private func t(_ ru: String,_ en: String,_ uz: String,_ cy: String) -> String { IumrahFlightCopy.text(settings.language, ru, en, uz, cy) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Приватный трансфер", "Private transfer", "Shaxsiy transfer", "Шахсий трансфер")).font(.title.bold())
            Text(t("Выберите отдельный автомобиль для вашей семьи. Стоимость подтвердит сервер вместе с остальными компонентами.", "Choose a private car for your family. The server confirms its price with your other selections.", "Oilangiz uchun alohida avtomobil tanlang. Narx paket bilan tasdiqlanadi.", "Оилангиз учун алоҳида автомобил танланг. Нарх пакет билан тасдиқланади.")).foregroundStyle(.secondary)
            ForEach(TransferVehicleKind.allCases) { vehicle in
                let selected = manual.transfer == vehicle
                Button {
                    manual.transfer = vehicle; IumrahHaptics.success()
                } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(vehicle.assetName).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 130)
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(vehicle.modelName).font(.headline)
                                Label("\(vehicle.passengerCapacity)", systemImage: "person.2").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title2)
                        }
                        Text(selected ? t("Трансфер добавлен в пакет", "Transfer added to package", "Transfer paketga qo‘shildi", "Трансфер пакетга қўшилди") : t("Добавить в мой пакет", "Add to my package", "Paketimga qo‘shish", "Пакетимга қўшиш"))
                            .font(.subheadline.weight(.semibold))
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26))
                        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.primary.opacity(selected ? 0.8 : 0.08), lineWidth: selected ? 1.5 : 1))
                }.buttonStyle(.plain).disabled(vehicle.passengerCapacity < manual.adults)
                    .opacity(vehicle.passengerCapacity < manual.adults ? 0.55 : 1)
            }
            Button(t("Открыть мой пакет", "Open my package", "Paketimni ochish", "Пакетимни очиш")) { chrome.openHotels(board: .summary) }.buttonStyle(IumrahPrimaryButtonStyle())
        }.padding(.horizontal, IumrahDesign.pagePadding).padding(.top, 16)
    }
}

struct IumrahManualPackageView: View {
    @EnvironmentObject private var manual: IumrahManualJourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var chrome: AppChromeStore
    @State private var pricedJourney: JourneyStore?
    @State private var pricedKey: String?
    @State private var busy = false
    @State private var showFinal = false
    @State private var retry = 0
    private func t(_ ru: String,_ en: String,_ uz: String,_ cy: String) -> String { IumrahFlightCopy.text(settings.language, ru, en, uz, cy) }
    private var currentQuote: PackageQuote? { pricedKey == manual.revisionKey && pricedJourney?.hasFinalGeneratorQuote == true ? pricedJourney?.quote : nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("Мой пакет", "My package", "Mening paketim", "Менинг пакетим")).font(.title.bold())
            Text(t("Выбирайте компоненты в любом порядке. Для бронирования необходимы все обязательные услуги и подтверждённая цена.", "Choose components in any order. Booking requires all mandatory services and a confirmed price.", "Qismlarni istalgan tartibda tanlang. Bron uchun barcha xizmatlar va tasdiqlangan narx kerak.", "Қисмларни исталган тартибда танланг. Брон учун барча хизматлар ва тасдиқланган нарх керак.")).foregroundStyle(.secondary)
            Picker(t("Маршрут", "Route", "Yo‘nalish", "Йўналиш"), selection: Binding(get: { manual.scope }, set: { manual.changeScope($0) })) {
                Text(t("Только Мекка", "Makkah only", "Faqat Makka", "Фақат Макка")).tag(JourneyScope.makkahOnly)
                Text(t("Мекка + Медина", "Makkah + Madinah", "Makka + Madina", "Макка + Мадина")).tag(JourneyScope.makkahAndMadinah)
            }.pickerStyle(.segmented)
            Stepper(t("Взрослых", "Adults", "Kattalar", "Катталар") + ": \(manual.adults)", value: $manual.adults, in: 1...6)
                .padding(16).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
            flightCard(manual.outbound, title: t("Авиабилет туда", "Outbound flight", "Borish aviachiptasi", "Бориш авиачиптаси"), direction: 0)
            flightCard(manual.inbound, title: t("Обратный авиабилет", "Return flight", "Qaytish aviachiptasi", "Қайтиш авиачиптаси"), direction: 1)
            if manual.outbound != nil && manual.inbound != nil && (manual.trip == nil || !manual.sourceCompatible) {
                Text(t("Проверьте даты, маршрут и совместимость билетов. Связанные рейсы нужно выбирать из одного опубликованного маршрута.", "Check flight dates, route and compatibility. Paired flights must belong to the same published itinerary.", "Reys sanalari va yo‘nalishini tekshiring.", "Рейс саналари ва йўналишини текширинг.")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(manual.cities, id: \.self) { city in hotelCard(city) }
            component(title: t("Приватный трансфер", "Private transfer", "Shaxsiy transfer", "Шахсий трансфер"), symbol: "car.side", detail: manual.transfer?.modelName,
                      valid: manual.transfer.map { $0.passengerCapacity >= manual.adults } ?? false,
                      onChoose: { chrome.openHotels(board: .transfer) }, onRemove: { manual.transfer = nil })
            Text(t("Цены в карточках — ориентировочные тарифы компонентов, не стоимость пакета. Визу, сопровождение и остальные услуги рассчитает сервер по правилам конфигуратора.", "Card prices are indicative component rates, not a package total. The server prices the visa, assistance and other services using the configurator rules.", "Kartalardagi narxlar taxminiy. Paket va xizmatlar narxini server hisoblaydi.", "Карталардаги нархлар тахминий. Пакет ва хизматлар нархини сервер ҳисоблайди.")).font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Text(t("Итоговая цена", "Package total", "Yakuniy narx", "Якуний нарх")).font(.headline)
                if let quote = currentQuote {
                    Text(quote.currency + " " + NSDecimalNumber(decimal: quote.totalPackagePrice).stringValue).font(.largeTitle.bold())
                    if quote.bookingAllowed != true {
                        Text(t("Цена рассчитана, но сервер пока не разрешает бронирование.", "The quote is ready, but booking is not yet enabled by the server.", "Narx hisoblandi, ammo bron hali ochilmagan.", "Нарх ҳисобланди, аммо брон ҳали очилмаган.")).font(.footnote).foregroundStyle(.secondary)
                    }
                } else if busy { ProgressView() }
                else {
                    Text("—").font(.largeTitle.bold())
                    Text(manual.complete ? t("Сервер пока не подтвердил цену. Повторите расчёт.", "The server has not confirmed a price. Retry.", "Narx tasdiqlanmadi. Qayta urinib ko‘ring.", "Нарх тасдиқланмади. Қайта уриниб кўринг.") : t("Цена будет рассчитана после выбора всех обязательных компонентов.", "The total is calculated once all required components are selected.", "Barcha qismlar tanlangach narx hisoblanadi.", "Барча қисмлар танлангач нарх ҳисобланади."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if manual.complete && currentQuote == nil && !busy {
                    Button(t("Повторить расчёт", "Retry quote", "Qayta hisoblash", "Қайта ҳисоблаш")) { retry += 1 }
                }
                Button(t("Перейти к бронированию", "Continue to booking", "Bron qilishga o‘tish", "Брон қилишга ўтиш")) { showFinal = true }
                    .buttonStyle(IumrahPrimaryButtonStyle()).disabled(!manual.complete || busy || currentQuote?.bookingAllowed != true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28))
        }.padding(.horizontal, IumrahDesign.pagePadding).padding(.top, 16)
            .task(id: manual.revisionKey + ":\(retry)") { await requestQuote() }
            .navigationDestination(isPresented: $showFinal) {
                if let pricedJourney { FinalPackageView().environmentObject(pricedJourney) }
            }
    }
    @MainActor private func requestQuote() async {
        let key = manual.revisionKey
        pricedJourney = nil; pricedKey = nil; busy = false
        guard let draft = manual.makeQuoteJourney() else { return }
        busy = true
        await draft.buildQuote()
        guard !Task.isCancelled, key == manual.revisionKey else { return }
        busy = false; pricedJourney = draft; pricedKey = key
    }
    private func flightCard(_ flight: LocalJourneyFlight?, title: String, direction: Int) -> some View {
        component(title: title, symbol: "airplane", detail: flight.map { flight in
            let price = flight.displayedPrice.map { " · " + NuiteeHotelService.usd($0) } ?? ""
            return "\(flight.origin) → \((flight.destination)) · \((flight.airline)) \((flight.flightNumber))\n\(String(flight.departureAt.prefix(10)))" + price
        }, valid: flight != nil,
                  onChoose: { chrome.requestedManualFlightDirection = direction; chrome.openHotels(board: .flights) }, onRemove: { if direction == 0 { manual.outbound = nil } else { manual.inbound = nil } })
    }
    private func hotelCard(_ city: String) -> some View {
        let room = manual.rooms[city]
        let title = city == "madinah" ? t("Отель в Медине", "Madinah hotel", "Madinadagi mehmonxona", "Мадинадаги меҳмонхона") : t("Отель в Мекке", "Makkah hotel", "Makkadagi mehmonxona", "Маккадаги меҳмонхона")
        let window = manual.expectedWindow(city)
        let dates = window.map { "\($0.checkIn.formatted(date: .abbreviated, time: .omitted)) — \($0.checkOut.formatted(date: .abbreviated, time: .omitted))" }
        let detail = room.map { "\($0.hotel.name) · \($0.rate.roomName)\n\($0.checkin.formatted(date: .abbreviated, time: .omitted)) — \($0.checkout.formatted(date: .abbreviated, time: .omitted)) · " + NuiteeHotelService.usd($0.rate.price) }
        return VStack(alignment: .leading, spacing: 6) {
            component(title: title, symbol: "bed.double", detail: detail, valid: manual.trip == nil ? room != nil : manual.validRoom(city), onChoose: {
                chrome.requestedManualHotelCity = city; chrome.openHotels(board: .hotels)
            }, onRemove: { manual.rooms.removeValue(forKey: city) })
            if let dates, !manual.validRoom(city) {
                Text(t("Необходимые даты", "Required dates", "Kerakli sanalar", "Керакли саналар") + ": " + dates).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func component(title: String, symbol: String, detail: String?, valid: Bool, onChoose: @escaping () -> Void, onRemove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol).font(.title3).frame(width: 28)
                Text(title).font(.headline)
                Spacer()
                Image(systemName: valid ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
            }
            Text(detail ?? t("Не выбрано", "Not selected", "Tanlanmagan", "Танланмаган")).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button(detail == nil ? t("Выбрать", "Choose", "Tanlash", "Танлаш") : t("Изменить", "Change", "O‘zgartirish", "Ўзгартириш"), action: onChoose).font(.subheadline.bold())
                Spacer()
                if detail != nil { Button(role: .destructive, action: onRemove) { Image(systemName: "trash").foregroundStyle(.secondary) }.accessibilityLabel(t("Удалить", "Remove", "O‘chirish", "Ўчириш")) }
            }.buttonStyle(.plain)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 25))
    }
}
