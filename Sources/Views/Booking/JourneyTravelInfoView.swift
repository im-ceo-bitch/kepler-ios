import CoreLocation
import Foundation
import SwiftUI

// MARK: - Booking travel context

enum IumrahHolyCity: String, CaseIterable, Identifiable, Codable {
    case makkah
    case madinah

    var id: String { rawValue }

    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .makkah: return CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)
        case .madinah: return CLLocationCoordinate2D(latitude: 24.4672, longitude: 39.6111)
        }
    }

    var timeZone: TimeZone {
        TimeZone(identifier: "Asia/Riyadh") ?? .current
    }

    func title(_ language: AppSettingsStore.Language) -> String {
        switch self {
        case .makkah:
            switch language {
            case .russian: return "Мекка"
            case .turkish: return TurkishLocalization.phrase("Makkah")
            case .arabic: return ArabicLocalization.phrase("Makkah")
            case .indonesian, .malay, .english: return "Makkah"
            case .uzbek: return "Makka"
            case .uzbekCyrillic: return "Макка"
            }
        case .madinah:
            switch language {
            case .russian: return "Медина"
            case .turkish: return TurkishLocalization.phrase("Madinah")
            case .arabic: return ArabicLocalization.phrase("Madinah")
            case .indonesian, .malay, .english: return "Madinah"
            case .uzbek: return "Madina"
            case .uzbekCyrillic: return "Мадина"
            }
        }
    }
}

enum JourneyInfoPage: Int, CaseIterable, Identifiable {
    case prayer
    case weather
    case clocks
    var id: Int { rawValue }
}

@MainActor
final class JourneyTravelInfoModel: ObservableObject {
    @Published private(set) var prayers: IumrahPrayerDay?
    @Published private(set) var weather: IumrahWeatherSnapshot?
    @Published private(set) var localCityName: String
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let prayerService = IumrahPrayerTimesService()
    private let weatherService = IumrahWeatherService()
    private var lastCity: IumrahHolyCity?

    init() {
        localCityName = Self.timeZoneCityName()
        resolveAuthorizedLocationName()
    }

    func refresh(city: IumrahHolyCity, force: Bool = false) async {
        if !force, lastCity == city, prayers != nil, weather != nil { return }
        if lastCity != nil, lastCity != city {
            prayers = nil
            weather = nil
        }
        lastCity = city
        isRefreshing = true
        defer { isRefreshing = false }

        async let prayerResult: IumrahPrayerDay? = try? prayerService.prayers(for: city, date: Date(), forceRefresh: force)
        async let weatherResult: IumrahWeatherSnapshot? = try? weatherService.forecast(for: city, forceRefresh: force)
        let (newPrayers, newWeather) = await (prayerResult, weatherResult)

        if let newPrayers { prayers = newPrayers }
        if let newWeather { weather = newWeather }
        lastError = (newPrayers == nil && newWeather == nil) ? "unavailable" : nil
    }

    private func resolveAuthorizedLocationName() {
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways,
              let location = CLLocationManager().location else { return }

        Task { @MainActor in
            if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first,
               let city = placemark.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
               !city.isEmpty {
                localCityName = city
            }
        }
    }

    private static func timeZoneCityName() -> String {
        let identifier = TimeZone.autoupdatingCurrent.identifier
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }
}

struct JourneyTravelInfoView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @AppStorage("iumrah.booking.travelInfo.city") private var selectedCityRaw = IumrahHolyCity.makkah.rawValue
    @StateObject private var model = JourneyTravelInfoModel()
    @State private var page: JourneyInfoPage = .prayer
    var onOpenPrayer: (() -> Void)? = nil
    var onOpenWeather: (() -> Void)? = nil

    init(initialPage: JourneyInfoPage = .prayer, onOpenPrayer: (() -> Void)? = nil, onOpenWeather: (() -> Void)? = nil) {
        _page = State(initialValue: initialPage)
        self.onOpenPrayer = onOpenPrayer
        self.onOpenWeather = onOpenWeather
    }

    private var city: IumrahHolyCity {
        IumrahHolyCity(rawValue: selectedCityRaw) ?? .makkah
    }

    var body: some View {
        VStack(spacing: 12) {
            holyCityPicker

            TabView(selection: $page) {
                PrayerTimesCard(city: city, day: model.prayers, isRefreshing: model.isRefreshing)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenPrayer?() }
                    .accessibilityAddTraits(onOpenPrayer == nil ? [] : .isButton)
                    .tag(JourneyInfoPage.prayer)
                WeatherForecastCard(city: city, forecast: model.weather, isRefreshing: model.isRefreshing)
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenWeather?() }
                    .accessibilityAddTraits(onOpenWeather == nil ? [] : .isButton)
                    .tag(JourneyInfoPage.weather)
                DualWorldClockCard(city: city, localCityName: model.localCityName)
                    .tag(JourneyInfoPage.clocks)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 310)

            HStack(spacing: 7) {
                ForEach(JourneyInfoPage.allCases) { item in
                    Capsule()
                        .fill(item == page ? Color.primary : Color.secondary.opacity(0.20))
                        .frame(width: item == page ? 22 : 7, height: 7)
                        .animation(.snappy(duration: 0.24), value: page)
                }
            }
            .accessibilityHidden(true)
        }
        .task(id: city.rawValue) {
            await model.refresh(city: city)
        }
        .onChange(of: page) { _, _ in
            IumrahHaptics.selection()
        }
        .refreshable {
            await model.refresh(city: city, force: true)
        }
    }

    private var holyCityPicker: some View {
        Picker(
            tr("Holy city", "Священный город", "Muqaddas shahar", "Муқаддас шаҳар"),
            selection: Binding(
                get: { city },
                set: { newValue in
                    guard newValue != city else { return }
                    IumrahHaptics.selection()
                    withAnimation(.snappy(duration: 0.24)) {
                        selectedCityRaw = newValue.rawValue
                    }
                }
            )
        ) {
            Text(IumrahHolyCity.makkah.title(settings.language)).tag(IumrahHolyCity.makkah)
            Text(IumrahHolyCity.madinah.title(settings.language)).tag(IumrahHolyCity.madinah)
        }
        .pickerStyle(.segmented)
        .accessibilityElement(children: .contain)
    }

    private func tr(_ en: String, _ ru: String, _ uz: String, _ cyrl: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .turkish: return TurkishLocalization.phrase(en)
        case .arabic: return ArabicLocalization.phrase(en)
        case .indonesian, .malay, .english: return en
        case .uzbek: return uz
        case .uzbekCyrillic: return cyrl
        }
    }
}

