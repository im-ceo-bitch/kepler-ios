import SwiftUI

// MARK: - Shared presentation, deliberately not a booking/pricing model

/// One read-only visual representation for the Flights tab and the flight-first
/// configurator. Never infer missing supplier facts from another data source.
struct IumrahOTAFlightLeg: Hashable {
    let origin: String
    let destination: String
    let departureAt: String
    let arrivalAt: String
    let airlineCode: String
    let flightNumber: String
}

enum IumrahOTAFlightSource {
    case published
    case cachedSearch
}

struct IumrahOTAFlightSnapshot {
    let id: String
    let airline: String
    let airlineCode: String
    let flightNumber: String
    let origin: String
    let destination: String
    let departureAt: String
    let arrivalAt: String?
    let durationMinutes: Int
    let stops: Int
    let priceUSD: Double?
    let source: IumrahOTAFlightSource
    let cabin: String?
    /// Populated only from a verified provider itinerary, or an existing
    /// published one-segment flight with known departure AND arrival.
    let segments: [IumrahOTAFlightLeg]

    /// Display-only fallback from the V5 flight clock. Never written to a booking or supplier model.
    var arrivalInfo: IumrahFlightClock.Arrival? {
        IumrahFlightClock.arrival(actual: arrivalAt, departure: departureAt,
            duration: durationMinutes, origin: origin, destination: destination)
    }

    var hasUsablePrice: Bool {
        guard let priceUSD else { return false }
        return priceUSD.isFinite && priceUSD > 0
    }

    var isConnectionDetailComplete: Bool {
        !segments.isEmpty && segments.count == max(0, stops) + 1
    }
}

private enum IumrahOTAText {
    static func localized(_ lang: AppSettingsStore.Language, _ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch lang {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        default: return en
        }
    }

    /// Convert offset/Z timestamps to the airport's local time. Offset-free
    /// supplier strings are already local and remain untouched.
    private static func absoluteDate(_ raw: String) -> Date? {
        let hasZone = raw.hasSuffix("Z") || raw.range(of: "[+-][0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil
        guard hasZone else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    static func clock(_ iso: String?, airportCode: String? = nil) -> String {
        guard let iso else { return "—" }
        if let airportCode,
           let timeZone = FlightReferenceCatalog.timeZone(for: airportCode),
           let instant = absoluteDate(iso) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: instant)
        }
        guard let divider = iso.firstIndex(of: "T") else { return "—" }
        let start = iso.index(after: divider)
        let prefix = String(iso[start...].prefix(5))
        guard prefix.count == 5,
              prefix[prefix.index(prefix.startIndex, offsetBy: 2)] == ":",
              let hour = Int(prefix.prefix(2)), (0...23).contains(hour),
              let minute = Int(prefix.suffix(2)), (0...59).contains(minute) else { return "—" }
        return prefix
    }

    private static func localDay(_ raw: String, airportCode: String?) -> String {
        if let airportCode,
           let zone = FlightReferenceCatalog.timeZone(for: airportCode),
           let instant = absoluteDate(raw) {
            let display = DateFormatter()
            display.locale = Locale(identifier: "en_US_POSIX")
            display.timeZone = zone
            display.dateFormat = "yyyy-MM-dd"
            return display.string(from: instant)
        }
        return String(raw.prefix(10))
    }

    static func city(_ code: String) -> String {
        FlightReferenceCatalog.airport(code.uppercased())?.city ?? code.uppercased()
    }

    static func airport(_ code: String) -> String? {
        guard let value = FlightReferenceCatalog.airport(code.uppercased())?.name,
              !value.isEmpty else { return nil }
        return value
    }

