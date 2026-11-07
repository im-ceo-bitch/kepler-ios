import SwiftUI

struct FlightDateCalendarResult {
    let departure: Date
    let returnDate: Date
    let publishedSelection: CuratedPublishedFlightSelection?
}

struct FlightDateCalendarView: View {
    let trip: TripDraft
    let initialDeparture: Date
    let initialReturn: Date
    let publishedOnly: Bool
    let onApply: (FlightDateCalendarResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var departure: Date?
    @State private var returnDate: Date?
    @State private var publishedFlights: [CuratedFlightRecommendation] = []
    @State private var isLoading = false
    @State private var loadError = false
    @State private var showFlexibleWarning = false
    @State private var stage: Stage = .departure

    private enum Stage { case departure, `return` }

    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        return value
    }()

    init(
        trip: TripDraft,
        initialDeparture: Date,
        initialReturn: Date,
        publishedOnly: Bool = false,
        onApply: @escaping (FlightDateCalendarResult) -> Void
    ) {
        self.trip = trip
        self.initialDeparture = initialDeparture
        self.initialReturn = initialReturn
        self.publishedOnly = publishedOnly
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.iumrahPageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        stageSwitcher
                        routeSummary
                        availabilityCard
                        selectionSummary

                        ForEach(monthStarts, id: \.self) { month in
                            monthSection(month)
                        }

                        inventoryNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 126)
                }
                .scrollIndicators(.hidden)

                if showFlexibleWarning {
                    flexibleWarningOverlay
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        IumrahHaptics.selection()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(closeLabel)
                }

                ToolbarItem(placement: .principal) {
                    Image("IumrahFlightsCalendarLogo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .frame(width: 138, height: 30)
                        .accessibilityLabel("iumrah Flights")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .task { await loadPublishedFlights() }
        }
        .onAppear {
            departure = calendar.startOfDay(for: initialDeparture)
            returnDate = calendar.startOfDay(for: initialReturn)
            stage = .departure
        }
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(36)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(copy(.title))
                .font(IumrahType.screenTitle)
                .tracking(-0.5)
            Text(stage == .departure ? copy(.subtitleDeparture) : copy(.subtitleReturn))
                .font(IumrahType.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageSwitcher: some View {
        HStack(spacing: 10) {
            stageButton(.departure, title: copy(.outboundStageTitle), subtitle: departure.map(shortDateText) ?? copy(.notSelected))
            stageButton(.return, title: copy(.returnStageTitle), subtitle: returnDate.map(shortDateText) ?? copy(.notSelected), disabled: departure == nil)
        }
    }

    private func stageButton(_ step: Stage, title: String, subtitle: String, disabled: Bool = false) -> some View {
        let selected = stage == step
        return Button {
            guard !disabled else { return }
            stage = step
            IumrahHaptics.selection()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(IumrahType.regular(12, relativeTo: .caption))
                    .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.iumrahMuted)
                Text(subtitle)
                    .font(IumrahType.bold(15, relativeTo: .subheadline))
                    .foregroundStyle(selected ? Color.white : Color.iumrahInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .frame(height: 62)
            .background(selected ? Color.iumrahSignatureBlack : Color.iumrahCardBackground,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
            }
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
    }

    private var routeSummary: some View {
        HStack(spacing: 10) {
            routeCode(trip.originCode)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            routeCode(trip.outboundDestinationCode)
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            routeCode(trip.returnOriginCode)
            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            routeCode(trip.originCode)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private func routeCode(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .monospaced()
            .frame(maxWidth: .infinity)
    }

    private var availabilityCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.iumrahRaisedBackground)
                    .frame(width: 42, height: 42)
                Image(systemName: stage == .departure ? "airplane.departure" : "airplane.arrival")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.iumrahSignatureBlack)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stage == .departure ? copy(.chooseOutboundHintTitle) : copy(.chooseReturnHintTitle))
                    .font(.subheadline.weight(.bold))
                Text(isLoading ? copy(.loading) : (stage == .departure ? copy(.chooseOutboundHintBody) : copy(.chooseReturnHintBody)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if loadError {
                Button(copy(.retry)) {
                    Task { await loadPublishedFlights() }
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(Color.iumrahRaisedBackground, in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            selectionBadge(title: copy(.outboundStageTitle), value: departure.map(fullDateText) ?? copy(.notSelected), active: stage == .departure)
            selectionBadge(title: copy(.returnStageTitle), value: returnDate.map(fullDateText) ?? copy(.notSelected), active: stage == .return)
        }
    }

    private func selectionBadge(title: String, value: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(IumrahType.regular(11, relativeTo: .caption2))
                .foregroundStyle(Color.iumrahMuted)
            Text(value)
                .font(IumrahType.bold(14, relativeTo: .subheadline))
                .foregroundStyle(Color.iumrahInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .frame(height: 58)
        .background(active ? Color.iumrahRaisedBackground : Color.iumrahCardBackground,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(active ? 0.08 : 0.04), lineWidth: 1)
        }
    }

    private func monthSection(_ month: Date) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(monthTitle(month))
                .font(.system(size: 25, weight: .bold, design: .rounded))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                ForEach(weekdayTitles, id: \.self) { title in
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                ForEach(monthCells(month), id: \.id) { cell in
                    if let date = cell.date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 54)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.iumrahCardBackground,
                    in: RoundedRectangle(cornerRadius: IumrahDesign.cardRadius, style: .continuous))
    }

    private func dayCell(_ date: Date) -> some View {
        let day = calendar.startOfDay(for: date)
        let disabledByPast = day < calendar.startOfDay(for: Date())
        let available = isAvailableDay(day)
        let selectable = !disabledByPast && available
        let isDeparture = departure.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isReturn = returnDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let inRange = isInsideSelectedRange(day)

        return Button {
            guard selectable else { return }
            select(day)
        } label: {
            Text(String(calendar.component(.day, from: day)))
                .font(.system(size: 17, weight: (isDeparture || isReturn) ? .bold : .medium, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background {
                    if isDeparture || isReturn {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.iumrahSignatureBlack)
                    } else if inRange {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.iumrahSignatureBlack.opacity(0.10))
                    } else if selectable {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.iumrahRaisedBackground)
                    }
                }
                .foregroundStyle(
                    disabledByPast || !available
                    ? Color.secondary.opacity(0.28)
                    : ((isDeparture || isReturn) ? Color.white : Color.iumrahInk)
                )
                .overlay {
                    if selectable && !isDeparture && !isReturn && !inRange {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityHint(available ? copy(.availableAccessibility) : copy(.unavailableAccessibility))
    }

    private var inventoryNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(copy(.inventoryNote))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                departure = nil
                returnDate = nil
                stage = .departure
                IumrahHaptics.selection()
            } label: {
                Text(copy(.reset))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(width: 128, height: 58)
            }
            .buttonStyle(.plain)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }

            Button {
                applySelection()
            } label: {
                Text(copy(.chooseDates))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color.iumrahSignatureBlack, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!hasValidRange)
            .opacity(hasValidRange ? 1 : 0.42)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(Color.iumrahPageBackground)
        .overlay(alignment: .top) { Divider().opacity(0.14) }
    }

    private func applySelection() {
        guard let departure, let returnDate, returnDate > departure else { return }

        if let published = selectedPublishedSelection {
            IumrahHaptics.success()
            onApply(FlightDateCalendarResult(
                departure: departure,
                returnDate: returnDate,
                publishedSelection: published
            ))
            dismiss()
            return
        }

        guard !publishedOnly else {
            IumrahHaptics.error()
            return
        }

        IumrahHaptics.soft()
        showFlexibleWarning = true
    }

    private var flexibleWarningOverlay: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { showFlexibleWarning = false }

            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.13))
                        .frame(width: 54, height: 54)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(copy(.noDirectTitle))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(copy(.noDirectPopupBody))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showFlexibleWarning = false
                    departure = nil
                    returnDate = nil
                    stage = .departure
                    IumrahHaptics.selection()
                } label: {
                    Text(copy(.chooseDirectDates))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(Color.iumrahInk, in: RoundedRectangle(cornerRadius: 19, style: .continuous))

                Button {
                    guard let departure, let returnDate else { return }
                    IumrahHaptics.success()
                    onApply(FlightDateCalendarResult(
                        departure: departure,
                        returnDate: returnDate,
                        publishedSelection: nil
                    ))
                    dismiss()
                } label: {
                    Text(copy(.continueFlexible))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .padding(22)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.14), radius: 34, y: 16)
            .padding(.horizontal, 22)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .zIndex(20)
    }

    private var hasValidRange: Bool {
        guard let departure, let returnDate else { return false }
        return returnDate > departure
    }

    private var selectedPublishedSelection: CuratedPublishedFlightSelection? {
        guard let departure, let returnDate else { return nil }
        return publishedSelection(departure: departure, returnDate: returnDate)
    }

    private func publishedSelection(departure: Date, returnDate: Date) -> CuratedPublishedFlightSelection? {
        let outKey = dayKey(departure)
        let returnKey = dayKey(returnDate)

        if let complete = completeRecommendations.first(where: {
            $0.outboundDate == outKey && $0.inboundDate == returnKey
        }) {
            return CuratedPublishedFlightSelection(completeID: complete.id)
        }

        guard let outbound = oneWayOutboundRecommendations.first(where: { $0.outboundDate == outKey }),
              let inbound = oneWayReturnRecommendations.first(where: { $0.outboundDate == returnKey }) else {
            return nil
        }
        return CuratedPublishedFlightSelection(outboundID: outbound.id, returnID: inbound.id)
    }

    private var completeRecommendations: [CuratedFlightRecommendation] {
        publishedFlights.filter { recommendation in
            guard let inbound = recommendation.inbound else { return false }
            return recommendation.outbound.origin == trip.originCode &&
                recommendation.outbound.destination == trip.outboundDestinationCode &&
                inbound.origin == trip.returnOriginCode &&
                inbound.destination == trip.originCode &&
                recommendation.inboundDate != nil
        }
    }

    private var oneWayOutboundRecommendations: [CuratedFlightRecommendation] {
        publishedFlights.filter { recommendation in
            recommendation.inbound == nil &&
            recommendation.outbound.origin == trip.originCode &&
            recommendation.outbound.destination == trip.outboundDestinationCode
        }
    }

    private var oneWayReturnRecommendations: [CuratedFlightRecommendation] {
        publishedFlights.filter { recommendation in
            recommendation.inbound == nil &&
            recommendation.outbound.origin == trip.returnOriginCode &&
            recommendation.outbound.destination == trip.originCode
        }
    }

    private var recommendedOutboundDateKeys: Set<String> {
        Set(completeRecommendations.map(\.outboundDate) + oneWayOutboundRecommendations.map(\.outboundDate))
    }

    private func recommendedReturnDateKeys(for outbound: Date) -> Set<String> {
        let outKey = dayKey(outbound)
        var keys = Set(completeRecommendations.compactMap { recommendation -> String? in
            guard recommendation.outboundDate == outKey else { return nil }
            return recommendation.inboundDate
        })
        if oneWayOutboundRecommendations.contains(where: { $0.outboundDate == outKey }) {
            for recommendation in oneWayReturnRecommendations {
                if let date = CuratedFlightRecommendationService.date(recommendation.outboundDate), date > outbound {
                    keys.insert(recommendation.outboundDate)
                }
            }
        }
        return keys
    }

    private func isAvailableDay(_ day: Date) -> Bool {
        if publishedOnly {
            switch stage {
            case .departure:
                return recommendedOutboundDateKeys.contains(dayKey(day))
            case .return:
                guard let departure else { return false }
                return recommendedReturnDateKeys(for: departure).contains(dayKey(day))
            }
        }

        if stage == .return, let departure {
            return day > departure
        }
        return true
    }

    private func select(_ date: Date) {
        switch stage {
        case .departure:
            departure = date
            returnDate = nil
            stage = .return
        case .return:
            guard let departure else {
                self.departure = date
                stage = .return
                IumrahHaptics.selection()
                return
            }
            if date <= departure {
                self.departure = date
                returnDate = nil
                stage = .return
            } else {
                returnDate = date
            }
        }
        IumrahHaptics.selection()
    }

    private func isInsideSelectedRange(_ date: Date) -> Bool {
        guard let departure, let returnDate else { return false }
        return date > departure && date < returnDate
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: date).capitalized(with: locale)
    }

    private var weekdayTitles: [String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        var symbols = formatter.veryShortStandaloneWeekdaySymbols
            ?? formatter.veryShortWeekdaySymbols
            ?? ["S", "M", "T", "W", "T", "F", "S"]
        if calendar.firstWeekday == 2, !symbols.isEmpty {
            let first = symbols.removeFirst()
            symbols.append(first)
        }
        return symbols
    }

    private var monthStarts: [Date] {
        let today = calendar.startOfDay(for: Date())
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        return (0..<6).compactMap { calendar.date(byAdding: .month, value: $0, to: current) }
    }

    private struct MonthCell: Identifiable {
        let id: String
        let date: Date?
    }

    private func monthCells(_ month: Date) -> [MonthCell] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var cells: [MonthCell] = (0..<leading).map { MonthCell(id: "blank-\(month.timeIntervalSince1970)-\($0)", date: nil) }
        cells += range.compactMap { day -> MonthCell? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: first) else { return nil }
            return MonthCell(id: dayKey(date), date: date)
        }
        return cells
    }

    private func loadPublishedFlights() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = false
        defer { isLoading = false }
        do {
            let start = calendar.startOfDay(for: Date())
            let last = monthStarts.last ?? start
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: last) ?? last
            let days = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 180)
            publishedFlights = try await CuratedFlightRecommendationService.shared.load(trip: trip, from: Date(), days: min(365, days + 2))
        } catch {
            publishedFlights = []
            loadError = true
        }
    }

    private var locale: Locale {
        switch settings.language {
        case .english: return Locale(identifier: "en_US")
        case .russian: return Locale(identifier: "ru_RU")
        case .arabic: return Locale(identifier: "ar_SA")
        case .turkish: return Locale(identifier: "tr_TR")
        case .indonesian: return Locale(identifier: "id_ID")
        case .malay: return Locale(identifier: "ms_MY")
        case .uzbek: return Locale(identifier: "uz_Latn_UZ")
        case .uzbekCyrillic: return Locale(identifier: "uz_Cyrl_UZ")
        }
    }

    private var closeLabel: String {
        switch settings.language {
        case .russian: return "Закрыть"
        case .english: return "Close"
        case .arabic: return "إغلاق"
        case .turkish: return "Kapat"
        case .indonesian: return "Tutup"
        case .malay: return "Tutup"
        case .uzbek: return "Yopish"
        case .uzbekCyrillic: return "Ёпиш"
        }
    }

    private func shortDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    private func fullDateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).locale(locale))
    }

    private enum CopyKey {
        case title, subtitleDeparture, subtitleReturn
        case outboundStageTitle, returnStageTitle, notSelected
        case chooseOutboundHintTitle, chooseOutboundHintBody
        case chooseReturnHintTitle, chooseReturnHintBody
        case loading, retry, inventoryNote
        case reset, chooseDates
        case noDirectTitle, noDirectPopupBody, chooseDirectDates, continueFlexible
        case availableAccessibility, unavailableAccessibility
    }

    private func copy(_ key: CopyKey) -> String {
        switch (settings.language, key) {
        case (.russian, .title): return "Выберите даты"
        case (.russian, .subtitleDeparture): return "Сначала выберите билет туда. Доступны только даты, где есть опубликованный рейс."
        case (.russian, .subtitleReturn): return "Теперь выберите обратный билет. Показываем только даты, совместимые с выбранным вылетом."
        case (.russian, .outboundStageTitle): return "Туда"
        case (.russian, .returnStageTitle): return "Обратно"
        case (.russian, .notSelected): return "Не выбрано"
        case (.russian, .chooseOutboundHintTitle): return "Выберите вылет"
        case (.russian, .chooseOutboundHintBody): return "Светлые даты доступны для выбора. Дни без опубликованного рейса недоступны."
        case (.russian, .chooseReturnHintTitle): return "Выберите обратный рейс"
        case (.russian, .chooseReturnHintBody): return "После выбора вылета оставляем только подходящие даты возврата."
        case (.russian, .loading): return "Проверяем опубликованные прямые рейсы…"
        case (.russian, .retry): return "Обновить"
        case (.russian, .inventoryNote): return "Доступность строится по опубликованным рейсам в базе iumrah. После выбора туда и обратно между датами появляется лента диапазона."
        case (.russian, .reset): return "Сбросить"
        case (.russian, .chooseDates): return "Продолжить"
        case (.russian, .noDirectTitle): return "На эти даты нет прямых рейсов"
        case (.russian, .noDirectPopupBody): return "В iumrah сейчас нет опубликованной пары прямых рейсов на выбранные даты. При гибком поиске могут появиться варианты с 1–2 пересадками и более высокой ценой, которая увеличит итоговую стоимость вашего пакета."
        case (.russian, .chooseDirectDates): return "Выбрать даты с прямым рейсом"
        case (.russian, .continueFlexible): return "Продолжить с гибкими датами"
        case (.russian, .availableAccessibility): return "Дата доступна"
        case (.russian, .unavailableAccessibility): return "Дата недоступна"

        case (.english, .title): return "Choose your dates"
        case (.english, .subtitleDeparture): return "Choose the outbound flight first. Only dates with published flights are available."
        case (.english, .subtitleReturn): return "Now choose the return flight. Only dates compatible with your outbound choice remain available."
        case (.english, .outboundStageTitle): return "Outbound"
        case (.english, .returnStageTitle): return "Return"
        case (.english, .notSelected): return "Not selected"
        case (.english, .chooseOutboundHintTitle): return "Choose departure"
        case (.english, .chooseOutboundHintBody): return "Light dates are available. Days without a published flight are disabled."
        case (.english, .chooseReturnHintTitle): return "Choose return"
        case (.english, .chooseReturnHintBody): return "After selecting your outbound flight, only matching return dates stay available."
        case (.english, .loading): return "Checking published direct flights…"
        case (.english, .retry): return "Refresh"
        case (.english, .inventoryNote): return "Availability comes from published flights in the iumrah database. After selecting both dates, the range is highlighted across the calendar."
        case (.english, .reset): return "Reset"
        case (.english, .chooseDates): return "Continue"
        case (.english, .noDirectTitle): return "No direct flights on these dates"
        case (.english, .noDirectPopupBody): return "iumrah currently has no published direct-flight pair for these dates. Flexible search may return one- or two-stop options at a higher fare, increasing your final package total."
        case (.english, .chooseDirectDates): return "Choose direct-flight dates"
        case (.english, .continueFlexible): return "Continue with flexible dates"
        case (.english, .availableAccessibility): return "Date available"
        case (.english, .unavailableAccessibility): return "Date unavailable"

        case (.arabic, .title): return "اختر التواريخ"
        case (.arabic, .subtitleDeparture): return "اختر رحلة الذهاب أولاً. تتوفر فقط التواريخ التي لديها رحلات منشورة."
        case (.arabic, .subtitleReturn): return "الآن اختر رحلة العودة. نعرض فقط التواريخ المتوافقة مع رحلة الذهاب التي اخترتها."
        case (.arabic, .outboundStageTitle): return "الذهاب"
        case (.arabic, .returnStageTitle): return "العودة"
        case (.arabic, .notSelected): return "غير محدد"
        case (.arabic, .chooseOutboundHintTitle): return "اختر الذهاب"
        case (.arabic, .chooseOutboundHintBody): return "التواريخ الفاتحة متاحة. الأيام التي لا تحتوي على رحلة منشورة غير متاحة."
        case (.arabic, .chooseReturnHintTitle): return "اختر العودة"
        case (.arabic, .chooseReturnHintBody): return "بعد اختيار الذهاب، تبقى فقط تواريخ العودة المناسبة."
        case (.arabic, .loading): return "جارٍ التحقق من الرحلات المباشرة المنشورة…"
        case (.arabic, .retry): return "تحديث"
        case (.arabic, .inventoryNote): return "تعتمد الإتاحة على الرحلات المنشورة في قاعدة بيانات iumrah. بعد اختيار تاريخي الذهاب والعودة، يظهر شريط النطاق في التقويم."
        case (.arabic, .reset): return "إعادة تعيين"
        case (.arabic, .chooseDates): return "متابعة"
        case (.arabic, .noDirectTitle): return "لا توجد رحلات مباشرة في هذه التواريخ"
        case (.arabic, .noDirectPopupBody): return "لا توجد حالياً لدى iumrah رحلة مباشرة منشورة مناسبة لهذه التواريخ. قد يُظهر البحث المرن خيارات بتوقف واحد أو توقفين وسعر أعلى، ما يزيد إجمالي سعر باقتك."
        case (.arabic, .chooseDirectDates): return "اختر تواريخ برحلات مباشرة"
        case (.arabic, .continueFlexible): return "متابعة مع تواريخ مرنة"
        case (.arabic, .availableAccessibility): return "التاريخ متاح"
        case (.arabic, .unavailableAccessibility): return "التاريخ غير متاح"

        case (.turkish, .title): return "Tarihleri seçin"
        case (.turkish, .subtitleDeparture): return "Önce gidiş biletini seçin. Yalnızca yayımlanmış uçuş olan tarihler kullanılabilir."
        case (.turkish, .subtitleReturn): return "Şimdi dönüş biletini seçin. Sadece seçtiğiniz gidiş uçuşuyla uyumlu tarihler kullanılabilir."
        case (.turkish, .outboundStageTitle): return "Gidiş"
        case (.turkish, .returnStageTitle): return "Dönüş"
        case (.turkish, .notSelected): return "Seçilmedi"
        case (.turkish, .chooseOutboundHintTitle): return "Gidişi seçin"
        case (.turkish, .chooseOutboundHintBody): return "Açık renkli tarihler seçilebilir. Yayımlanmış uçuş olmayan günler pasiftir."
        case (.turkish, .chooseReturnHintTitle): return "Dönüşü seçin"
        case (.turkish, .chooseReturnHintBody): return "Gidiş seçildikten sonra yalnızca uygun dönüş tarihleri açık kalır."
        case (.turkish, .loading): return "Yayımlanmış direkt uçuşlar kontrol ediliyor…"
        case (.turkish, .retry): return "Yenile"
        case (.turkish, .inventoryNote): return "Uygunluk, iumrah veritabanındaki yayımlanmış uçuşlara göre belirlenir. Her iki tarih seçilince aralık takvimde vurgulanır."
        case (.turkish, .reset): return "Sıfırla"
        case (.turkish, .chooseDates): return "Devam"
        case (.turkish, .noDirectTitle): return "Bu tarihlerde direkt uçuş yok"
        case (.turkish, .noDirectPopupBody): return "iumrah şu anda bu tarihler için yayımlanmış direkt bir uçuş çifti bulamadı. Esnek arama bir veya iki aktarmalı ve daha pahalı seçenekler döndürebilir; bu da nihai paket fiyatınızı artırır."
        case (.turkish, .chooseDirectDates): return "Direkt uçuş tarihlerini seç"
        case (.turkish, .continueFlexible): return "Esnek tarihlerle devam et"
        case (.turkish, .availableAccessibility): return "Tarih uygun"
        case (.turkish, .unavailableAccessibility): return "Tarih uygun değil"

        case (.indonesian, .title): return "Pilih tanggal"
        case (.indonesian, .subtitleDeparture): return "Pilih tiket berangkat terlebih dahulu. Hanya tanggal dengan penerbangan terbit yang tersedia."
        case (.indonesian, .subtitleReturn): return "Sekarang pilih tiket pulang. Hanya tanggal yang cocok dengan pilihan berangkat Anda yang tersedia."
        case (.indonesian, .outboundStageTitle): return "Berangkat"
        case (.indonesian, .returnStageTitle): return "Pulang"
        case (.indonesian, .notSelected): return "Belum dipilih"
        case (.indonesian, .chooseOutboundHintTitle): return "Pilih keberangkatan"
        case (.indonesian, .chooseOutboundHintBody): return "Tanggal terang tersedia untuk dipilih. Hari tanpa penerbangan terbit dinonaktifkan."
        case (.indonesian, .chooseReturnHintTitle): return "Pilih kepulangan"
        case (.indonesian, .chooseReturnHintBody): return "Setelah memilih keberangkatan, hanya tanggal pulang yang cocok yang tetap tersedia."
        case (.indonesian, .loading): return "Memeriksa penerbangan langsung yang dipublikasikan…"
        case (.indonesian, .retry): return "Muat ulang"
        case (.indonesian, .inventoryNote): return "Ketersediaan diambil dari penerbangan yang dipublikasikan di basis data iumrah. Setelah dua tanggal dipilih, rentangnya disorot di kalender."
        case (.indonesian, .reset): return "Atur ulang"
        case (.indonesian, .chooseDates): return "Lanjutkan"
        case (.indonesian, .noDirectTitle): return "Tidak ada penerbangan langsung pada tanggal ini"
        case (.indonesian, .noDirectPopupBody): return "Saat ini iumrah tidak memiliki pasangan penerbangan langsung terpublikasi untuk tanggal yang dipilih. Pencarian fleksibel dapat menampilkan opsi dengan 1–2 transit dan harga lebih tinggi, sehingga total paket Anda meningkat."
        case (.indonesian, .chooseDirectDates): return "Pilih tanggal penerbangan langsung"
        case (.indonesian, .continueFlexible): return "Lanjutkan dengan tanggal fleksibel"
        case (.indonesian, .availableAccessibility): return "Tanggal tersedia"
        case (.indonesian, .unavailableAccessibility): return "Tanggal tidak tersedia"

        case (.malay, .title): return "Pilih tarikh"
        case (.malay, .subtitleDeparture): return "Pilih tiket pergi dahulu. Hanya tarikh dengan penerbangan diterbitkan tersedia."
        case (.malay, .subtitleReturn): return "Sekarang pilih tiket balik. Hanya tarikh yang serasi dengan pilihan pergi anda kekal tersedia."
        case (.malay, .outboundStageTitle): return "Pergi"
        case (.malay, .returnStageTitle): return "Balik"
        case (.malay, .notSelected): return "Belum dipilih"
        case (.malay, .chooseOutboundHintTitle): return "Pilih penerbangan pergi"
        case (.malay, .chooseOutboundHintBody): return "Tarikh cerah tersedia untuk dipilih. Hari tanpa penerbangan diterbitkan dinyahaktifkan."
        case (.malay, .chooseReturnHintTitle): return "Pilih penerbangan balik"
        case (.malay, .chooseReturnHintBody): return "Selepas memilih pergi, hanya tarikh balik yang sepadan akan kekal tersedia."
        case (.malay, .loading): return "Sedang menyemak penerbangan terus yang diterbitkan…"
        case (.malay, .retry): return "Muat semula"
        case (.malay, .inventoryNote): return "Ketersediaan datang daripada penerbangan yang diterbitkan dalam pangkalan data iumrah. Selepas kedua-dua tarikh dipilih, julat akan diserlahkan pada kalendar."
        case (.malay, .reset): return "Tetapkan semula"
        case (.malay, .chooseDates): return "Teruskan"
        case (.malay, .noDirectTitle): return "Tiada penerbangan terus pada tarikh ini"
        case (.malay, .noDirectPopupBody): return "Buat masa ini iumrah tidak mempunyai pasangan penerbangan terus yang diterbitkan untuk tarikh yang dipilih. Carian fleksibel mungkin memaparkan pilihan 1–2 hentian pada tambang lebih tinggi, sekali gus menaikkan jumlah pakej anda."
        case (.malay, .chooseDirectDates): return "Pilih tarikh penerbangan terus"
        case (.malay, .continueFlexible): return "Teruskan dengan tarikh fleksibel"
        case (.malay, .availableAccessibility): return "Tarikh tersedia"
        case (.malay, .unavailableAccessibility): return "Tarikh tidak tersedia"

        case (.uzbek, .title): return "Sanalarni tanlang"
        case (.uzbek, .subtitleDeparture): return "Avval ketish reysini tanlang. Faqat e’lon qilingan reys bor sanalar ochiq."
        case (.uzbek, .subtitleReturn): return "Endi qaytish reysini tanlang. Faqat tanlangan ketish sanasiga mos qaytish kunlari ochiq qoladi."
        case (.uzbek, .outboundStageTitle): return "Ketish"
        case (.uzbek, .returnStageTitle): return "Qaytish"
        case (.uzbek, .notSelected): return "Tanlanmagan"
        case (.uzbek, .chooseOutboundHintTitle): return "Ketish sanasini tanlang"
        case (.uzbek, .chooseOutboundHintBody): return "Yorug‘ kunlar tanlash uchun ochiq. E’lon qilingan reys bo‘lmagan kunlar yopiq."
        case (.uzbek, .chooseReturnHintTitle): return "Qaytish sanasini tanlang"
        case (.uzbek, .chooseReturnHintBody): return "Ketish tanlangandan so‘ng faqat mos qaytish sanalari ochiq qoladi."
        case (.uzbek, .loading): return "E’lon qilingan to‘g‘ridan-to‘g‘ri reyslar tekshirilmoqda…"
        case (.uzbek, .retry): return "Yangilash"
        case (.uzbek, .inventoryNote): return "Mavjudlik iumrah bazasidagi e’lon qilingan reyslarga tayanadi. Ikki sana tanlangach, ularning oralig‘i kalendarda lenta bo‘lib ko‘rinadi."
        case (.uzbek, .reset): return "Tozalash"
        case (.uzbek, .chooseDates): return "Davom etish"
        case (.uzbek, .noDirectTitle): return "Bu sanalarda to‘g‘ridan-to‘g‘ri reys yo‘q"
        case (.uzbek, .noDirectPopupBody): return "Hozir iumrah bazasida tanlangan sanalar uchun e’lon qilingan to‘g‘ridan-to‘g‘ri reys juftligi yo‘q. Moslashuvchan qidiruv 1–2 ta transferli va qimmatroq variantlarni topishi mumkin; bu yakuniy paket narxini oshiradi."
        case (.uzbek, .chooseDirectDates): return "To‘g‘ri reysli sanalarni tanlash"
        case (.uzbek, .continueFlexible): return "Moslashuvchan sanalar bilan davom etish"
        case (.uzbek, .availableAccessibility): return "Sana mavjud"
        case (.uzbek, .unavailableAccessibility): return "Sana mavjud emas"

        case (.uzbekCyrillic, .title): return "Саналарни танланг"
        case (.uzbekCyrillic, .subtitleDeparture): return "Аввал кетиш рейсини танланг. Фақат эълон қилинган рейс бор саналар очиқ."
        case (.uzbekCyrillic, .subtitleReturn): return "Энди қайтиш рейсини танланг. Фақат танланган кетиш санасига мос қайтиш кунлари очиқ қолади."
        case (.uzbekCyrillic, .outboundStageTitle): return "Кетиш"
        case (.uzbekCyrillic, .returnStageTitle): return "Қайтиш"
        case (.uzbekCyrillic, .notSelected): return "Танланмаган"
        case (.uzbekCyrillic, .chooseOutboundHintTitle): return "Кетиш санасини танланг"
        case (.uzbekCyrillic, .chooseOutboundHintBody): return "Ёруғ кунлар танлаш учун очиқ. Эълон қилинган рейс бўлмаган кунлар ёпиқ."
        case (.uzbekCyrillic, .chooseReturnHintTitle): return "Қайтиш санасини танланг"
        case (.uzbekCyrillic, .chooseReturnHintBody): return "Кетиш танлангандан сўнг фақат мос қайтиш саналар очиқ қолади."
        case (.uzbekCyrillic, .loading): return "Эълон қилинган тўғридан-тўғри рейслар текширилмоқда…"
        case (.uzbekCyrillic, .retry): return "Янгилаш"
        case (.uzbekCyrillic, .inventoryNote): return "Мавжудлик iumrah базасидаги эълон қилинган рейсларга таянади. Икки сана танлангач, уларнинг оралиғи календарда лента бўлиб кўринади."
        case (.uzbekCyrillic, .reset): return "Тозалаш"
        case (.uzbekCyrillic, .chooseDates): return "Давом этиш"
        case (.uzbekCyrillic, .noDirectTitle): return "Бу саналарда тўғридан-тўғри рейс йўқ"
        case (.uzbekCyrillic, .noDirectPopupBody): return "Ҳозир iumrah базасида танланган саналар учун эълон қилинган тўғридан-тўғри рейс жуфтлиги йўқ. Мослашувчан қидирув 1–2 та трансферли ва қимматроқ вариантларни топиши мумкин; бу якуний пакет нархини оширади."
        case (.uzbekCyrillic, .chooseDirectDates): return "Тўғри рейсли саналарни танлаш"
        case (.uzbekCyrillic, .continueFlexible): return "Мослашувчан саналар билан давом этиш"
        case (.uzbekCyrillic, .availableAccessibility): return "Сана мавжуд"
        case (.uzbekCyrillic, .unavailableAccessibility): return "Сана мавжуд эмас"
        }
    }
}
