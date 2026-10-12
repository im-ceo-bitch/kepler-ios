import SwiftUI

/// Uses only published Hotel First package snapshots already owned by the server.
/// This is a calendar of complete package prices, not individual room-night rates.
struct HotelPackagePriceGraphSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var storefront: HotelStorefrontStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDayID = ""
    @State private var centeredDayID: String?
    @State private var selectedPackage: StorefrontFlightPackagePreview?
    @State private var isOpeningPackage = false
    @State private var packageUnavailable = false

    private var days: [Date] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        return (0..<90).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var priceByDay: [String: HotelPackagePricePoint] {
        Dictionary(uniqueKeysWithValues: storefront.hotelPackagePriceCalendar.map { ($0.id, $0) })
    }

    private var selectedPrice: HotelPackagePricePoint? { priceByDay[selectedDayID] }

    private var minimumPrice: Decimal? { storefront.hotelPackagePriceCalendar.map(\.pricePerPersonUSD).min() }
    private var maximumPrice: Double {
        max(1, storefront.hotelPackagePriceCalendar.map { NSDecimalNumber(decimal: $0.pricePerPersonUSD).doubleValue }.max() ?? 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(localized("Готовые пакеты по датам", "Packages by date", "Sanalar bo‘yicha paketlar", "Саналар бўйича пакетлар", "Tarihe göre paketler", "Paket menurut tanggal", "Pakej mengikut tarikh"))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text(localized("Актуальные опубликованные цены Iumrah в долларах США", "Current published Iumrah prices in US dollars", "Iumrah e’lon qilgan joriy narxlar USDda", "Iumrah эълон қилган жорий нархлар USDда", "Güncel yayınlanan Iumrah fiyatları (USD)", "Harga Iumrah terkini dalam USD", "Harga Iumrah semasa dalam USD"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.blue)
                            Text(selectedDateTitle)
                                .font(.headline)
                            Spacer()
                            Text("USD")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .bottom, spacing: 9) {
                                ForEach(days, id: \.self) { date in
                                    let id = dateID(date)
                                    dayColumn(date: date, quote: priceByDay[id], selected: selectedDayID == id)
                                        .id(id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: $centeredDayID, anchor: .center)
                        .onChange(of: centeredDayID) { _, next in
                            guard let next, next != selectedDayID else { return }
                            selectedDayID = next
                            IumrahHaptics.soft()
                        }

                        HStack(spacing: 8) {
                            Circle().fill(Color.green).frame(width: 9, height: 9)
                            Text(localized("Самая выгодная дата", "Lowest available price", "Eng arzon sana", "Энг арзон сана", "En uygun tarih", "Tanggal termurah", "Tarikh termurah"))
                            Spacer(minLength: 3)
                            Circle().fill(Color.gray.opacity(0.4)).frame(width: 9, height: 9)
                            Text(localized("Другие даты", "Other dates", "Boshqa sanalar", "Бошқа саналар", "Diğer tarihler", "Tanggal lain", "Tarikh lain"))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 17)
                    }
                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                    VStack(alignment: .leading, spacing: 12) {
                        if let quote = selectedPrice {
                            Text(localized("Доступно на выбранную дату", "Available on selected date", "Tanlangan sanada mavjud", "Танланган санада мавжуд", "Seçilen tarihte mevcut", "Tersedia pada tanggal ini", "Tersedia pada tarikh ini"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(money(quote.pricePerPersonUSD))
                                .environment(\.layoutDirection, .leftToRight)
                                .font(.system(size: 36, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                            Text(localized("Стоимость готового пакета за одного паломника, включая перелёт, отель и услуги. Не цена за ночь в отеле.", "Complete package price per pilgrim, including flights, hotel and services. Not a room-night rate.", "Parvoz, mehmonxona va xizmatlar bilan bir ziyoratchi uchun tayyor paket narxi. Bir kechalik xona narxi emas.", "Парвоз, меҳмонхона ва хизматлар билан бир зиёратчи учун тайёр пакет нархи. Бир кечалик хона нархи эмас.", "Uçuş, otel ve hizmetler dahil kişi başı paket fiyatı. Gecelik oda fiyatı değildir.", "Harga paket per jemaah termasuk penerbangan, hotel, dan layanan; bukan tarif kamar per malam.", "Harga pakej seorang jemaah termasuk penerbangan, hotel dan perkhidmatan; bukan harga bilik semalam."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if quote.isEstimated {
                                Label(localized("Предварительная опубликованная цена — подтвердится при бронировании", "Published estimate — confirmed at booking", "E’lon qilingan taxminiy narx — band qilishda tasdiqlanadi", "Эълон қилинган тахминий нарх — банд қилишда тасдиқланади", "Yayınlanan tahmini fiyat — rezervasyonda doğrulanır", "Estimasi harga — dikonfirmasi saat pemesanan", "Anggaran harga — disahkan semasa tempahan"), systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                guard !isOpeningPackage else { return }
                                isOpeningPackage = true
                                IumrahHaptics.selection()
                                Task { @MainActor in
                                    selectedPackage = await storefront.packagePreview(id: quote.packageID)
                                    packageUnavailable = selectedPackage == nil
                                    isOpeningPackage = false
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    if isOpeningPackage { ProgressView().tint(.white) }
                                    Text(localized("Посмотреть пакет", "View package", "Paketni ko‘rish", "Пакетни кўриш", "Paketi görüntüle", "Lihat paket", "Lihat pakej"))
                                    Image(systemName: "arrow.right")
                                }
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(isOpeningPackage)
                        } else {
                            Label(localized("Нет опубликованной цены на выбранную дату", "No published price for this date", "Bu sanada e’lon qilingan narx yo‘q", "Бу санада эълон қилинган нарх йўқ", "Bu tarih için yayınlanmış fiyat yok", "Belum ada harga untuk tanggal ini", "Tiada harga untuk tarikh ini"), systemImage: "calendar.badge.exclamationmark")
                                .font(.subheadline.weight(.semibold))
                            Text(localized("Пролистайте даты или обновите предложения. Неизвестные цены не рассчитываются искусственно.", "Swipe to another date or refresh offers. Missing prices are never estimated.", "Boshqa sanani suring yoki takliflarni yangilang. Narxlar taxmin qilinmaydi.", "Бошқа санани суринг ёки таклифларни янгиланг. Нархлар тахмин қилинмайди.", "Başka bir tarihe kaydırın veya teklifleri yenileyin.", "Geser ke tanggal lain atau perbarui penawaran.", "Leret ke tarikh lain atau muat semula tawaran."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 23, style: .continuous))

                    Button {
                        Task { await storefront.refresh() }
                    } label: {
                        Label(localized("Обновить цены", "Refresh prices", "Narxlarni yangilash", "Нархларни янгилаш", "Fiyatları yenile", "Perbarui harga", "Muat semula harga"), systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(storefront.isLoading)
                    .frame(maxWidth: .infinity)
                }
                .padding(20)
                .padding(.bottom, 28)
            }
            .background(Color.iumrahPageBackground)
            .navigationTitle(localized("График цен", "Price chart", "Narx grafigi", "Нарх графиги", "Fiyat grafiği", "Grafik harga", "Carta harga"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(localized("Готово", "Done", "Tayyor", "Тайёр", "Bitti", "Selesai", "Selesai")) { dismiss() }
                }
            }
            .navigationDestination(item: $selectedPackage) { preview in
                StorefrontUmrahPackageDetailView(preview: preview)
            }
            .alert(localized("Пакет недоступен", "Package unavailable", "Paket mavjud emas", "Пакет мавжуд эмас", "Paket kullanılamıyor", "Paket tidak tersedia", "Pakej tidak tersedia"), isPresented: $packageUnavailable) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(localized("Обновите цены и выберите другое предложение.", "Refresh prices and choose another offer.", "Narxlarni yangilab, boshqa taklifni tanlang.", "Нархларни янгилаб, бошқа таклифни танланг.", "Fiyatları yenileyin ve başka bir teklif seçin.", "Perbarui harga dan pilih penawaran lain.", "Muat semula harga dan pilih tawaran lain."))
            }
            .onAppear {
                if selectedDayID.isEmpty {
                    let availableIDs = Set(days.map(dateID))
                    let first = storefront.hotelPackagePriceCalendar
                        .first(where: { availableIDs.contains($0.id) })?.id
                        ?? days.first.map(dateID) ?? ""
                    selectedDayID = first
                    centeredDayID = first
                }
            }
            .task {
                await storefront.prepareIfNeeded()
                if selectedPrice == nil,
                   let available = storefront.hotelPackagePriceCalendar.first(where: { priceByDay[$0.id] != nil }) {
                    withAnimation(.smooth(duration: 0.30)) {
                        selectedDayID = available.id
                        centeredDayID = available.id
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func dayColumn(date: Date, quote: HotelPackagePricePoint?, selected: Bool) -> some View {
        let amount = quote.map { NSDecimalNumber(decimal: $0.pricePerPersonUSD).doubleValue }
        let best = quote != nil && quote?.pricePerPersonUSD == minimumPrice
        return Button {
            guard selectedDayID != dateID(date) else { return }
            withAnimation(.smooth(duration: 0.25)) {
                selectedDayID = dateID(date)
                centeredDayID = dateID(date)
            }
            IumrahHaptics.soft()
        } label: {
            VStack(spacing: 9) {
                Text(quote.map { shortMoney($0.pricePerPersonUSD) } ?? "—")
                    .environment(\.layoutDirection, .leftToRight)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.blue : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.blue : (best ? Color.green : Color.gray.opacity(0.28)))
                    .frame(width: 43, height: amount.map { CGFloat(max(30.0, min(142.0, 142.0 * $0 / maximumPrice))) } ?? 7)
                    .frame(height: 145, alignment: .bottom)
                Text(dayNumber(date))
                    .font(.system(size: 15, weight: selected ? .bold : .medium, design: .rounded))
                Text(weekday(date))
                    .font(.caption2)
            }
            .foregroundStyle(selected ? Color.blue : Color.primary)
            .frame(width: 53)
            .padding(.vertical, 5)
            .background(selected ? Color.blue.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dateTitle(date)), \(quote.map { money($0.pricePerPersonUSD) } ?? "—")")
    }

    private var selectedDateTitle: String {
        guard let date = days.first(where: { dateID($0) == selectedDayID }) else { return "—" }
        return dateTitle(date)
    }

    private func dateID(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dateTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func dayNumber(_ date: Date) -> String { String(Calendar.current.component(.day, from: date)) }

    private func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    private func money(_ value: Decimal) -> String {
        String(format: "$%.0f", NSDecimalNumber(decimal: value).doubleValue)
    }

    private func shortMoney(_ value: Decimal) -> String {
        String(format: "$%.0f", NSDecimalNumber(decimal: value).doubleValue)
    }

    private var arabicTranslations: [String: String] {
        [
            "Packages by date": "الباقات حسب التاريخ",
            "Current published Iumrah prices in US dollars": "أسعار باقات عمرة المنشورة بالدولار الأمريكي",
            "Lowest available price": "أقل سعر متاح",
            "Other dates": "تواريخ أخرى",
            "Available on selected date": "متاح في التاريخ المحدد",
            "Complete package price per pilgrim, including flights, hotel and services. Not a room-night rate.": "سعر الباقة الكاملة لكل معتمر، بما يشمل الطيران والفندق والخدمات، وليس سعر الغرفة لليلة واحدة.",
            "Published estimate — confirmed at booking": "سعر تقديري منشور — يتم تأكيده عند الحجز",
            "View package": "عرض الباقة",
            "No published price for this date": "لا يوجد سعر منشور لهذا التاريخ",
            "Swipe to another date or refresh offers. Missing prices are never estimated.": "اسحب لاختيار تاريخ آخر أو حدّث العروض. لا نعرض أسعارًا غير متوفرة.",
            "Refresh prices": "تحديث الأسعار",
            "Price chart": "مخطط الأسعار",
            "Done": "تم",
            "Package unavailable": "الباقة غير متاحة",
            "Refresh prices and choose another offer.": "حدّث الأسعار واختر عرضًا آخر.",
        ]
    }

    private func localized(_ ru: String, _ en: String, _ uz: String, _ cy: String, _ tr: String, _ id: String, _ ms: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .english: return en
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        case .turkish: return tr
        case .indonesian: return id
        case .malay: return ms
        case .arabic: return arabicTranslations[en] ?? ArabicLocalization.phrase(en)
        }
    }
}