    static func date(_ iso: String, language: AppSettingsStore.Language, airportCode: String? = nil) -> String {
        let day = localDay(iso, airportCode: airportCode)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: day) else { return day }
        let display = DateFormatter()
        display.locale = Locale(identifier: language.localeIdentifier)
        display.timeZone = TimeZone(secondsFromGMT: 0)
        display.setLocalizedDateFormatFromTemplate("d MMM, EEE")
        return display.string(from: parsed)
    }

    static func nextDay(_ departure: String, _ arrival: String?, origin: String, destination: String) -> String? {
        guard let arrival, departure.count >= 10, arrival.count >= 10 else { return nil }
        let from = localDay(departure, airportCode: origin), to = localDay(arrival, airportCode: destination)
        // Date labels are local in their respective airports; never derive
        // a landing time from duration alone.
        guard to > from else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let a = formatter.date(from: from), let b = formatter.date(from: to),
              let days = Calendar(identifier: .gregorian).dateComponents([.day], from: a, to: b).day,
              days > 0 else { return nil }
        return "+\(days)"
    }

    static func duration(_ value: Int, _ language: AppSettingsStore.Language) -> String {
        guard value > 0 else { return localized(language, "Время уточняется", "Duration pending", "Vaqt aniqlanmoqda", "Вақт аниқланмоқда") }
        let hours = value / 60, minutes = value % 60
        switch language {
        case .russian: return "\(hours) ч \(minutes) мин"
        case .uzbek: return "\(hours) soat \(minutes) daq"
        case .uzbekCyrillic: return "\(hours) соат \(minutes) дақ"
        default: return "\(hours)h \(minutes)m"
        }
    }

    static func stopLabel(_ stops: Int, _ language: AppSettingsStore.Language) -> String {
        if stops == 0 { return localized(language, "Прямой", "Non-stop", "To‘g‘ridan-to‘g‘ri", "Тўғридан-тўғри") }
        return localized(language, "Пересадок: \(stops)", "\(stops) stop(s)", "\(stops) ta almashish", "\(stops) та алмашиш")
    }

    static func price(_ amount: Double) -> String {
        "$" + amount.formatted(.number.precision(.fractionLength(0)))
    }

    static func connectionMinutes(_ lhs: IumrahOTAFlightLeg, _ rhs: IumrahOTAFlightLeg) -> Int? {
        guard lhs.destination.uppercased() == rhs.origin.uppercased() else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func parse(_ raw: String) -> Date? {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        guard let a = parse(lhs.arrivalAt), let b = parse(rhs.departureAt), b >= a else { return nil }
        return Int(b.timeIntervalSince(a) / 60)
    }
}

// MARK: - Catalog card

struct IumrahOTAFlightCard: View {
    let flight: IumrahOTAFlightSnapshot
    let language: AppSettingsStore.Language
    var isSelected = false