// MARK: - Prayer card

private struct PrayerTimesCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let city: IumrahHolyCity
    let day: IumrahPrayerDay?
    let isRefreshing: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(eyebrow, systemImage: "moon.stars.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(city.title(settings.language))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .tracking(-0.55)
                    }
                    Spacer(minLength: 8)
                    if isRefreshing && day == nil { ProgressView().controlSize(.small) }
                    if let next = day?.nextPrayer(after: context.date) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(next.title(settings.language))
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.iumrahCareLight)
                            Text(next.time)
                                .font(.title3.monospacedDigit().weight(.bold))
                        }
                    }
                }

                if let day {
                    HStack(spacing: 6) {
                        ForEach(day.prayers) { prayer in
                            prayerCell(prayer, nextID: day.nextPrayer(after: context.date)?.id)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ForEach(0..<5, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.primary.opacity(0.045))
                                .frame(height: 86)
                        }
                    }
                    .redacted(reason: .placeholder)

                    if !isRefreshing {
                        Label(prayerUnavailableText, systemImage: "wifi.slash")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text(methodLabel)
                    Spacer()
                    if let sunrise = day?.sunrise {
                        Label(sunrise, systemImage: "sunrise.fill")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)

                if let next = day?.nextPrayer(after: context.date) {
                    countdownPanel(next: next, now: context.date)
                }
            }
            .padding(19)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(prayerBackground, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
        }
    }

    private func prayerCell(_ prayer: IumrahPrayerMoment, nextID: String?) -> some View {
        let active = prayer.id == nextID
        return VStack(spacing: 9) {
            Image(systemName: prayer.symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.secondary)
            Text(prayer.shortTitle(settings.language))
                .font(.caption.weight(.bold))
                .foregroundStyle(active ? Color.white.opacity(0.90) : Color.secondary)
            Text(prayer.time)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 94)
        .background(active ? Color.black : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: active)
    }

    private func countdownPanel(next: IumrahPrayerMoment, now: Date) -> some View {
        let parts = countdownParts(to: next.date, now: now)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("NEXT PRAYER", "СЛЕДУЮЩАЯ МОЛИТВА", "KEYINGI NAMOZ", "КЕЙИНГИ НАМОЗ"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(next.title(settings.language))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }

            Spacer(minLength: 8)

            Text(String(format: "%02d:%02d:%02d", parts.hours, parts.minutes, parts.seconds))
                .font(.system(size: 25, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .padding(.horizontal, 15)
        .frame(height: 64)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private func countdownParts(to date: Date, now: Date) -> (hours: Int, minutes: Int, seconds: Int) {
        let interval = max(0, Int(date.timeIntervalSince(now)))
        return (interval / 3600, (interval % 3600) / 60, interval % 60)
    }

    private var prayerBackground: LinearGradient {
        LinearGradient(
            colors: [Color.iumrahCardBackground, Color.iumrahCareLight.opacity(0.055)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var prayerUnavailableText: String {
        switch settings.language {
        case .russian: return "Времена появятся после подключения к сети"
        case .turkish: return TurkishLocalization.phrase("Prayer times appear when online")
        case .arabic: return ArabicLocalization.phrase("Prayer times appear when online")
        case .indonesian, .malay, .english: return "Prayer times appear when online"
        case .uzbek: return "Namoz vaqtlari internet bo‘lganda chiqadi"
        case .uzbekCyrillic: return "Намоз вақтлари интернет бўлганда чиқади"
        }
    }

    private var eyebrow: String {
        switch settings.language {
        case .russian: return "ВРЕМЕНА МОЛИТВ"
        case .turkish: return TurkishLocalization.phrase("PRAYER TIMES")
        case .arabic: return ArabicLocalization.phrase("PRAYER TIMES")
        case .indonesian, .malay, .english: return "PRAYER TIMES"
        case .uzbek: return "NAMOZ VAQTLARI"
        case .uzbekCyrillic: return "НАМОЗ ВАҚТЛАРИ"
        }
    }

    private var methodLabel: String {
        switch settings.language {
        case .russian: return "Umm al-Qura · время Саудии"
        case .turkish: return TurkishLocalization.phrase("Umm al-Qura · Saudi time")
        case .arabic: return ArabicLocalization.phrase("Umm al-Qura · Saudi time")
        case .indonesian, .malay, .english: return "Umm al-Qura · Saudi time"
        case .uzbek: return "Umm al-Qura · Saudiya vaqti"
        case .uzbekCyrillic: return "Umm al-Qura · Саудия вақти"
        }
    }

    private func tr(_ en: String, _ ru: String, _ uz: String, _ cyrl: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .turkish: return TurkishLocalization.phrase(en)
        case .arabic: return ArabicLocalization.phrase(en)
        case .indonesian, .malay, .english: return en
        case .uzbek: return uz
        case .uzbekCyrillic: return cyrl
        }
    }
}

// MARK: - Weather card

private struct WeatherForecastCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let city: IumrahHolyCity
    let forecast: IumrahWeatherSnapshot?
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(weatherEyebrow, systemImage: "cloud.sun.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(city.title(settings.language))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                }
                Spacer(minLength: 8)
                if let forecast {
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: forecast.currentCondition.symbol)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                forecast.currentCondition.primaryColor,
                                forecast.currentCondition.secondaryColor
                            )
                            .font(.system(size: 34, weight: .semibold))
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(Int(forecast.currentTemperature.rounded()))°")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .tracking(-1.2)
                            Text(forecast.currentCondition.localized(settings.language))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }

            if let forecast {
                HStack(spacing: 8) {
                    ForEach(forecast.days.prefix(7)) { day in
                        VStack(spacing: 7) {
                            Text(day.dayLabel(language: settings.language, timeZone: city.timeZone))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                            Image(systemName: day.condition.symbol)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(day.condition.primaryColor, day.condition.secondaryColor)
                                .font(.system(size: 21, weight: .semibold))
                            Text("\(Int(day.high.rounded()))°")
                                .font(.caption.monospacedDigit().weight(.bold))
                            Text("\(Int(day.low.rounded()))°")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .frame(height: 105)
                    .redacted(reason: .placeholder)
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                Text(forecast == nil ? unavailableText : providerText)
                Spacer()
                if let forecast {
                    Text(forecast.updatedLabel(language: settings.language, timeZone: city.timeZone))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(19)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(weatherBackground)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
    }

    private var weatherBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.iumrahCardBackground, Color.blue.opacity(0.085), Color.yellow.opacity(0.035)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var weatherEyebrow: String {
        switch settings.language {
        case .russian: return "ПОГОДА · 7 ДНЕЙ"
        case .turkish: return TurkishLocalization.phrase("WEATHER · 7 DAYS")
        case .arabic: return ArabicLocalization.phrase("WEATHER · 7 DAYS")
        case .indonesian, .malay, .english: return "WEATHER · 7 DAYS"
        case .uzbek: return "OB-HAVO · 7 KUN"
        case .uzbekCyrillic: return "ОБ-ҲАВО · 7 КУН"
        }
    }

    private var providerText: String { "Weather data · MET Norway" }

    private var unavailableText: String {
        switch settings.language {
        case .russian: return "Прогноз появится при подключении к сети"
        case .turkish: return TurkishLocalization.phrase("Forecast appears when online")
        case .arabic: return ArabicLocalization.phrase("Forecast appears when online")
        case .indonesian, .malay, .english: return "Forecast appears when online"
        case .uzbek: return "Prognoz internet bo‘lganda chiqadi"
        case .uzbekCyrillic: return "Прогноз интернет бўлганда чиқади"
        }
    }
}

// MARK: - Clock card

private struct DualWorldClockCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let city: IumrahHolyCity
    let localCityName: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Label(clockEyebrow, systemImage: "clock.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: 18) {
                    clockColumn(
                        title: city.title(settings.language),
                        date: context.date,
                        timeZone: city.timeZone,
                        accent: Color.iumrahCareLight
                    )
                    clockColumn(
                        title: localCityName,
                        date: context.date,
                        timeZone: .autoupdatingCurrent,
                        accent: .blue
                    )
                }

                VStack(spacing: 5) {
                    HStack {
                        Text("\(city.title(settings.language)) · \(gmtLabel(city.timeZone))")
                        Spacer()
                        Text("\(localCityName) · \(gmtLabel(.autoupdatingCurrent))")
                    }
                    Text(offsetText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
            .padding(19)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(clockBackground)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.085), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.035), radius: 14, y: 6)
        }
    }

    private func clockColumn(title: String, date: Date, timeZone: TimeZone, accent: Color) -> some View {
        VStack(spacing: 8) {
            AnalogTravelClock(date: date, timeZone: timeZone, accent: accent)
                .frame(width: 112, height: 112)
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(timeString(date, timeZone: timeZone))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var clockBackground: some ShapeStyle {
        LinearGradient(
            colors: [Color.iumrahCardBackground, Color.primary.opacity(0.018)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var clockEyebrow: String {
        switch settings.language {
        case .russian: return "МИРОВОЕ ВРЕМЯ"
        case .turkish: return TurkishLocalization.phrase("WORLD CLOCK")
        case .arabic: return ArabicLocalization.phrase("WORLD CLOCK")
        case .indonesian, .malay, .english: return "WORLD CLOCK"
        case .uzbek: return "DUNYO VAQTI"
        case .uzbekCyrillic: return "ДУНЁ ВАҚТИ"
        }
    }

    private var offsetText: String {
        let holySeconds = city.timeZone.secondsFromGMT(for: Date())
        let localSeconds = TimeZone.autoupdatingCurrent.secondsFromGMT(for: Date())
        let deltaMinutes = (localSeconds - holySeconds) / 60
        guard deltaMinutes != 0 else {
            switch settings.language {
            case .russian: return "Одинаковое время"
            case .turkish: return TurkishLocalization.phrase("Same time")
            case .arabic: return ArabicLocalization.phrase("Same time")
            case .indonesian, .malay, .english: return "Same time"
            case .uzbek: return "Vaqt bir xil"
            case .uzbekCyrillic: return "Вақт бир хил"
            }
        }
        let sign = deltaMinutes > 0 ? "+" : "−"
        let absolute = abs(deltaMinutes)
        let hours = absolute / 60
        let minutes = absolute % 60
        let delta = minutes == 0 ? "\(sign)\(hours) ч" : "\(sign)\(hours):\(String(format: "%02d", minutes))"
        switch settings.language {
        case .russian: return "Ваш город \(delta) относительно Саудии"
        case .turkish: return TurkishLocalization.phrase("Your city \(delta) vs Saudi Arabia")
        case .arabic: return ArabicLocalization.phrase("Your city \(delta) vs Saudi Arabia")
        case .indonesian, .malay, .english: return "Your city \(delta) vs Saudi Arabia"
        case .uzbek: return "Shahringiz Saudiya vaqtiga nisbatan \(delta)"
        case .uzbekCyrillic: return "Шаҳрингиз Саудия вақтига нисбатан \(delta)"
        }
    }

    private func gmtLabel(_ timeZone: TimeZone) -> String {
        let minutes = timeZone.secondsFromGMT(for: Date()) / 60
        let sign = minutes >= 0 ? "+" : "−"
        let absolute = abs(minutes)
        let hours = absolute / 60
        let remainder = absolute % 60
        return remainder == 0 ? "UTC\(sign)\(hours)" : "UTC\(sign)\(hours):\(String(format: "%02d", remainder))"
    }

    private func timeString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct AnalogTravelClock: View {
    let date: Date
    let timeZone: TimeZone
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2

            var face = Path()
            face.addEllipse(in: CGRect(x: center.x - radius + 1, y: center.y - radius + 1, width: (radius - 1) * 2, height: (radius - 1) * 2))
            context.fill(face, with: .color(Color.primary.opacity(0.035)))
            context.stroke(face, with: .color(Color.primary.opacity(0.10)), lineWidth: 0.8)

            for index in 0..<60 {
                let angle = Double(index) / 60 * 2 * Double.pi - Double.pi / 2
                let major = index % 5 == 0
                let outer = radius - 7
                let inner = outer - (major ? 8 : 3)
                var mark = Path()
                mark.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                mark.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                context.stroke(mark, with: .color(Color.primary.opacity(major ? 0.58 : 0.18)), lineWidth: major ? 1.5 : 0.7)
            }

            let calendar = Calendar(identifier: .gregorian)
            var zoned = calendar
            zoned.timeZone = timeZone
            let comps = zoned.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60
            let minute = Double(comps.minute ?? 0) + Double(comps.second ?? 0) / 60
            let second = Double(comps.second ?? 0)

            hand(context: context, center: center, radius: radius * 0.48, angle: hour / 12 * 2 * .pi - .pi / 2, width: 4.2, color: .primary)
            hand(context: context, center: center, radius: radius * 0.68, angle: minute / 60 * 2 * .pi - .pi / 2, width: 2.7, color: .primary)
            hand(context: context, center: center, radius: radius * 0.72, angle: second / 60 * 2 * .pi - .pi / 2, width: 1.2, color: accent)

            var dot = Path()
            dot.addEllipse(in: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .color(accent))
        }
        .accessibilityHidden(true)
    }

    private func hand(context: GraphicsContext, center: CGPoint, radius: CGFloat, angle: Double, width: CGFloat, color: Color) {
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
    }
}

// MARK: - Prayer service

struct IumrahPrayerMoment: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let time: String
    let date: Date

    var symbol: String {
        switch id {
        case "fajr": return "sunrise.fill"
        case "dhuhr": return "sun.max.fill"
        case "asr": return "sun.haze.fill"
        case "maghrib": return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }

    func title(_ language: AppSettingsStore.Language) -> String {
        switch (id, language) {
        case ("fajr", .russian): return "Фаджр"
        case ("dhuhr", .russian): return "Зухр"
        case ("asr", .russian): return "Аср"
        case ("maghrib", .russian): return "Магриб"
        case ("isha", .russian): return "Иша"
        case ("fajr", .uzbek), ("fajr", .uzbekCyrillic): return "Fajr"
        case ("dhuhr", .uzbek), ("dhuhr", .uzbekCyrillic): return "Dhuhr"
        case ("asr", .uzbek), ("asr", .uzbekCyrillic): return "Asr"
        case ("maghrib", .uzbek), ("maghrib", .uzbekCyrillic): return "Maghrib"
        case ("isha", .uzbek), ("isha", .uzbekCyrillic): return "Isha"
        default: return name
        }
    }

    func shortTitle(_ language: AppSettingsStore.Language) -> String {
        switch id {
        case "fajr": return language == .russian ? "Фаджр" : "Fajr"
        case "dhuhr": return language == .russian ? "Зухр" : "Dhuhr"
        case "asr": return language == .russian ? "Аср" : "Asr"
        case "maghrib": return language == .russian ? "Магр." : "Magh."
        default: return language == .russian ? "Иша" : "Isha"
        }
    }
}

struct IumrahPrayerDay: Codable, Hashable {
    let city: IumrahHolyCity
    let dateKey: String
    let prayers: [IumrahPrayerMoment]
    let sunrise: String?
    let tomorrowFajr: IumrahPrayerMoment?
    let cachedAt: Date

    func nextPrayer(after now: Date) -> IumrahPrayerMoment? {
        if let next = prayers.first(where: { $0.date > now }) { return next }
        if let tomorrowFajr, tomorrowFajr.date > now { return tomorrowFajr }
        return nil
    }
}

private actor IumrahPrayerTimesService {
    private let session: URLSession = .shared

    func prayers(for city: IumrahHolyCity, date: Date, forceRefresh: Bool) async throws -> IumrahPrayerDay {
        let key = cacheKey(city: city, date: date)
        var cityCalendar = Calendar(identifier: .gregorian)
        cityCalendar.timeZone = city.timeZone
        if !forceRefresh, let cached = loadCache(key), cityCalendar.isDate(cached.cachedAt, inSameDayAs: date) {
            return cached
        }

        do {
            let value = try await fetch(city: city, date: date)
            saveCache(value, key: key)
            return value
        } catch {
            if let cached = loadCache(key) { return cached }
            throw error
        }
    }

    private func fetch(city: IumrahHolyCity, date: Date) async throws -> IumrahPrayerDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) ?? date.addingTimeInterval(86_400)

        async let todayTimings = fetchTimings(city: city, date: date)
        async let tomorrowTimings = fetchTimings(city: city, date: tomorrow)
        let (today, nextDay) = try await (todayTimings, tomorrowTimings)
        return makeDay(city: city, date: date, timings: today, tomorrowDate: tomorrow, tomorrowTimings: nextDay)
    }

    private func fetchTimings(city: IumrahHolyCity, date: Date) async throws -> AlAdhanTimings {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "dd-MM-yyyy"
        let dateString = formatter.string(from: date)
        let coordinate = city.coordinate
        var components = URLComponents(string: "https://api.aladhan.com/v1/timings/\(dateString)")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.5f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.5f", coordinate.longitude)),
            URLQueryItem(name: "method", value: "4"),
            URLQueryItem(name: "school", value: "0")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        request.setValue("iumrah-iOS/2.0 (https://iumrah.app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(AlAdhanResponse.self, from: data).data.timings
    }

    private func makeDay(city: IumrahHolyCity, date: Date, timings: AlAdhanTimings, tomorrowDate: Date, tomorrowTimings: AlAdhanTimings) -> IumrahPrayerDay {
        let clean: (String) -> String = { raw in
            raw.split(separator: " ").first.map(String.init) ?? raw
        }
        let values: [(String, String, String)] = [
            ("fajr", "Fajr", clean(timings.Fajr)),
            ("dhuhr", "Dhuhr", clean(timings.Dhuhr)),
            ("asr", "Asr", clean(timings.Asr)),
            ("maghrib", "Maghrib", clean(timings.Maghrib)),
            ("isha", "Isha", clean(timings.Isha))
        ]
        let moments = values.compactMap { id, name, time -> IumrahPrayerMoment? in
            guard let parsed = combine(day: date, time: time, timeZone: city.timeZone) else { return nil }
            return IumrahPrayerMoment(id: id, name: name, time: time, date: parsed)
        }
        let keyFormatter = DateFormatter()
        keyFormatter.timeZone = city.timeZone
        keyFormatter.dateFormat = "yyyy-MM-dd"
        let tomorrowFajrTime = clean(tomorrowTimings.Fajr)
        let tomorrowFajr = combine(day: tomorrowDate, time: tomorrowFajrTime, timeZone: city.timeZone).map {
            IumrahPrayerMoment(id: "fajr", name: "Fajr", time: tomorrowFajrTime, date: $0)
        }
        return IumrahPrayerDay(
            city: city,
            dateKey: keyFormatter.string(from: date),
            prayers: moments,
            sunrise: clean(timings.Sunrise),
            tomorrowFajr: tomorrowFajr,
            cachedAt: Date()
        )
    }

    private func combine(day: Date, time: String, timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        components.hour = parts[0]
        components.minute = parts[1]
        components.second = 0
        components.timeZone = timeZone
        return calendar.date(from: components)
    }

    private func cacheKey(city: IumrahHolyCity, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "iumrah.prayers.\(city.rawValue).\(formatter.string(from: date))"
    }

    private func loadCache(_ key: String) -> IumrahPrayerDay? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IumrahPrayerDay.self, from: data)
    }

    private func saveCache(_ value: IumrahPrayerDay, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct AlAdhanResponse: Decodable {
    let data: AlAdhanData
}
private struct AlAdhanData: Decodable { let timings: AlAdhanTimings }
private struct AlAdhanTimings: Decodable {
    let Fajr: String
    let Sunrise: String
    let Dhuhr: String
    let Asr: String
    let Maghrib: String
    let Isha: String
}

// MARK: - Weather service

struct IumrahWeatherSnapshot: Codable, Hashable {
    let city: IumrahHolyCity
    let currentTemperature: Double
    let currentCondition: IumrahWeatherCondition
    let days: [IumrahWeatherDay]
    let hourly: [IumrahWeatherHour]?
    let fetchedAt: Date

    func updatedLabel(language: AppSettingsStore.Language, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        switch language {
        case .russian: return "обновлено \(formatter.string(from: fetchedAt))"
        case .turkish: return TurkishLocalization.phrase("updated \(formatter.string(from: fetchedAt))")
        case .arabic: return ArabicLocalization.phrase("updated \(formatter.string(from: fetchedAt))")
        case .indonesian, .malay, .english: return "updated \(formatter.string(from: fetchedAt))"
        case .uzbek: return "yangilandi \(formatter.string(from: fetchedAt))"
        case .uzbekCyrillic: return "янгиланди \(formatter.string(from: fetchedAt))"
        }
    }
}

struct IumrahWeatherHour: Codable, Hashable, Identifiable {
    let date: Date
    let temperature: Double
    let condition: IumrahWeatherCondition
    var id: Date { date }
}

struct IumrahWeatherDay: Identifiable, Codable, Hashable {
    let date: Date
    let high: Double
    let low: Double
    let condition: IumrahWeatherCondition
    var id: Date { date }

    func dayLabel(language: AppSettingsStore.Language, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: Date()) {
            switch language {
            case .russian: return "Сег."
            case .turkish: return TurkishLocalization.phrase("Today")
            case .arabic: return ArabicLocalization.phrase("Today")
            case .indonesian, .malay, .english: return "Today"
            case .uzbek: return "Bugun"
            case .uzbekCyrillic: return "Бугун"
            }
        }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        switch language {
        case .russian: formatter.locale = Locale(identifier: "ru_RU")
        case .turkish: formatter.locale = Locale(identifier: "tr_TR")
        case .arabic: formatter.locale = Locale(identifier: "ar_SA")
        case .indonesian, .malay, .english: formatter.locale = Locale(identifier: "en_US")
        case .uzbek: formatter.locale = Locale(identifier: "uz_Latn_UZ")
        case .uzbekCyrillic: formatter.locale = Locale(identifier: "uz_Cyrl_UZ")
        }
        formatter.dateFormat = "EE"
        return formatter.string(from: date).capitalized
    }
}

enum IumrahWeatherCondition: String, Codable, Hashable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case rain
    case showers
    case thunder
    case snow
    case unknown

    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .rain: return "cloud.rain.fill"
        case .showers: return "cloud.heavyrain.fill"
        case .thunder: return "cloud.bolt.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .unknown: return "cloud.fill"
        }
    }

    var primaryColor: Color {
        switch self {
        case .clear: return .yellow
        case .partlyCloudy: return .yellow
        case .cloudy, .fog: return Color(uiColor: .systemGray)
        case .rain, .showers: return .blue
        case .thunder: return .yellow
        case .snow: return Color(uiColor: .systemCyan)
        case .unknown: return Color(uiColor: .systemGray2)
        }
    }

    var secondaryColor: Color {
        switch self {
        case .clear: return .orange
        case .partlyCloudy: return Color(uiColor: .systemBlue)
        case .cloudy, .fog: return Color(uiColor: .systemGray3)
        case .rain, .showers: return Color(uiColor: .systemCyan)
        case .thunder: return Color(uiColor: .systemIndigo)
        case .snow: return .white
        case .unknown: return Color(uiColor: .systemGray4)
        }
    }

    func localized(_ language: AppSettingsStore.Language) -> String {
        switch (self, language) {
        case (.clear, .russian): return "Ясно"
        case (.partlyCloudy, .russian): return "Переменная облачность"
        case (.cloudy, .russian): return "Облачно"
        case (.fog, .russian): return "Туман"
        case (.rain, .russian), (.showers, .russian): return "Дождь"
        case (.thunder, .russian): return "Гроза"
        case (.snow, .russian): return "Снег"
        case (.clear, .turkish): return TurkishLocalization.phrase("Clear")
        case (.clear, .arabic): return ArabicLocalization.phrase("Clear")
        case (.clear, .indonesian), (.clear, .malay), (.clear, .english): return "Clear"
        case (.partlyCloudy, .turkish): return TurkishLocalization.phrase("Partly cloudy")
        case (.partlyCloudy, .arabic): return ArabicLocalization.phrase("Partly cloudy")
        case (.partlyCloudy, .indonesian), (.partlyCloudy, .malay), (.partlyCloudy, .english): return "Partly cloudy"
        case (.cloudy, .turkish): return TurkishLocalization.phrase("Cloudy")
        case (.cloudy, .arabic): return ArabicLocalization.phrase("Cloudy")
        case (.cloudy, .indonesian), (.cloudy, .malay), (.cloudy, .english): return "Cloudy"
        case (.fog, .turkish): return TurkishLocalization.phrase("Fog")
        case (.fog, .arabic): return ArabicLocalization.phrase("Fog")
        case (.fog, .indonesian), (.fog, .malay), (.fog, .english): return "Fog"
        case (.rain, .turkish), (.showers, .turkish): return TurkishLocalization.phrase("Rain")
        case (.rain, .arabic), (.showers, .arabic): return ArabicLocalization.phrase("Rain")
        case (.rain, .indonesian), (.rain, .malay), (.rain, .english), (.showers, .indonesian), (.showers, .malay), (.showers, .english): return "Rain"
        case (.thunder, .turkish): return TurkishLocalization.phrase("Thunderstorm")
        case (.thunder, .arabic): return ArabicLocalization.phrase("Thunderstorm")
        case (.thunder, .indonesian), (.thunder, .malay), (.thunder, .english): return "Thunderstorm"
        case (.snow, .turkish): return TurkishLocalization.phrase("Snow")
        case (.snow, .arabic): return ArabicLocalization.phrase("Snow")
        case (.snow, .indonesian), (.snow, .malay), (.snow, .english): return "Snow"
        case (.clear, .uzbek), (.clear, .uzbekCyrillic): return "Ochiq"
        case (.partlyCloudy, .uzbek), (.partlyCloudy, .uzbekCyrillic): return "Qisman bulutli"
        case (.cloudy, .uzbek), (.cloudy, .uzbekCyrillic): return "Bulutli"
        case (.fog, .uzbek), (.fog, .uzbekCyrillic): return "Tuman"
        case (.rain, .uzbek), (.showers, .uzbek), (.rain, .uzbekCyrillic), (.showers, .uzbekCyrillic): return "Yomg‘ir"
        case (.thunder, .uzbek), (.thunder, .uzbekCyrillic): return "Momaqaldiroq"
        case (.snow, .uzbek), (.snow, .uzbekCyrillic): return "Qor"
        default: return "Weather"
        }
    }

    static func fromMET(_ raw: String?) -> IumrahWeatherCondition {
        guard let raw = raw?.lowercased() else { return .unknown }
        if raw.contains("thunder") { return .thunder }
        if raw.contains("snow") || raw.contains("sleet") { return .snow }
        if raw.contains("rainshowers") || raw.contains("showers") { return .showers }
        if raw.contains("rain") { return .rain }
        if raw.contains("fog") { return .fog }
        if raw.contains("partlycloudy") || raw.contains("fair") { return .partlyCloudy }
        if raw.contains("cloudy") { return .cloudy }
        if raw.contains("clearsky") { return .clear }
        return .unknown
    }
}

private actor IumrahWeatherService {
    private let session: URLSession = .shared
    private let maxAge: TimeInterval = 30 * 60

    func forecast(for city: IumrahHolyCity, forceRefresh: Bool) async throws -> IumrahWeatherSnapshot {
        let key = "iumrah.weather.\(city.rawValue)"
        if !forceRefresh, let cached = loadCache(key), Date().timeIntervalSince(cached.fetchedAt) < maxAge {
            return cached
        }

        do {
            let snapshot = try await fetch(city: city)
            saveCache(snapshot, key: key)
            return snapshot
        } catch {
            if let cached = loadCache(key) { return cached }
            throw error
        }
    }

    private func fetch(city: IumrahHolyCity) async throws -> IumrahWeatherSnapshot {
        let c = city.coordinate
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.4f", c.latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.4f", c.longitude))
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("iumrah-iOS/2.0 (https://iumrah.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder.metWeather.decode(METLocationForecast.self, from: data)
        guard let current = decoded.properties.timeseries.first else { throw URLError(.cannotParseResponse) }

        let currentTemp = current.data.instant.details.airTemperature
        let currentCondition = IumrahWeatherCondition.fromMET(current.data.next1Hours?.summary.symbolCode ?? current.data.next6Hours?.summary.symbolCode)
        let days = aggregateDays(decoded.properties.timeseries, city: city)
        let hours = decoded.properties.timeseries
            .filter { $0.time >= Date().addingTimeInterval(-3600) }
            .prefix(24)
            .map { entry in
                IumrahWeatherHour(
                    date: entry.time,
                    temperature: entry.data.instant.details.airTemperature,
                    condition: .fromMET(entry.data.next1Hours?.summary.symbolCode ?? entry.data.next6Hours?.summary.symbolCode)
                )
            }
        return IumrahWeatherSnapshot(city: city, currentTemperature: currentTemp, currentCondition: currentCondition, days: days, hourly: hours, fetchedAt: Date())
    }

    private func aggregateDays(_ series: [METTimeSeries], city: IumrahHolyCity) -> [IumrahWeatherDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.timeZone
        let grouped = Dictionary(grouping: series) { calendar.startOfDay(for: $0.time) }
        return grouped.keys.sorted().prefix(7).compactMap { day in
            guard let items = grouped[day], !items.isEmpty else { return nil }
            let temperatures = items.map { $0.data.instant.details.airTemperature }
            guard let low = temperatures.min(), let high = temperatures.max() else { return nil }
            let midday = items.min { lhs, rhs in
                abs(calendar.component(.hour, from: lhs.time) - 12) < abs(calendar.component(.hour, from: rhs.time) - 12)
            }
            let code = midday?.data.next6Hours?.summary.symbolCode ?? midday?.data.next1Hours?.summary.symbolCode
            return IumrahWeatherDay(date: day, high: high, low: low, condition: .fromMET(code))
        }
    }

    private func loadCache(_ key: String) -> IumrahWeatherSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(IumrahWeatherSnapshot.self, from: data)
    }

    private func saveCache(_ value: IumrahWeatherSnapshot, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private struct METLocationForecast: Decodable {
    let properties: METProperties
}
private struct METProperties: Decodable { let timeseries: [METTimeSeries] }
private struct METTimeSeries: Decodable {
    let time: Date
    let data: METData
}
private struct METData: Decodable {
    let instant: METInstant
    let next1Hours: METPeriod?
    let next6Hours: METPeriod?

    enum CodingKeys: String, CodingKey {
        case instant
        case next1Hours = "next_1_hours"
        case next6Hours = "next_6_hours"
    }
}
private struct METInstant: Decodable { let details: METInstantDetails }
private struct METInstantDetails: Decodable {
    let airTemperature: Double
    enum CodingKeys: String, CodingKey { case airTemperature = "air_temperature" }
}
private struct METPeriod: Decodable { let summary: METSummary }
private struct METSummary: Decodable {
    let symbolCode: String?
    enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
}

private extension JSONDecoder {
    static var metWeather: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// The prayer/weather/clocks dashboard was previously visible only when a
// booking existed. Expose the same live services directly from Home.
struct JourneyTravelInfoScreen: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let initialPage: JourneyInfoPage

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                JourneyTravelInfoView(initialPage: initialPage)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 36)
        }
        .background(Color.iumrahPageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch settings.language {
        case .russian: return "Погода и время"
        case .uzbek: return "Ob-havo va vaqt"
        case .uzbekCyrillic: return "Об-ҳаво ва вақт"
        case .turkish: return "Hava ve saat"
        case .indonesian: return "Cuaca dan waktu"
        case .malay: return "Cuaca dan waktu"
        case .arabic: return ArabicLocalization.phrase("Weather & time")
        case .english: return "Weather & time"
        }
    }

    private var subtitle: String {
        switch settings.language {
        case .russian: return "Мекка и Медина · прогноз, молитвы и мировое время"
        case .uzbek: return "Makka va Madina · ob-havo, namoz va vaqt"
        case .uzbekCyrillic: return "Макка ва Мадина · об-ҳаво, намоз ва вақт"
        case .turkish: return "Mekke ve Medine · hava, namaz ve saat"
        case .indonesian: return "Makkah dan Madinah · cuaca, salat, waktu"
        case .malay: return "Makkah dan Madinah · cuaca, solat, waktu"
        case .arabic: return ArabicLocalization.phrase("Makkah and Madinah · forecast, prayer and clocks")
        case .english: return "Makkah and Madinah · forecast, prayer and clocks"
        }
    }
}


