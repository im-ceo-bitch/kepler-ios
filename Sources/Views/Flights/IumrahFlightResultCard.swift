import SwiftUI

/// Shared presentation for the catalogue and both configurator legs.
struct IumrahFlightResultCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let airline: String
    let airlineCode: String
    let flightNumber: String
    let origin: String
    let destination: String
    let departureAt: String
    let arrivalAt: String?
    let duration: Int
    let stops: Int
    let price: Double?
    let isAviasales: Bool
    var selected = false
    let action: () -> Void

    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    private var arrival: IumrahFlightClock.Arrival? {
        IumrahFlightClock.arrival(actual: arrivalAt, departure: departureAt, duration: duration, origin: origin, destination: destination)
    }
    private var localDeparture: String { IumrahFlightClock.local(departureAt, airport: origin) }
    private var number: String {
        let trimmed = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.uppercased().hasPrefix(airlineCode.uppercased()) ? trimmed : "\(airlineCode) \(trimmed)"
    }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    AirlineLogoView(airlineCode: airlineCode, size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(airline).font(IumrahType.bold(16, relativeTo: .headline)).lineLimit(2)
                        Text(number).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(isAviasales ? "Aviasales" : "iumrah Direct")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isAviasales ? Color.blue : Color.iumrahInk)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background((isAviasales ? Color.blue : Color.primary).opacity(0.08), in: Capsule())
                        if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green) }
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(IumrahFlightClock.time(localDeparture)).font(.title2.weight(.bold)).monospacedDigit()
                        Text(origin).font(.subheadline.weight(.semibold))
                        Text(IumrahFlightClock.day(localDeparture, locale: Locale(identifier: settings.language.localeIdentifier))).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 7) {
                        Text(duration > 0 ? "\(duration / 60)h \(duration % 60)m" : "—").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                            Image(systemName: stops == 0 ? "airplane" : "circle.fill").font(.system(size: stops == 0 ? 12 : 5))
                            Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 1)
                        }.frame(width: 70).foregroundStyle(stops == 0 ? Color.green : Color.secondary)
                        Text(stops == 0 ? tr("Без пересадок", "Non-stop", "Transfersiz", "Трансферсиз") : tr("Пересадок: \(stops)", "Stops: \(stops)", "Transfer: \(stops)", "Трансфер: \(stops)"))
                            .font(.caption2).foregroundStyle(stops == 0 ? Color.green : Color.secondary)
                    }.padding(.top, 4)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(arrival?.time ?? "—").font(.title2.weight(.bold)).monospacedDigit()
                        Text(destination).font(.subheadline.weight(.semibold))
                        if let arrival {
                            Text(IumrahFlightClock.day(arrival.day, locale: Locale(identifier: settings.language.localeIdentifier))).font(.caption).foregroundStyle(.secondary)
                            if arrival.estimated {
                                Text(tr("Расчётное", "Estimated", "Hisoblangan", "Ҳисобланган")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Divider().opacity(0.55)
                HStack(alignment: .firstTextBaseline) {
                    Text(tr("За пассажира", "Per passenger", "Bir yo‘lovchi uchun", "Бир йўловчи учун"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let price, price > 0 {
                        Text(price.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                            .font(IumrahType.bold(23, relativeTo: .title2))
                    } else {
                        Text(tr("Цена при расчёте", "Price on quote", "Narx hisobda", "Нарх ҳисобда"))
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(Color.iumrahInk).padding(18)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(selected ? Color.green : Color.primary.opacity(0.04), lineWidth: selected ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 28))
        }.buttonStyle(.plain)
    }
}

enum IumrahFlightCopy {
    static func text(_ language: AppSettingsStore.Language, _ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch language { case .russian: return ru; case .uzbek: return uz; case .uzbekCyrillic: return cy; default: return en }
    }
}

/// A calculated arrival is display-only, never written into a supplier itinerary.
enum IumrahFlightClock {
    struct Arrival { let time: String; let day: String; let estimated: Bool }
    static func time(_ value: String) -> String {
        guard value.count >= 16 else { return "—" }
        return String(value.dropFirst(11).prefix(5))
    }
    static func day(_ value: String, locale: Locale) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(value.prefix(10))) else { return "" }
        let output = DateFormatter(); output.locale = locale; output.timeZone = parser.timeZone; output.setLocalizedDateFormatFromTemplate("d MMM")
        return output.string(from: date)
    }
    static func local(_ value: String, airport: String) -> String {
        guard let zone = FlightReferenceCatalog.timeZone(for: airport) else { return value }
        let parser = ISO8601DateFormatter()
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; date = parser.date(from: value) }
        guard let date else { return value }
        let output = DateFormatter(); output.locale = Locale(identifier: "en_US_POSIX"); output.timeZone = zone
        output.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return output.string(from: date)
    }
    static func arrival(actual: String?, departure: String, duration: Int, origin: String, destination: String) -> Arrival? {
        if let actual, actual.count >= 16 {
            let localized = local(actual, airport: destination)
            return Arrival(time: time(localized), day: String(localized.prefix(10)), estimated: false)
        }
        guard duration > 0, let originZone = FlightReferenceCatalog.timeZone(for: origin),
              let destinationZone = FlightReferenceCatalog.timeZone(for: destination) else { return nil }
        let iso = ISO8601DateFormatter()
        var date = iso.date(from: departure)
        if date == nil {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            date = iso.date(from: departure)
        }
        if date == nil {
            let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = originZone
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = parser.date(from: String(departure.prefix(19)))
            if date == nil { parser.dateFormat = "yyyy-MM-dd'T'HH:mm"; date = parser.date(from: String(departure.prefix(16))) }
        }
        guard let date else { return nil }
        let output = DateFormatter(); output.locale = Locale(identifier: "en_US_POSIX"); output.timeZone = destinationZone
        let arrival = date.addingTimeInterval(TimeInterval(duration * 60))
        output.dateFormat = "HH:mm"; let time = output.string(from: arrival)
        output.dateFormat = "yyyy-MM-dd"
        return Arrival(time: time, day: output.string(from: arrival), estimated: true)
    }
}

struct IumrahFlightFilterState {
    var directOnly = false
    var airline = ""
    var sort = 0
    var day: String? = nil
    func accepts(stops: Int, airline: String, departure: String, includeDay: Bool = true) -> Bool {
        (!directOnly || stops == 0) && (self.airline.isEmpty || self.airline == airline) && (!includeDay || day == nil || day == String(departure.prefix(10)))
    }
}
struct IumrahFlightPriceDay: Identifiable {
    let id: String
    let price: Double
}

/// Bars are minimum observed fares, not interpolated prices or a live quote.
struct IumrahFlightSearchControls: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var filters: IumrahFlightFilterState
    let airlines: [String]
    let days: [IumrahFlightPriceDay]
    var selectedDay: String? = nil
    var onSelectDay: ((String) -> Void)? = nil
    @State private var showCalendar = false
    @State private var calendarDate = Date()
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String { IumrahFlightCopy.text(settings.language, ru, en, uz, cy) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { filters.directOnly.toggle() } label: {
                        Text(tr("Без пересадок", "Non-stop", "Transfersiz", "Трансферсиз"))
                            .foregroundStyle(filters.directOnly ? Color.white : Color.iumrahInk)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(filters.directOnly ? Color.iumrahSignatureBlack : Color.iumrahCardBackground, in: Capsule())
                    }.buttonStyle(.plain)
                    Menu {
                        Picker(tr("Авиакомпания", "Airline", "Aviakompaniya", "Авиакомпания"), selection: $filters.airline) {
                            Text(tr("Все", "All", "Barchasi", "Барчаси")).tag("")
                            ForEach(airlines, id: \.self) { Text(FlightReferenceCatalog.airlineName(code: $0, fallback: $0)).tag($0) }
                        }
                    } label: { pill(filters.airline.isEmpty ? tr("Авиакомпания", "Airline", "Aviakompaniya", "Авиакомпания") : filters.airline) }
                    Menu {
                        Picker(tr("Сортировка", "Sort", "Saralash", "Саралаш"), selection: $filters.sort) {
                            Text(tr("По дате", "Date", "Sana", "Сана")).tag(0)
                            Text(tr("Дешевле", "Cheapest", "Arzonroq", "Арзонроқ")).tag(1)
                            Text(tr("Быстрее", "Fastest", "Tezroq", "Тезроқ")).tag(2)
                        }
                    } label: { pill(filters.sort == 1 ? tr("Дешевле", "Cheapest", "Arzonroq", "Арзонроқ") : filters.sort == 2 ? tr("Быстрее", "Fastest", "Tezroq", "Тезроқ") : tr("По дате", "Date", "Sana", "Сана")) }
                    Button { showCalendar = true } label: { pill(tr("Календарь", "Calendar", "Taqvim", "Тақвим")) }.buttonStyle(.plain)
                }.font(.subheadline.weight(.medium))
            }
            if !days.isEmpty {
                HStack {
                    Text(tr("Цены по датам · USD", "Fares by date · USD", "Sanalar bo‘yicha narx · USD", "Саналар бўйича нарх · USD")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if filters.day != nil {
                        Button(tr("Все даты", "All dates", "Barcha sanalar", "Барча саналар")) { filters.day = nil }.font(.caption)
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(days) { day in
                            Button { select(day.id) } label: {
                                VStack(spacing: 6) {
                                    Text(day.price.formatted(.number.precision(.fractionLength(0)))).font(.caption2.weight(.semibold))
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill((selectedDay ?? filters.day) == day.id ? Color.iumrahInk : Color.blue.opacity(0.24))
                                        .frame(width: 42, height: max(12, 52 * day.price / max(days.map(\.price).max() ?? 1, 1)))
                                    Text(IumrahFlightClock.day(day.id, locale: Locale(identifier: settings.language.localeIdentifier))).font(.caption2)
                                }.frame(width: 56).foregroundStyle(Color.iumrahInk)
                            }.buttonStyle(.plain)
                             .accessibilityLabel("\(day.id), \(day.price.formatted(.currency(code: "USD")))")
                             .accessibilityAddTraits((selectedDay ?? filters.day) == day.id ? .isSelected : [])
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showCalendar) {
            NavigationStack {
                VStack(spacing: 20) {
                    DatePicker(tr("Дата вылета", "Departure date", "Uchish sanasi", "Учиш санаси"), selection: $calendarDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Button(tr("Выбрать дату", "Select date", "Sanani tanlash", "Санани танлаш")) {
                        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
                        select(formatter.string(from: calendarDate)); showCalendar = false
                    }.buttonStyle(IumrahPrimaryButtonStyle())
                    Spacer()
                }.padding(20)
                .navigationTitle(tr("Календарь цен", "Fare calendar", "Narxlar taqvimi", "Нархлар тақвими"))
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("Закрыть", "Close", "Yopish", "Ёпиш")) { showCalendar = false } } }
            }.presentationDetents([.large])
        }
    }
    private func select(_ day: String) {
        if let onSelectDay { onSelectDay(day) } else { filters.day = day }
        IumrahHaptics.selection()
    }
    private func pill(_ title: String) -> some View {
        Text(title).padding(.horizontal, 14).padding(.vertical, 10).background(Color.iumrahCardBackground, in: Capsule())
    }
    static func priceDays(_ fares: [(String, Double?)]) -> [IumrahFlightPriceDay] {
        var lowest: [String: Double] = [:]
        for (date, price) in fares {
            guard let price, price.isFinite, price > 0 else { continue }
            let key = String(date.prefix(10))
            lowest[key] = min(lowest[key] ?? price, price)
        }
        return lowest.keys.sorted().map { IumrahFlightPriceDay(id: $0, price: lowest[$0]!) }
    }
}
