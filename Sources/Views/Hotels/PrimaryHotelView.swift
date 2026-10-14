import Foundation
import SwiftUI

enum PrimaryHotelEntryMode {
    case standard
    case flightFirst
}

struct PrimaryHotelView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.iumrahAdaptiveLayout) private var adaptiveLayout
    @State private var showTransfer = false
    @State private var isPreparingPublishedPackage = false
    @State private var publishedPackageError: String?
    @State private var activeHotelCity: HotelSelectionRole = .makkah
    @State private var starFilter: Int? = nil
    @State private var isUpdatingPrice = false

    // The server is the source of truth for package totals. Never invent a total
    // from the catalog hotel's nightly rate or reuse a quote for another selection.
    private var visibleTotal: String? {
        guard journey.hasFinalGeneratorQuote, let quote = journey.quote else {
            return isUpdatingPrice ? priceLoadingText : pricePendingText
        }
        let value = NSDecimalNumber(decimal: quote.totalPackagePrice).doubleValue
        return value.formatted(.currency(code: quote.currency).precision(.fractionLength(0)))
    }

    private var quoteInputKey: String {
        [journey.selectedHotel?.id ?? "", journey.selectedMadinahHotel?.id ?? "",
         journey.trip.packageTier.rawValue, journey.packageFlightPath.rawValue,
         journey.selectedRoom?.id ?? "", journey.selectedMadinahRoom?.id ?? "",
         String(journey.trip.travelerCount)].joined(separator: "|")
    }

    var entryMode: PrimaryHotelEntryMode = .standard

    private var requiresMadinah: Bool { journey.trip.scope == .makkahAndMadinah }
    private var canContinue: Bool {
        // Selection should not be blocked by a stale list-row cache. The existing
        // pricing pipeline re-reads hotel detail and still requires a fresh 48h
        // price before any final package quote can be produced.
        journey.selectedHotel != nil &&
        (!requiresMadinah || journey.selectedMadinahHotel != nil)
    }

    var body: some View {
        GeometryReader { viewport in
            let contentWidth = max(0, viewport.size.width - IumrahDesign.pagePadding * 2)

            VStack(spacing: 0) {
                // Keep one native glass generator header outside the ScrollView.
                // This preserves the animated stage, live total and back action
                // while the user scrolls through the hotel catalogue.
                IumrahGeneratorHeader(stage: .hotel, currentPriceText: visibleTotal)
                    .frame(width: contentWidth)
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .padding(.top, 9)
                    .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 21) {
                        heading
                        if entryMode == .flightFirst {
                            flightFirstContextCard
                            flightFirstTierSelector
                        }
                        hotelContent
                        cityAndStarNavigation
                        availableHotels
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .frame(width: viewport.size.width)
            }
        }
        .background(Color.iumrahPageBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedContinueButton
        }
        .iumrahInternalNavigation(progress: .hotel, showsGeneratorAmbient: true)
        .task {
            if journey.hotels.isEmpty { await journey.loadMakkahHotels() }
            if requiresMadinah, journey.madinahHotels.isEmpty { await journey.loadMadinahHotels() }
        }
        .task(id: quoteInputKey) {
            // Debounce rapid city/hotel changes so only the settled choice is
            // resolved against the live Package Engine.
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            await refreshCurrentPackagePrice()
        }
        .onChange(of: requiresMadinah) { _, included in
            if !included { activeHotelCity = .makkah }
            starFilter = nil
        }
        .onChange(of: activeHotelCity) { _, _ in
            starFilter = nil
            IumrahHaptics.selection()
        }
        .navigationDestination(isPresented: $showTransfer) {
            TransferSelectionView()
        }
        .alert(publishedErrorTitle, isPresented: Binding(
            get: { publishedPackageError != nil },
            set: { if !$0 { publishedPackageError = nil } }
        )) {
            Button("OK", role: .cancel) { publishedPackageError = nil }
        } message: {
            Text(publishedPackageError ?? "")
        }
    }

    private var pinnedContinueButton: some View {
        Group {
            if journey.packageFlightPath == .publishedDirect || journey.packageFlightPath == .aviasalesSelected {
                Button {
                    Task { await continuePublishedDirectPackage() }
                } label: {
                    continueLabel(publishedContinueTitle)
                }
                .disabled(!canContinue || isPreparingPublishedPackage)
            } else {
                NavigationLink {
                    OutboundFlightView()
                } label: {
                    continueLabel(FlowCopy.text(.continueToFlights, settings.language))
                }
                .disabled(!canContinue)
            }
        }
        .buttonStyle(IumrahPrimaryButtonStyle())
        .opacity(canContinue && !isPreparingPublishedPackage ? 1 : 0.46)
        .padding(.horizontal, IumrahDesign.pagePadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.iumrahPageBackground)
    }

    private func continueLabel(_ text: String) -> some View {
        HStack(spacing: 10) {
            if isPreparingPublishedPackage { ProgressView().tint(.white) }
            Text(text)
            if !isPreparingPublishedPackage { Image(systemName: "arrow.forward") }
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func refreshCurrentPackagePrice() async {
        // This step precedes flight search in the flexible-dates flow, so a
        // genuine total cannot exist until the itinerary is selected. In Flight
        // First the chosen itinerary can be resolved and quoted by the server.
        guard canContinue else { return }
        guard journey.packageFlightPath == .publishedDirect ||
              journey.packageFlightPath == .aviasalesSelected ||
              journey.selectedOutbound != nil else { return }
        guard !journey.hasFinalGeneratorQuote else { return }
        isUpdatingPrice = true
        defer { isUpdatingPrice = false }
        switch journey.packageFlightPath {
        case .publishedDirect:
            _ = await journey.preparePublishedDirectQuote()
        case .aviasalesSelected:
            _ = await journey.prepareAviasalesSelectedQuote()
        case .flexibleDates, .weekend:
            await journey.buildQuote()
        }
    }

    @MainActor
    private func continuePublishedDirectPackage() async {
        guard !isPreparingPublishedPackage else { return }
        isPreparingPublishedPackage = true
        publishedPackageError = nil
        defer { isPreparingPublishedPackage = false }

        let ready: Bool
        if journey.packageFlightPath == .aviasalesSelected {
            ready = await journey.prepareAviasalesSelectedQuote()
        } else {
            ready = await journey.preparePublishedDirectQuote()
        }
        if ready {
            IumrahHaptics.success()
            showTransfer = true
        } else {
            IumrahHaptics.error()
            publishedPackageError = journey.errorMessage ?? publishedFallbackError
        }
    }


    private var flightFirstContextCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "airplane.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(flightFirstTitle)
                        .font(.headline)
                    Text(flightFirstSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }

            if !journey.stagedUmrahFlights.isEmpty {
                Divider()
                ForEach(journey.stagedUmrahFlights) { flight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: flight.kind == .roundTrip ? "arrow.left.arrow.right" : "airplane")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flight.routeTitle)
                                .font(.subheadline.monospaced().weight(.bold))
                            Text([flight.airline, flight.flightNumber].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let returnAt = flight.returnAt {
                                Text("↩︎ \(String(returnAt.prefix(10)))" + ((flight.returnAirline ?? flight.returnFlightNumber) == nil ? "" : " · " + [flight.returnAirline, flight.returnFlightNumber].compactMap { $0 }.joined(separator: " · ")))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }

            if journey.packageFlightPath == .aviasalesSelected,
               let roundTrip = journey.stagedAviasalesOffers[.roundTrip],
               (roundTrip.returnAirlineCode?.isEmpty != false || roundTrip.returnFlightNumber?.isEmpty != false) {
                Label(unverifiedReturnFlightNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack(spacing: 14) {
                Label("\(max(1, journey.trip.travelerCount))", systemImage: "person.2.fill")
                Label(journey.trip.scope.title(settings.language), systemImage: "mappin.and.ellipse")
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.8)
        }
    }


    private var flightFirstTierSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(flightFirstHotelLevelTitle)
                    .font(.headline)
                Text(flightFirstHotelLevelSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: adaptiveLayout.isWide ? 4 : 2),
                spacing: 10
            ) {
                    ForEach(PackageTier.allCases) { tier in
                        let selected = journey.trip.packageTier == tier
                        Button {
                            guard !selected else { return }
                            IumrahHaptics.selection()
                            journey.selectPackageTier(tier)
                            Task {
                                await journey.loadMakkahHotels()
                                if requiresMadinah { await journey.loadMadinahHotels() }
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(tier.primaryHotelStars)★")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                Text(tier.title(settings.language))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(selected ? Color.iumrahPrimaryButtonText : Color.primary)
                            .padding(.horizontal, 15)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 66, alignment: .leading)
                            .background(
                                selected ? Color.iumrahPrimaryButtonBackground : Color.iumrahRaisedBackground,
                                in: RoundedRectangle(cornerRadius: 19, style: .continuous)
                            )
                            .overlay {
                                if !selected {
                                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
            }
        }
        .padding(16)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
    }

    private var unverifiedReturnFlightNote: String {
        switch settings.language {
        case .russian: return "Data API не указал авиакомпанию или номер обратного рейса. Проверьте эти данные у продавца до покупки билета."
        case .turkish: return TurkishLocalization.phrase("Data API did not provide the return carrier or flight number. Confirm these with the seller before buying.")
        case .arabic: return ArabicLocalization.phrase("Data API did not provide the return carrier or flight number. Confirm these with the seller before buying.")
        case .indonesian, .malay, .english: return "Data API did not provide the return carrier or flight number. Confirm these with the seller before buying."
        case .uzbek: return "Data API qaytish aviakompaniyasi yoki reys raqamini bermagan. Xarid qilishdan oldin sotuvchidan tekshiring."
        case .uzbekCyrillic: return "Data API қайтиш авиакомпанияси ёки рейс рақамини бермаган. Харид қилишдан олдин сотувчидан текширинг."
        }
    }

    private var flightFirstHotelLevelTitle: String {
        switch settings.language {
        case .russian: return "Уровень отеля"
        case .turkish: return TurkishLocalization.phrase("Hotel level")
        case .arabic: return ArabicLocalization.phrase("Hotel level")
        case .indonesian, .malay, .english: return "Hotel level"
        case .uzbek: return "Mehmonxona darajasi"
        case .uzbekCyrillic: return "Меҳмонхона даражаси"
        }
    }

    private var flightFirstHotelLevelSubtitle: String {
        switch settings.language {
        case .russian: return "Выберите звёздность — iumrah автоматически подберёт Primary Hotel для нужных городов."
        case .turkish: return TurkishLocalization.phrase("Choose the hotel level and iumrah will automatically resolve the Primary Hotel for each required city.")
        case .arabic: return ArabicLocalization.phrase("Choose the hotel level and iumrah will automatically resolve the Primary Hotel for each required city.")
        case .indonesian, .malay, .english: return "Choose the hotel level and iumrah will automatically resolve the Primary Hotel for each required city."
        case .uzbek: return "Yulduz darajasini tanlang — iumrah kerakli shaharlardagi Primary Hotel’ni avtomatik tavsiya qiladi."
        case .uzbekCyrillic: return "Юлдуз даражасини танланг — iumrah керакли шаҳарлардаги Primary Hotel’ни автоматик тавсия қилади."
        }
    }

    private var flightFirstTitle: String {
        switch settings.language {
        case .russian: return "Flight First · авиабилет выбран"
        case .turkish: return TurkishLocalization.phrase("Flight First · flight selected")
        case .arabic: return ArabicLocalization.phrase("Flight First · flight selected")
        case .indonesian, .malay, .english: return "Flight First · flight selected"
        case .uzbek: return "Flight First · aviachipta tanlangan"
        case .uzbekCyrillic: return "Flight First · авиачипта танланган"
        }
    }

    private var flightFirstSubtitle: String {
        switch settings.language {
        case .russian: return "Теперь выберите Primary Hotels. После этого flow продолжится к трансферу и итоговому сравнению пакета."
        case .turkish: return TurkishLocalization.phrase("Choose Primary Hotels next. The flow then continues to transfer and final package comparison.")
        case .arabic: return ArabicLocalization.phrase("Choose Primary Hotels next. The flow then continues to transfer and final package comparison.")
        case .indonesian, .malay, .english: return "Choose Primary Hotels next. The flow then continues to transfer and final package comparison."
        case .uzbek: return "Endi Primary Hotels’ni tanlang. Keyin flow transfer va yakuniy paket taqqoslashiga o‘tadi."
        case .uzbekCyrillic: return "Энди Primary Hotels’ни танланг. Кейин flow трансфер ва якуний пакет таққослашига ўтади."
        }
    }

    private var publishedContinueTitle: String {
        switch settings.language {
        case .russian: return "Продолжить к трансферу"
        case .turkish: return TurkishLocalization.phrase("Continue to transfer")
        case .arabic: return ArabicLocalization.phrase("Continue to transfer")
        case .indonesian, .malay, .english: return "Continue to transfer"
        case .uzbek: return "Transferga davom etish"
        case .uzbekCyrillic: return "Трансферга давом этиш"
        }
    }

    private var publishedErrorTitle: String {
        switch settings.language {
        case .russian: return "Не удалось собрать пакет"
        case .turkish: return TurkishLocalization.phrase("Could not build package")
        case .arabic: return ArabicLocalization.phrase("Could not build package")
        case .indonesian, .malay, .english: return "Could not build package"
        case .uzbek: return "Paketni yig‘ib bo‘lmadi"
        case .uzbekCyrillic: return "Пакетни йиғиб бўлмади"
        }
    }

    private var publishedFallbackError: String {
        switch settings.language {
        case .russian: return "Не удалось получить опубликованный рейс или актуальную цену отеля. Попробуйте ещё раз."
        case .turkish: return TurkishLocalization.phrase("The published flight or current hotel price could not be resolved. Please try again.")
        case .arabic: return ArabicLocalization.phrase("The published flight or current hotel price could not be resolved. Please try again.")
        case .indonesian, .malay, .english: return "The published flight or current hotel price could not be resolved. Please try again."
        case .uzbek: return "E’lon qilingan reys yoki mehmonxonaning dolzarb narxini olib bo‘lmadi. Qayta urinib ko‘ring."
        case .uzbekCyrillic: return "Эълон қилинган рейс ёки меҳмонхонанинг долзарб нархини олиб бўлмади. Қайта уриниб кўринг."
        }
    }

    // MARK: - Hotel alternatives, directly in step two (no Change Hotel screen)

    private var activeCatalog: [HotelSummary] {
        activeHotelCity == .makkah ? journey.hotels : journey.madinahHotels
    }

    private var preferredStars: Int {
        (activeHotelCity == .makkah ? journey.selectedHotel?.stars : journey.selectedMadinahHotel?.stars)
            ?? journey.trip.packageTier.primaryHotelStars
    }

    private var orderedStars: [Int] {
        var result: [Int] = []
        for value in [preferredStars, 5, 4, 3, 2, 1] where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private var orderedHotels: [HotelSummary] {
        let ranks = orderedStars
        return activeCatalog
            .filter { hotel in
                guard let stars = hotel.stars, (1...5).contains(stars) else { return false }
                return starFilter == nil || stars == starFilter
            }
            .sorted { lhs, rhs in
                let left = ranks.firstIndex(of: lhs.stars ?? 0) ?? 99
                let right = ranks.firstIndex(of: rhs.stars ?? 0) ?? 99
                if left != right { return left < right }
                if lhs.price?.isUsableForPackage != rhs.price?.isUsableForPackage {
                    return lhs.price?.isUsableForPackage == true
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private var cityAndStarNavigation: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 9) {
                cityButton(.makkah)
                if requiresMadinah { cityButton(.madinah) }
            }
            if !activeCatalog.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        starButton(nil)
                        ForEach(orderedStars.filter { stars in activeCatalog.contains(where: { $0.stars == stars }) }, id: \.self) { stars in
                            starButton(stars)
                        }
                    }
                }
                .contentMargins(.horizontal, 1)
            }
        }
        .padding(.top, 8)
    }

    private func cityButton(_ city: HotelSelectionRole) -> some View {
        let isActive = activeHotelCity == city
        return Button {
            withAnimation(.smooth(duration: 0.26)) { activeHotelCity = city }
        } label: {
            Label(city == .makkah ? localizedMakkah : localizedMadinah,
                  systemImage: city == .makkah ? "mappin.circle.fill" : "building.2.fill")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 47)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(isActive ? Color.primary : Color.iumrahCardBackground,
                            in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func starButton(_ stars: Int?) -> some View {
        let isActive = starFilter == stars
        return Button {
            IumrahHaptics.selection()
            withAnimation(.easeInOut(duration: 0.20)) { starFilter = stars }
        } label: {
            Text(stars.map { "\($0) ★" } ?? allHotelsTitle)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 17)
                .frame(height: 39)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(isActive ? Color.black : Color.iumrahCardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var availableHotels: some View {
        LazyVStack(spacing: 12) {
            if orderedHotels.isEmpty {
                ContentUnavailableView(emptyHotelsTitle, systemImage: "building.2.crop.circle")
            } else {
                ForEach(orderedHotels) { hotel in
                    alternativeHotelRow(hotel)
                }
            }
        }
    }

    private func alternativeHotelRow(_ hotel: HotelSummary) -> some View {
        let selected = (activeHotelCity == .makkah ? journey.selectedHotel?.id : journey.selectedMadinahHotel?.id) == hotel.id
        return HStack(alignment: .center, spacing: 12) {
            HotelCachedImage(rawURL: hotel.coverImageURL)
                .frame(width: 83, height: 91)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(hotel.name)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                Text("\(hotel.stars ?? 0) ★")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HotelPackageDeltaText(hotel: hotel, city: activeHotelCity, isSelected: selected,
                                      emptyLabel: pricePendingText)
                HStack(spacing: 11) {
                    NavigationLink {
                        HotelDetailView(hotel: hotel, selectionFlow: true, selectionRole: activeHotelCity)
                    } label: {
                        Text(FlowCopy.text(.viewHotel, settings.language))
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    if !selected {
                        Button {
                            IumrahHaptics.selection()
                            if activeHotelCity == .makkah { journey.chooseHotel(hotel) }
                            else { journey.chooseMadinahHotel(hotel) }
                        } label: {
                            Text(selectHotelTitle)
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(red: 0.23, green: 0.72, blue: 0.43))
                    } else {
                        Label(selectedHotelTitle, systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(red: 0.23, green: 0.72, blue: 0.43))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private var allHotelsTitle: String { stepText("Все", "All", "Barchasi", "Барчаси", "Tümü", "الكل", "Semua", "Semua") }
    private var emptyHotelsTitle: String { stepText("Нет доступных отелей", "No hotels available", "Mehmonxona topilmadi", "Меҳмонхона топилмади", "Otel bulunamadı", "لا توجد فنادق", "Tidak ada hotel tersedia", "Tiada hotel tersedia") }
    private var selectHotelTitle: String { stepText("Выбрать", "Select", "Tanlash", "Танлаш", "Seç", "اختيار", "Pilih", "Pilih") }
    private var selectedHotelTitle: String { stepText("Выбран", "Selected", "Tanlandi", "Танланди", "Seçildi", "تم الاختيار", "Dipilih", "Dipilih") }
    private var priceLoadingText: String { stepText("Расчёт…", "Calculating…", "Hisoblanmoqda…", "Ҳисобланмоқда…", "Hesaplanıyor…", "جارٍ الحساب…", "Menghitung…", "Mengira…") }
    private var pricePendingText: String { stepText("После выбора рейса", "After flight selection", "Reys tanlangach", "Рейс танлангач", "Uçuş seçiminden sonra", "بعد اختيار الرحلة", "Setelah memilih penerbangan", "Selepas memilih penerbangan") }

    private func stepText(_ ru: String, _ en: String, _ uz: String, _ cy: String, _ tr: String, _ ar: String, _ id: String, _ ms: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        case .turkish: return tr
        case .arabic: return ar
        case .english: return en
        case .indonesian: return id
        case .malay: return ms
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(FlowCopy.text(.hotelStageEyebrow, settings.language))
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
            Text(FlowCopy.text(.hotelStageTitle, settings.language))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.8)
            Text(FlowCopy.text(.hotelStageBody, settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var hotelContent: some View {
        if adaptiveLayout.isWide && requiresMadinah {
            HStack(alignment: .top, spacing: 20) {
                cityHotelContent(role: .makkah)
                    .frame(maxWidth: .infinity, alignment: .top)
                cityHotelContent(role: .madinah)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
        } else {
            cityHotelContent(role: .makkah)
            if requiresMadinah {
                cityHotelContent(role: .madinah)
            }
        }
    }

    @ViewBuilder
    private func cityHotelContent(role: HotelSelectionRole) -> some View {
        let isMakkah = role == .makkah
        let isLoading = isMakkah ? journey.isLoadingHotels : journey.isLoadingMadinahHotels
        let selectedHotel = isMakkah ? journey.selectedHotel : journey.selectedMadinahHotel
        let roomName = isMakkah
            ? (journey.selectedRoom?.name ?? journey.selectedRoomCategory?.displayName)
            : (journey.selectedMadinahRoom?.name ?? journey.selectedMadinahRoomCategory?.displayName)

        if isLoading && selectedHotel == nil {
            loadingCard
        } else if let hotel = selectedHotel {
            stayCard(
                hotel: hotel,
                role: role,
                title: recommendedTitle(role: role),
                roomName: roomName
            )
        } else {
            missingHotelCard(role: role)
        }
    }

    private func recommendedTitle(role: HotelSelectionRole) -> String {
        switch settings.language {
        case .turkish:
            return "iumrah Öneriyor"
        case .arabic: return "توصية iumrah"
        case .indonesian, .malay, .english:
            return "iumrah Recommended"
        case .russian:
            return "Рекомендуем iumrah"
        case .uzbek:
            return "iumrah tavsiyasi"
        case .uzbekCyrillic:
            return "iumrah тавсияси"
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 13) {
            ProgressView()
            Text(L10n.text("primary_hotel_loading", settings.language))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .background(Color.iumrahCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func stayCard(hotel: HotelSummary, role: HotelSelectionRole, title: String, roomName: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hotelImage(hotel)
                .frame(height: 214)
                .background(Color.iumrahRaisedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(12)
                .padding(.bottom, 0)

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Label(title, systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color(red: 0.28, green: 0.79, blue: 0.49).opacity(0.13), in: Capsule())

                    Spacer(minLength: 8)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color(red: 0.23, green: 0.72, blue: 0.43))
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 7) {
                        Text(FlowCopy.text(.primaryHotel, settings.language))
                        if let stars = hotel.stars { Text("· \(stars)★") }
                        Text("·")
                        Text(role == .makkah ? localizedMakkah : localizedMadinah)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    Text(hotel.name)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                }

                HStack(spacing: 8) {
                    Label(L10n.city(hotel.city, settings.language), systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.iumrahRaisedBackground, in: Capsule())

                    if let roomName, !roomName.isEmpty {
                        Label(roomName, systemImage: "bed.double.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .padding(.horizontal, 11)
                            .frame(height: 32)
                            .background(Color.iumrahRaisedBackground, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }

                if journey.hasSelectableHotelMeals {
                    mealPlanCard(role: role)
                }

                NavigationLink {
                    HotelDetailView(hotel: hotel, selectionFlow: true, selectionRole: role)
                } label: {
                    Label(FlowCopy.text(.viewHotel, settings.language), systemImage: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftHotelActionButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.iumrahCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.05), radius: 18, y: 8)
    }

    private func mealPlanCard(role: HotelSelectionRole) -> some View {
        let city: HotelMealCity = role == .makkah ? .makkah : .madinah

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(mealPlanTitle)
                        .font(.subheadline.weight(.bold))
                    Text(mealScheduleText(role: role))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)

            Divider().padding(.leading, 54)
            includedBreakfastRow

            if role == .makkah {
                Divider().padding(.leading, 54)
                selectableMealRow(.lunch, city: city)
            }

            Divider().padding(.leading, 54)
            selectableMealRow(.dinner, city: city)
        }
        .background(Color.iumrahRaisedBackground.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.045), lineWidth: 0.6)
        }
    }

    private var includedBreakfastRow: some View {
        HStack(spacing: 12) {
            mealIcon("cup.and.saucer.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text(mealName(.breakfast))
                    .font(.subheadline.weight(.semibold))
                Text(mealIncludedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(red: 0.23, green: 0.72, blue: 0.43))
                .accessibilityLabel(mealIncludedText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func selectableMealRow(_ meal: HotelMealKind, city: HotelMealCity) -> some View {
        let price = PackagePricingPresentation.optionalMealUnitPriceUsd(for: journey.trip.packageTier) ?? 0
        let isOn = Binding(
            get: { journey.isMealEnabled(meal, city: city) },
            set: { journey.setMealEnabled($0, meal: meal, city: city) }
        )

        return HStack(spacing: 12) {
            mealIcon(meal == .lunch ? "sun.max.fill" : "moon.stars.fill")

            VStack(alignment: .leading, spacing: 2) {
                Text(mealName(meal))
                    .font(.subheadline.weight(.semibold))
                Text(optionalMealPriceText(price))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(Color(red: 0.23, green: 0.72, blue: 0.43))
                .accessibilityLabel(mealName(meal))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func mealIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
    }

    private var mealPlanTitle: String {
        switch settings.language {
        case .russian: return "Питание в отеле"
        case .turkish: return TurkishLocalization.phrase("Hotel meals")
        case .arabic: return ArabicLocalization.phrase("Hotel meals")
        case .indonesian, .malay, .english: return "Hotel meals"
        case .uzbek: return "Mehmonxonada ovqatlanish"
        case .uzbekCyrillic: return "Меҳмонхонада овқатланиш"
        }
    }

    private func mealScheduleText(role: HotelSelectionRole) -> String {
        switch (settings.language, role) {
        case (.russian, .makkah): return "Мекка · завтрак, обед и ужин"
        case (.russian, .madinah): return "Медина · завтрак и ужин"
        case (.turkish, .makkah): return TurkishLocalization.phrase("Makkah · breakfast, lunch and dinner")
        case (.arabic, .makkah): return ArabicLocalization.phrase("Makkah · breakfast, lunch and dinner")
        case (.indonesian, .makkah), (.malay, .makkah), (.english, .makkah): return "Makkah · breakfast, lunch and dinner"
        case (.turkish, .madinah): return TurkishLocalization.phrase("Madinah · breakfast and dinner")
        case (.arabic, .madinah): return ArabicLocalization.phrase("Madinah · breakfast and dinner")
        case (.indonesian, .madinah), (.malay, .madinah), (.english, .madinah): return "Madinah · breakfast and dinner"
        case (.uzbek, .makkah): return "Makka · nonushta, tushlik va kechki ovqat"
        case (.uzbek, .madinah): return "Madina · nonushta va kechki ovqat"
        case (.uzbekCyrillic, .makkah): return "Макка · нонушта, тушлик ва кечки овқат"
        case (.uzbekCyrillic, .madinah): return "Мадина · нонушта ва кечки овқат"
        }
    }

    private func mealName(_ meal: HotelMealKind) -> String {
        switch (settings.language, meal) {
        case (.russian, .breakfast): return "Завтрак"
        case (.russian, .lunch): return "Обед"
        case (.russian, .dinner): return "Ужин"
        case (.turkish, .breakfast): return TurkishLocalization.phrase("Breakfast")
        case (.arabic, .breakfast): return ArabicLocalization.phrase("Breakfast")
        case (.indonesian, .breakfast), (.malay, .breakfast), (.english, .breakfast): return "Breakfast"
        case (.turkish, .lunch): return TurkishLocalization.phrase("Lunch")
        case (.arabic, .lunch): return ArabicLocalization.phrase("Lunch")
        case (.indonesian, .lunch), (.malay, .lunch), (.english, .lunch): return "Lunch"
        case (.turkish, .dinner): return TurkishLocalization.phrase("Dinner")
        case (.arabic, .dinner): return ArabicLocalization.phrase("Dinner")
        case (.indonesian, .dinner), (.malay, .dinner), (.english, .dinner): return "Dinner"
        case (.uzbek, .breakfast): return "Nonushta"
        case (.uzbek, .lunch): return "Tushlik"
        case (.uzbek, .dinner): return "Kechki ovqat"
        case (.uzbekCyrillic, .breakfast): return "Нонушта"
        case (.uzbekCyrillic, .lunch): return "Тушлик"
        case (.uzbekCyrillic, .dinner): return "Кечки овқат"
        }
    }

    private var mealIncludedText: String {
        switch settings.language {
        case .russian: return "Включено · без доплаты"
        case .turkish: return TurkishLocalization.phrase("Included · no extra charge")
        case .arabic: return ArabicLocalization.phrase("Included · no extra charge")
        case .indonesian, .malay, .english: return "Included · no extra charge"
        case .uzbek: return "Kiritilgan · qo‘shimcha to‘lovsiz"
        case .uzbekCyrillic: return "Киритилган · қўшимча тўловсиз"
        }
    }

    private func optionalMealPriceText(_ price: Decimal) -> String {
        let amount = NSDecimalNumber(decimal: price).intValue
        switch settings.language {
        case .russian: return "$\(amount) · за человека / день"
        case .turkish: return TurkishLocalization.phrase("$\(amount) · per person / day")
        case .arabic: return ArabicLocalization.phrase("$\(amount) · per person / day")
        case .indonesian, .malay, .english: return "$\(amount) · per person / day"
        case .uzbek: return "$\(amount) · kishi / kun"
        case .uzbekCyrillic: return "$\(amount) · киши / кун"
        }
    }

    private var localizedMakkah: String {
        switch settings.language {
        case .russian: return "Мекка"
        case .turkish: return TurkishLocalization.phrase("Makkah")
        case .arabic: return ArabicLocalization.phrase("Makkah")
        case .indonesian, .malay, .english: return "Makkah"
        case .uzbek: return "Makka"
        case .uzbekCyrillic: return "Макка"
        }
    }

    private var localizedMadinah: String {
        switch settings.language {
        case .russian: return "Медина"
        case .turkish: return TurkishLocalization.phrase("Madinah")
        case .arabic: return ArabicLocalization.phrase("Madinah")
        case .indonesian, .malay, .english: return "Madinah"
        case .uzbek: return "Madina"
        case .uzbekCyrillic: return "Мадина"
        }
    }

    private func missingHotelCard(role: HotelSelectionRole) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 36, weight: .light))
            Text(role == .makkah ? FlowCopy.text(.makkahStay, settings.language) : FlowCopy.text(.madinahStay, settings.language))
                .font(.headline)
            NavigationLink {
                HotelSelectionView(role: role)
            } label: {
                Text(FlowCopy.text(.chooseHotel, settings.language))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IumrahSecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iumrahCard()
    }

    private func hotelImage(_ hotel: HotelSummary) -> some View {
        GeometryReader { proxy in
            HotelCachedImage(rawURL: hotel.coverImageURL)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

private struct SoftHotelActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 52)
            .iumrahGlass(
                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                interactive: true
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.90 : 1)
    }
}