// Full-page, city-specific weather. All observations are received from MET Norway;
// unknown hours/days are never populated with synthetic temperatures.
struct IumrahWeatherFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var model = JourneyTravelInfoModel()
    @AppStorage("iumrah.booking.travelInfo.city") private var selectedCityRaw = IumrahHolyCity.makkah.rawValue

    private var city: IumrahHolyCity { IumrahHolyCity(rawValue: selectedCityRaw) ?? .makkah }
    private var forecast: IumrahWeatherSnapshot? { model.weather }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.035, green: 0.055, blue: 0.16), Color(red: 0.13, green: 0.20, blue: 0.38), Color(red: 0.23, green: 0.35, blue: 0.53)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack {
                        Picker("", selection: $selectedCityRaw) {
                            ForEach(IumrahHolyCity.allCases) { city in
                                Text(city.title(settings.language)).tag(city.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        Spacer(minLength: 20)
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .tint(.white)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 8) {
                        Text(city.title(settings.language))
                            .font(.system(size: 36, weight: .regular))
                        if let forecast {
                            Text("\(Int(forecast.currentTemperature.rounded()))°")
                                .font(.system(size: 104, weight: .ultraLight, design: .rounded))
                                .minimumScaleFactor(0.7)
                            Text(forecast.currentCondition.localized(settings.language))
                                .font(.title3.weight(.medium))
                            if let today = forecast.days.first {
                                Text("\(label("Max", "Макс.")): \(Int(today.high.rounded()))° · \(label("Min", "Мин.")): \(Int(today.low.rounded()))°")
                                    .font(.headline)
                            }
                        } else if model.isRefreshing {
                            ProgressView().tint(.white).padding(36)
                        } else {
                            Text(label("Weather temporarily unavailable", "Прогноз временно недоступен"))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)

                    weatherPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            Label(label("Hourly forecast", "Почасовой прогноз"), systemImage: "clock")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            if let hours = forecast?.hourly, !hours.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 23) {
                                        ForEach(hours) { hour in
                                            VStack(spacing: 14) {
                                                Text(hourText(hour.date))
                                                    .font(.caption.weight(.semibold))
                                                Image(systemName: hour.condition.symbol)
                                                    .symbolRenderingMode(.multicolor)
                                                    .font(.title3)
                                                Text("\(Int(hour.temperature.rounded()))°")
                                                    .font(.headline)
                                            }
                                            .frame(minWidth: 46)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                }
                            } else {
                                Text(label("No hourly forecast", "Нет почасового прогноза"))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                        }
                    }

                    weatherPanel {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(label("Next days", "Прогноз по дням"), systemImage: "calendar")
                                .font(.subheadline.weight(.semibold))
                                .padding(.bottom, 14)
                            if let forecast {
                                ForEach(forecast.days) { day in
                                    HStack(spacing: 12) {
                                        Text(day.dayLabel(language: settings.language, timeZone: city.timeZone))
                                            .frame(width: 76, alignment: .leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: day.condition.symbol)
                                            .symbolRenderingMode(.multicolor)
                                            .frame(width: 30)
                                        Text("\(Int(day.low.rounded()))°")
                                            .foregroundStyle(.white.opacity(0.68))
                                        Capsule()
                                            .fill(LinearGradient(colors: [.blue, .orange], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: 75, height: 5)
                                        Text("\(Int(day.high.rounded()))°")
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.vertical, 9)
                                    if day.id != forecast.days.last?.id { Divider().overlay(.white.opacity(0.12)) }
                                }
                            }
                        }
                    }
                    Text(label("Forecast · MET Norway · Updated from the latest available observations", "Прогноз · MET Norway · По последним доступным данным"))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .padding(.bottom, 22)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
            }
            .refreshable { await model.refresh(city: city, force: true) }
        }
        .task(id: city.rawValue) { await model.refresh(city: city) }
        .preferredColorScheme(.dark)
    }

    private func weatherPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.09), lineWidth: 0.7))
    }

    private func hourText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = city.timeZone
        formatter.dateFormat = "HH"
        return formatter.string(from: date)
    }

    private func label(_ english: String, _ russian: String) -> String {
        switch settings.language {
        case .russian: return russian
        case .arabic: return ArabicLocalization.phrase(english)
        case .turkish: return TurkishLocalization.phrase(english)
        case .indonesian: return IndonesianLocalization.phrase(english)
        case .malay: return MalayLocalization.phrase(english)
        case .english, .uzbek, .uzbekCyrillic: return english
        }
    }
}
