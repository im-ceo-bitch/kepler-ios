import SwiftUI

/// Shared native hero and airport / aircraft sections. Used by search, package
/// selection and booked-flight details. No invented fare or telemetry fields.
struct IumrahPremiumFlightDetail: View {
    let leg: IumrahPremiumFlightLeg
    let language: AppSettingsStore.Language
    @State private var details: IumrahFlightOperationalDetail?
    @State private var from: Airport?
    @State private var to: Airport?
    @State private var refreshing = false
    @Environment(\.scenePhase) private var scenePhase

    private func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch language { case .russian: return ru; case .uzbek: return uz; case .uzbekCyrillic: return cy; default: return en }
    }
    private let graphite = Color(white: 0.065)
    private var live: Bool { ["EnRoute", "Approaching", "Departed"].contains(details?.status ?? "") }
    private var livePosition: IumrahFlightOperationalDetail.Position? {
        guard live, let p = details?.position, let date = IumrahPremiumFlightLeg.instant(p.reportedAt), Date().timeIntervalSince(date) < 900, Date().timeIntervalSince(date) > -60 else { return nil }
        return p
    }
    private var status: String? {
        switch details?.status {
        case "Expected": return t("По расписанию", "Scheduled", "Jadval bo‘yicha", "Жадвал бўйича")
        case "EnRoute": return t("В полёте", "In flight", "Parvozda", "Парвозда")
        case "Departed": return t("Вылетел", "Departed", "Jo‘nadi", "Жўнади")
        case "Approaching": return t("На подлёте", "Approaching", "Yetib kelmoqda", "Етиб келмоқда")
        case "CheckIn": return t("Регистрация", "Check-in", "Ro‘yxatdan o‘tish", "Рўйхатдан ўтиш")
        case "Boarding": return t("Посадка", "Boarding", "Samolyotga chiqish", "Самолётга чиқиш")
        case "GateClosed": return t("Посадка завершена", "Gate closed", "Chiqish yopildi", "Чиқиш ёпилди")
        case "Delayed": return t("Задержан", "Delayed", "Kechikmoqda", "Кечикмоқда")
        case "Arrived": return t("Прибыл", "Arrived", "Yetib keldi", "Етиб келди")
        case "Canceled": return t("Отменён", "Canceled", "Bekor qilindi", "Бекор қилинди")
        case "Diverted": return t("Маршрут изменён", "Diverted", "Yo‘nalish o‘zgardi", "Йўналиш ўзгарди")
        case "CanceledUncertain": return t("Возможна отмена", "Possible cancellation", "Bekor qilinishi mumkin", "Бекор қилиниши мумкин")
        default: return nil
        }
    }
    private var statusColor: Color {
        if live || details?.status == "Arrived" { return .green }
        if ["Canceled", "Diverted", "Delayed", "CanceledUncertain"].contains(details?.status ?? "") { return .orange }
        return Color.white.opacity(0.8)
    }
    private var route: IumrahFlightGlobeRoute? {
        guard leg.stops == 0, let a = from ?? bundled(leg.origin), let b = to ?? bundled(leg.destination) else { return nil }
        return .init(from: a, to: b, position: livePosition)
    }
    private func bundled(_ code: String) -> Airport? { AirportMapBootstrapCatalog.airports.first { $0.iata == code.uppercased() } }
    private func city(_ code: String, airport: Airport?) -> String { airport?.city ?? FlightReferenceCatalog.airport(code)?.city ?? code }
    private func dateLabel(_ day: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: day) else { return day }
        f.locale = Locale(identifier: language.localeIdentifier); f.setLocalizedDateFormatFromTemplate("d MMM EEE"); return f.string(from: date)
    }
    private func durationText(_ minutes: Int) -> String {
        t("\(minutes / 60) ч \(minutes % 60) мин", "\(minutes / 60)h \(minutes % 60)m", "\(minutes / 60) soat \(minutes % 60) daq", "\(minutes / 60) соат \(minutes % 60) дақ")
    }
    private func clean(_ value: String?) -> String? { guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }; return value }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if live { TimelineView(.periodic(from: .now, by: 60)) { _ in hero } } else { hero }
            airportSection
            if clean(details?.aircraft ?? leg.aircraft) != nil || clean(details?.registration) != nil || clean(leg.cabin) != nil || clean(leg.operatingCarrier) != nil { aircraftSection }
            if details != nil {
                HStack {
                    Text("AeroDataBox · " + (IumrahPremiumFlightLeg.instant(details?.updatedAt).map { $0.formatted(.dateTime.day().month().hour().minute()) } ?? t("Данные рейса", "Flight data", "Reys ma’lumotlari", "Рейс маълумотлари"))).font(IumrahType.regular(11, relativeTo: .caption2)).foregroundStyle(.secondary)
                    Spacer()
                    Button { Task { await refreshOperational() } } label: {
                        Text(t("Обновить", "Refresh", "Yangilash", "Янгилаш")).font(IumrahType.bold(12))
                    }.buttonStyle(.plain).disabled(refreshing)
                }
            }
        }
        .task(id: leg) { await load() }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if !leg.airlineCode.isEmpty { AirlineLogoView(airlineCode: leg.airlineCode, size: 39) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(leg.title).font(IumrahType.regular(14)).foregroundStyle(.white.opacity(0.72))
                    if let number = leg.verifiedNumber, leg.stops == 0 { Text(number).font(IumrahType.bold(29, relativeTo: .title)).foregroundStyle(.white) }
                }
                Spacer(minLength: 0)
                if let status { Text(status).font(IumrahType.bold(12, relativeTo: .caption)).foregroundStyle(statusColor).multilineTextAlignment(.trailing) }
            }
            HStack(alignment: .top, spacing: 10) {
                endpoint(leg.origin, city: city(leg.origin, airport: from ?? bundled(leg.origin)), raw: leg.departure, trailing: false)
                VStack(spacing: 7) {
                    Image(systemName: leg.stops == 0 ? "airplane" : "arrow.triangle.branch").font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    if leg.effectiveDuration > 0 { Text(durationText(leg.effectiveDuration)).font(IumrahType.regular(11, relativeTo: .caption)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center) }
                }.padding(.top, 12).frame(maxWidth: .infinity)
                endpoint(leg.destination, city: city(leg.destination, airport: to ?? bundled(leg.destination)), raw: arrivalDisplay, trailing: true, estimated: arrivalEstimated)
            }
            if leg.stops >= 0 { Text(leg.stops == 0 ? t("Прямой рейс", "Non-stop", "To‘g‘ridan-to‘g‘ri", "Тўғридан-тўғри") : t("Пересадок: \(leg.stops)", "Stops: \(leg.stops)", "Ulanish: \(leg.stops)", "Уланиш: \(leg.stops)")).font(IumrahType.regular(12, relativeTo: .caption)).foregroundStyle(.white.opacity(0.68)).frame(maxWidth: .infinity) }
            globe
            if let p = livePosition { liveMetrics(p) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(graphite, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
    private var arrivalEstimate: IumrahFlightClock.Arrival? {
        guard clean(leg.arrival) == nil, details?.arrivalScheduled == nil, IumrahPremiumFlightLeg.localParts(leg.departure, code: leg.origin) != nil, leg.stops == 0 else { return nil }
        return IumrahFlightClock.arrival(actual: nil, departure: leg.departure, duration: leg.effectiveDuration, origin: leg.origin, destination: leg.destination)
    }
    private var arrivalDisplay: String? {
        if let raw = leg.arrival, !raw.isEmpty { return raw }
        if let raw = details?.arrivalScheduled, raw.count >= 16 { return String(raw.prefix(16)) }
        return arrivalEstimate.map { $0.day + "T" + $0.time }
    }
    private var arrivalEstimated: Bool { arrivalEstimate != nil }
    private func endpoint(_ code: String, city: String, raw: String?, trailing: Bool, estimated: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            Text(code).font(IumrahType.bold(37, relativeTo: .largeTitle)).minimumScaleFactor(0.65).lineLimit(1).foregroundStyle(.white)
            if city != code { Text(city).font(IumrahType.regular(12, relativeTo: .caption)).foregroundStyle(.white.opacity(0.72)).lineLimit(2) }
            if let local = IumrahPremiumFlightLeg.localParts(raw, code: code) {
                Text(local.time).font(IumrahType.bold(27, relativeTo: .title2)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(.white).padding(.top, 6)
                Text(dateLabel(local.day)).font(IumrahType.regular(11, relativeTo: .caption)).foregroundStyle(.white.opacity(0.72))
                if estimated { Text(t("Расчётное", "Estimated", "Hisoblangan", "Ҳисобланган")).font(IumrahType.regular(10)).foregroundStyle(.white.opacity(0.65)) }
            } else if let raw, raw.count == 10 {
                Text(dateLabel(raw)).font(IumrahType.regular(12)).foregroundStyle(.white.opacity(0.72))
            }
        }.frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }
    private var globe: some View {
        VStack(spacing: 4) {
            ZStack {
                IumrahHemisphereMap(projection: route?.projection ?? .arabia, palette: .dark, isAnimating: scenePhase == .active, mapOpacity: 0.87)
                if let route { routeOverlay(route) }
            }.frame(height: 218)
            if route != nil { Text(t("Маршрут по большой окружности", "Great-circle route", "Katta aylana bo‘yicha yo‘nalish", "Катта айлана бўйича йўналиш")).font(IumrahType.regular(10, relativeTo: .caption2)).foregroundStyle(.white.opacity(0.52)) }
        }.accessibilityHidden(true)
    }
    private func routeOverlay(_ route: IumrahFlightGlobeRoute) -> some View {
        Canvas { context, size in
            let d = min(size.width, size.height), x = (size.width-d)/2, y = (size.height-d)/2
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: x+p.x*d, y: y+p.y*d) }
            func line(_ points: ArraySlice<CGPoint>) -> Path { Path { path in if let first = points.first { path.move(to: point(first)); for item in points.dropFirst() { path.addLine(to: point(item)) } } } }
            context.stroke(line(route.points[...]), with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 4]))
            if let index = route.progressIndex, route.livePoint != nil {
                context.stroke(line(route.points[...index]), with: .color(.green), style: StrokeStyle(lineWidth: 2.3, lineCap: .round))
            }
            for (p, label) in [(route.points.first, leg.origin), (route.points.last, leg.destination)] {
                guard let p else { continue }; let q = point(p)
                context.fill(Path(ellipseIn: CGRect(x: q.x-3.5, y: q.y-3.5, width: 7, height: 7)), with: .color(.white))
                context.draw(Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: q.x, y: q.y + 15))
            }
            if let p = route.livePoint {
                let q = point(p)
                context.draw(Text(Image(systemName: "airplane.circle.fill")).font(.system(size: 17)).foregroundColor(.green), at: q)
            }
        }.allowsHitTesting(false)
    }
    private func liveMetrics(_ p: IumrahFlightOperationalDetail.Position) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let altitude = p.altitudeFeet, altitude.isFinite, abs(altitude) < 100_000 { metric(t("Высота", "Altitude", "Balandlik", "Баландлик"), "\(Int(altitude.rounded())) ft") }
                if let speed = p.speedKmh, speed.isFinite, speed >= 0, speed < 3000 { metric(t("Скорость", "Ground speed", "Tezlik", "Тезлик"), "\(Int(speed.rounded())) km/h") }
                if let arrival = IumrahPremiumFlightLeg.instant(details?.arrivalEstimatedUTC), arrival > Date() { metric(t("До прилёта", "Until arrival", "Yetib kelishgacha", "Етиб келишгача"), durationText(Int(arrival.timeIntervalSinceNow / 60))) }
            }
            if let date = IumrahPremiumFlightLeg.instant(p.reportedAt) { Text(t("Позиция на ", "Position at ", "Joylashuv vaqti ", "Жойлашув вақти ") + date.formatted(.dateTime.hour().minute()) + " · " + t("Прогресс ориентировочный", "Approximate progress", "Taxminiy jarayon", "Тахминий жараён")).font(IumrahType.regular(10, relativeTo: .caption2)).foregroundStyle(.white.opacity(0.65)) }
        }
    }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(title).font(IumrahType.regular(11)).foregroundStyle(.white.opacity(0.65)); Text(value).font(IumrahType.bold(17)).foregroundStyle(.white).minimumScaleFactor(0.7) }.frame(maxWidth: .infinity, alignment: .leading) }
    private var airportSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(t("Детали перелёта", "Flight itinerary", "Parvoz tafsilotlari", "Парвоз тафсилотлари")).font(IumrahType.bold(19))
            airportRow(code: leg.origin, airport: from ?? bundled(leg.origin), title: t("Вылет", "Departure", "Jo‘nash", "Жўнаш"), terminal: details?.departureTerminal ?? leg.departureTerminal, gate: details?.departureGate, revised: details?.departureRevised, actual: details?.departureActual)
            Divider()
            airportRow(code: leg.destination, airport: to ?? bundled(leg.destination), title: t("Прилёт", "Arrival", "Yetib kelish", "Етиб келиш"), terminal: details?.arrivalTerminal ?? leg.arrivalTerminal, gate: details?.arrivalGate, revised: details?.arrivalRevised, actual: details?.arrivalActual)
            if let belt = clean(details?.baggageBelt) { fact(t("Лента багажа", "Baggage belt", "Bagaj lentasi", "Багаж лентаси"), belt) }
        }.iumrahCard()
    }
    private func airportRow(code: String, airport: Airport?, title: String, terminal: String?, gate: String?, revised: String?, actual: String?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(IumrahType.regular(12)).foregroundStyle(.secondary)
            Text("\(city(code, airport: airport)) · \(code)").font(IumrahType.bold(17))
            if let name = airport?.name ?? FlightReferenceCatalog.airport(code)?.name { Text(name).font(IumrahType.regular(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let terminal = clean(terminal) { fact(t("Терминал", "Terminal", "Terminal", "Терминал"), terminal) }
            if let gate = clean(gate) { fact(t("Выход", "Gate", "Chiqish", "Чиқиш"), gate) }
            if let actual = clean(actual) { fact(t("Фактическое время ВПП", "Actual runway time", "Haqiqiy uchish vaqti", "Ҳақиқий учиш вақти"), actual) }
            else if let revised = clean(revised) { fact(t("Обновлённое время", "Revised time", "Yangilangan vaqt", "Янгиланган вақт"), revised) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var aircraftSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Самолёт и класс", "Aircraft & cabin", "Samolyot va klass", "Самолёт ва класс")).font(IumrahType.bold(19))
            if let model = clean(details?.aircraft ?? leg.aircraft) { fact(t("Самолёт", "Aircraft", "Samolyot", "Самолёт"), model) }
            if let reg = clean(details?.registration) { fact(t("Бортовой номер", "Registration", "Bort raqami", "Борт рақами"), reg) }
            if let cabin = clean(leg.cabin) { fact(t("Класс", "Cabin", "Klass", "Класс"), cabin.capitalized) }
            if let carrier = clean(leg.operatingCarrier) { fact(t("Выполняет рейс", "Operated by", "Parvoz operatori", "Парвоз оператори"), carrier) }
        }.iumrahCard()
    }
    private func fact(_ title: String, _ value: String) -> some View { HStack(alignment: .firstTextBaseline) { Text(title).font(IumrahType.regular(13)).foregroundStyle(.secondary); Spacer(minLength: 10); Text(value).font(IumrahType.bold(13)).multilineTextAlignment(.trailing) } }
    @MainActor private func load() async {
        details = nil; from = bundled(leg.origin); to = bundled(leg.destination)
        async let origin = resolve(leg.origin, existing: from)
        async let destination = resolve(leg.destination, existing: to)
        async let enrichment = fetchDetail()
        let (a, b, data) = await (origin, destination, enrichment)
        guard !Task.isCancelled else { return }
        from = a; to = b; details = data
        // No timer polling by default: avoid consuming provider quota. The
        // user can explicitly refresh the operational data on this screen.
    }
    @MainActor private func refreshOperational() async {
        guard !refreshing else { return }; refreshing = true; defer { refreshing = false }
        if let new = await fetchDetail(), !Task.isCancelled { details = new }
    }
    private func resolve(_ code: String, existing: Airport?) async -> Airport? {
        if let existing { return existing }
        guard let airports = try? await AirportSearchService().search(code, limit: 4) else { return nil }
        return airports.first { $0.iata.uppercased() == code.uppercased() }
    }
    private func fetchDetail() async -> IumrahFlightOperationalDetail? {
        guard leg.stops == 0, let number = leg.verifiedNumber, let local = IumrahPremiumFlightLeg.localParts(leg.departure, code: leg.origin) else { return nil }
        return await IumrahFlightDetailService.shared.detail(number: number, day: local.day, time: local.time, origin: leg.origin.uppercased(), destination: leg.destination.uppercased())
    }
}

/// Only show connections whose adjacent segments and timestamps are verified.
struct IumrahPremiumFlightConnection: View {
    let previous: IumrahPremiumFlightLeg
    let next: IumrahPremiumFlightLeg
    let language: AppSettingsStore.Language
    var body: some View {
        if previous.destination.uppercased() == next.origin.uppercased(),
           let arrival = IumrahPremiumFlightLeg.instant(previous.arrival),
           let departure = IumrahPremiumFlightLeg.instant(next.departure), departure >= arrival {
            let minutes = Int(departure.timeIntervalSince(arrival) / 60)
            HStack(spacing: 10) {
                Image(systemName: "clock").foregroundStyle(.secondary)
                Text(title + " · " + next.origin).font(IumrahType.bold(14))
                Spacer()
                Text("\(minutes / 60)h \(minutes % 60)m").font(IumrahType.regular(13)).foregroundStyle(.secondary)
            }.iumrahCard()
        }
    }
    private var title: String {
        switch language { case .russian: return "Пересадка"; case .uzbek: return "Ulanish"; case .uzbekCyrillic: return "Уланиш"; default: return "Connection" }
    }
}