    private func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahOTAText.localized(language, ru, en, uz, cy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .center, spacing: 11) {
                AirlineLogoView(airlineCode: flight.airlineCode, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(flight.airline.isEmpty ? flight.airlineCode : flight.airline)
                        .font(IumrahType.bold(17))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        let number = flight.flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !number.isEmpty {
                            Text(number)
                                .font(IumrahType.regular(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                        if !number.isEmpty { Text("·").foregroundStyle(.tertiary) }
                        Text(IumrahOTAText.date(flight.departureAt, language: language, airportCode: flight.origin))
                            .font(IumrahType.regular(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary)
                        .accessibilityLabel(t("Выбран", "Selected", "Tanlangan", "Танланган"))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                terminalBlock(code: flight.origin, time: IumrahOTAText.clock(flight.departureAt, airportCode: flight.origin), isArrival: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: 7) {
                    Text(flight.durationMinutes > 0 ? IumrahOTAText.duration(flight.durationMinutes, language) : " ")
                        .font(IumrahType.regular(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 3) {
                        Capsule().fill(Color.primary.opacity(0.22)).frame(height: 1)
                        if flight.stops > 0 {
                            ForEach(0..<max(0, min(flight.stops, 2)), id: \.self) { _ in
                                Circle().fill(Color.primary.opacity(0.55)).frame(width: 5, height: 5)
                                Capsule().fill(Color.primary.opacity(0.22)).frame(height: 1)
                            }
                        }
                        Image(systemName: "airplane")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.75))
                    }
                    Text(IumrahOTAText.stopLabel(flight.stops, language))
                        .font(IumrahType.regular(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                terminalBlock(code: flight.destination, time: flight.arrivalInfo?.time ?? "—", isArrival: true, estimated: flight.arrivalInfo?.estimated ?? false)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(flight.source == .cachedSearch
                         ? t("Цена из кэша", "Cached fare", "Keshdagi narx", "Кешдаги нарх")
                         : t("Опубликованный рейс", "Published flight", "E’lon qilingan reys", "Эълон қилинган рейс"))
                        .font(IumrahType.regular(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)

                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    if flight.hasUsablePrice, let price = flight.priceUSD {
                        Text(IumrahOTAText.price(price))
                            .font(IumrahType.bold(25, relativeTo: .title3))
                            .monospacedDigit()
                        Text(t("за пассажира · ориентир", "per traveler · indicative", "yo‘lovchiga · taxminiy", "йўловчига · тахминий"))
                            .font(IumrahType.regular(10, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(t("Посмотреть тариф", "View fare", "Tarifni ko‘rish", "Тарифни кўриш"))
                            .font(IumrahType.bold(13, relativeTo: .subheadline))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }
        .padding(16)
        .background(IumrahFlightPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isSelected ? Color.primary.opacity(0.72) : Color.primary.opacity(0.075),
                              lineWidth: isSelected ? 1.5 : 0.75)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(t("Открыть подробности перелёта", "Open flight details", "Reys tafsilotlari", "Рейс тафсилотлари"))
    }

    private func terminalBlock(code: String, time: String, isArrival: Bool, estimated: Bool = false) -> some View {
        VStack(alignment: isArrival ? .trailing : .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if isArrival { Spacer(minLength: 0) }
                Text(time)
                    .font(IumrahType.bold(28, relativeTo: .title2))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                if isArrival, let day = IumrahOTAText.nextDay(flight.departureAt, flight.arrivalAt, origin: flight.origin, destination: flight.destination) {
                    Text(day)
                        .font(IumrahType.bold(10, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                }
                if !isArrival { Spacer(minLength: 0) }
            }
            Text(code.uppercased())
                .font(IumrahType.bold(15, relativeTo: .headline))
            Text(IumrahOTAText.city(code))
                .font(IumrahType.regular(11, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if estimated {
                Text(t("Расчётное", "Estimated", "Hisoblangan", "Ҳисобланган"))
                    .font(IumrahType.regular(10, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Full OTA flight detail, shared by both entry points

struct IumrahOTAFlightDetailPage: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let flight: IumrahOTAFlightSnapshot
    let language: AppSettingsStore.Language
    var actionTitle: String? = nil
    var onChoose: (() -> Void)? = nil
    var externalURL: URL? = nil
    var dismissAfterChoose = true

    private func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahOTAText.localized(language, ru, en, uz, cy)
    }

    private var legs: [IumrahPremiumFlightLeg] {
        if flight.isConnectionDetailComplete {
            return flight.segments.map { leg in
                IumrahPremiumFlightLeg(airline: FlightReferenceCatalog.airlineName(code: leg.airlineCode, fallback: leg.airlineCode), airlineCode: leg.airlineCode, number: leg.flightNumber, origin: leg.origin, destination: leg.destination, departure: leg.departureAt, arrival: leg.arrivalAt, duration: 0, stops: 0, cabin: flight.cabin)
            }
        }
        return [IumrahPremiumFlightLeg(airline: flight.airline, airlineCode: flight.airlineCode, number: flight.flightNumber, origin: flight.origin, destination: flight.destination, departure: flight.departureAt, arrival: flight.arrivalAt, duration: flight.durationMinutes, stops: flight.stops, cabin: flight.cabin)]
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                    if index > 0, flight.segments.indices.contains(index) { connectionRow(previous: flight.segments[index - 1], current: flight.segments[index]) }
                    IumrahPremiumFlightDetail(leg: leg, language: language, pageHeroInset: index == 0 ? IumrahDesign.pagePadding : nil)
                }
                if flight.hasUsablePrice, let price = flight.priceUSD {
                    Text(t("Ориентировочный тариф · ", "Indicative fare · ", "Taxminiy tarif · ", "Тахминий тариф · ") + IumrahOTAText.price(price)).font(IumrahType.bold(18))
                }
                Text(t("Перед оплатой подтверждаются цена, багаж и наличие мест.", "Final fare, baggage and availability are confirmed before payment.", "Narx, bagaj va joylar to‘lovdan oldin tasdiqlanadi.", "Нарх, багаж ва жойлар тўловдан олдин тасдиқланади.")).font(IumrahType.regular(13)).foregroundStyle(.secondary)
            if onChoose != nil || externalURL != nil {
                VStack(spacing: 10) {
                    if let onChoose {
                        Button { onChoose(); if dismissAfterChoose { dismiss() } } label: {
                            Text(actionTitle ?? t("Выбрать перелёт", "Select flight", "Parvozni tanlash", "Парвозни танлаш")).font(IumrahType.bold(16)).frame(maxWidth: .infinity).frame(height: 52)
                        }.buttonStyle(IumrahPrimaryButtonStyle())
                    }
                    if let externalURL {
                        Button { openURL(externalURL) } label: {
                            Text(t("Проверить на Aviasales", "Check on Aviasales", "Aviasales’da tekshirish", "Aviasales’да текшириш")).font(IumrahType.bold(14)).frame(maxWidth: .infinity).frame(height: 44)
                        }.buttonStyle(IumrahSecondaryButtonStyle())
                    }
                }.padding(.vertical, 10)
            }
            }.padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.bottom, IumrahDesign.pagePadding)
        }
        .background(IumrahFlightPalette.page, ignoresSafeAreaEdges: .bottom)
        .iumrahFlightDetailChrome(title: flight.airline, shareText: legs.first?.share ?? "\(flight.origin) → \(flight.destination)")
    }

    private func detailGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title)
                .font(IumrahType.bold(18, relativeTo: .headline))
            VStack(alignment: .leading, spacing: 13, content: content)
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(IumrahFlightPalette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.75)
                }
        }
    }

    private func routePoint(code: String, date: String?, title: String, estimatedArrival: IumrahFlightClock.Arrival? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 13))
                .foregroundStyle(Color.primary)
                .frame(width: 18)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(IumrahType.bold(10, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                Text("\(IumrahOTAText.city(code)) (\(code.uppercased()))")
                    .font(IumrahType.bold(15))
                if let airport = IumrahOTAText.airport(code) {
                    Text(airport).font(IumrahType.regular(12, relativeTo: .caption)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(estimatedArrival?.time ?? IumrahOTAText.clock(date, airportCode: code))
                    .font(IumrahType.bold(25, relativeTo: .title3))
                    .monospacedDigit()
                if let date {
                    Text(IumrahOTAText.date(date, language: language, airportCode: code))
                        .font(IumrahType.regular(11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                } else if let estimatedArrival {
                    Text(estimatedArrival.day)
                        .font(IumrahType.regular(11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                    Text(t("Расчётное время", "Estimated time", "Hisoblangan vaqt", "Ҳисобланган вақт"))
                        .font(IumrahType.regular(11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                } else {
                    Text(t("Время уточняется", "Time pending", "Vaqt aniqlanmoqda", "Вақт аниқланмоқда"))
                        .font(IumrahType.regular(11, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func legRow(_ leg: IumrahOTAFlightLeg, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            if flight.segments.count > 1 {
                HStack(spacing: 8) {
                    AirlineLogoView(airlineCode: leg.airlineCode, size: 28)
                    Text(t("Сегмент", "Segment", "Qism", "Қисм") + " \(index + 1)")
                        .font(IumrahType.bold(13, relativeTo: .subheadline))
                    Spacer()
                    if !leg.flightNumber.isEmpty {
                        Text(leg.flightNumber)
                            .font(IumrahType.regular(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            routePoint(code: leg.origin, date: leg.departureAt, title: t("Вылет", "Departure", "Jo‘nash", "Жўнаш"))
            Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1, height: 22).padding(.leading, 8)
            routePoint(code: leg.destination, date: leg.arrivalAt, title: t("Прилёт", "Arrival", "Yetib kelish", "Етиб келиш"))
        }
    }

    private func connectionRow(previous: IumrahOTAFlightLeg, current: IumrahOTAFlightLeg) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(Color.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(t("Пересадка", "Connection", "Ulanish", "Уланиш") + " · " +
                     IumrahOTAText.city(previous.destination))
                    .font(IumrahType.bold(13, relativeTo: .subheadline))
                if let minutes = IumrahOTAText.connectionMinutes(previous, current) {
                    Text(IumrahOTAText.duration(minutes, language))
                        .font(IumrahType.regular(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Text(t("Нужен ли повторный чек-ин или получение багажа — уточните у продавца.",
                       "Check with the seller about baggage collection and re-check-in.",
                       "Bagaj va qayta ro‘yxatdan o‘tishni sotuvchidan tekshiring.",
                       "Багаж ва қайта рўйхатдан ўтишни сотувчидан текширинг."))
                    .font(IumrahType.regular(11, relativeTo: .caption2))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private func factRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(IumrahType.regular(13, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(IumrahType.bold(13, relativeTo: .subheadline))
                .multilineTextAlignment(.trailing)
        }
    }
}
