import SwiftUI
import CoreLocation

// Prayer Times is an immersive destination (not a scrolling storefront).
// Calculations, city selection, alerts and wallpapers all reuse the existing
// persisted prayer services. No prayer or notification algorithms are changed.
struct IumrahPrayerTimesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore
    @StateObject private var state = IumrahPrayerState()
    @StateObject private var location = IumrahPrayerLocation()
    @StateObject private var qibla = IumrahPrayerQiblaHeading()

    @State private var chosenDate = Date()
    @State private var showingCity = false
    @State private var showingCalculation = false
    @State private var showingWallpapers = false
    @State private var showingSchedule = false
    @State private var showingDailySchedule = false
    @State private var showingOptions = false
    @State private var showingNotifications = false
    @State private var editingPrayer: IumrahPrayerKind?
    @State private var showingQibla = false
    @AppStorage("iumrah.booking.travelInfo.city") private var holyCityRaw = "makkah"

    private var schedule: IumrahPrayerSchedule {
        IumrahPrayerCalculator.calculate(on: chosenDate, place: state.place, method: state.method, hanafi: state.hanafi)
    }

    private var isToday: Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = state.place.timeZone
        return calendar.isDate(chosenDate, inSameDayAs: Date())
    }

    var body: some View {
        ZStack {
            immersiveWallpaper

            VStack(spacing: 0) {
                navigationHeader
                Spacer(minLength: 36)
                if showingQibla { qiblaContent }
                else if showingSchedule { immersiveScheduleContent }
                else { countdownContent }
                Spacer(minLength: 34)
                bottomActions
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.04, green: 0.16, blue: 0.14))
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .gesture(DragGesture(minimumDistance: 35)
            .onEnded { value in
                if value.translation.height < -90, !showingQibla {
                    IumrahHaptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { showingSchedule = true }
                } else if value.translation.height > 90, showingSchedule {
                    IumrahHaptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) { showingSchedule = false }
                } else if abs(value.translation.width) > 100 {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        showingQibla.toggle()
                        showingSchedule = false
                    }
                    IumrahHaptics.selection()
                    if showingQibla { qibla.activate() } else { qibla.deactivate() }
                }
            })
        .sheet(isPresented: $showingDailySchedule) { scheduleSheet }
        .sheet(item: $editingPrayer) { kind in
            IumrahPrayerNotificationSheet(start: kind, state: state)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingCity) {
            IumrahPrayerCitySheet(state: state, location: location)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingCalculation) {
            IumrahPrayerMethodSheet(state: state)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingWallpapers) {
            IumrahPrayerWallpaperSheet(state: state)
                .environmentObject(settings)
        }
        .sheet(isPresented: $showingNotifications) {
            IumrahPrayerNotificationSheet(start: .fajr, state: state)
                .environmentObject(settings)
        }
        .confirmationDialog(ui("Settings", "Настройки", "Sozlamalar", "الإعدادات"), isPresented: $showingOptions) {
            Button(ui("Prayer notifications", "Уведомления о намазе", "Namoz eslatmalari", "إشعارات الصلاة")) {
                showingNotifications = true
            }
            Button(ui("City and location", "Город и местоположение", "Shahar va joylashuv", "المدينة والموقع")) {
                showingCity = true
            }
            Button(ui("Calculation method", "Метод расчёта", "Hisoblash usuli", "طريقة الحساب")) {
                showingCalculation = true
            }
            Button(ui("Wallpaper", "Обои", "Fon rasmi", "الخلفية")) {
                showingWallpapers = true
            }
        }
        .task { _ = await IumrahPrayerNotifications.synchronize(state: state) }
        .onChange(of: state.place) { _, _ in refreshNotifications() }
        .onChange(of: state.method) { _, _ in refreshNotifications() }
        .onChange(of: state.hanafi) { _, _ in refreshNotifications() }
        .onDisappear { qibla.deactivate() }
    }

    private var immersiveWallpaper: some View {
        GeometryReader { geometry in
            Image(state.wallpaper.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [Color.black.opacity(0.51), Color.black.opacity(0.20), Color.black.opacity(0.40)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private var navigationHeader: some View {
        VStack(spacing: 13) {
            HStack(spacing: 10) {
                roundAction("xmark", label: ui("Close", "Закрыть", "Yopish", "إغلاق")) { dismiss() }
                Spacer(minLength: 0)
                Button {
                    IumrahHaptics.selection()
                    showingCity = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10, weight: .bold))
                        VStack(spacing: 3) {
                            Text(state.place.name)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                            Text(hijriDateLabel(Date()))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                roundAction("slider.horizontal.3", label: ui("Settings", "Настройки", "Sozlamalar", "الإعدادات")) {
                    showingOptions = true
                }
            }
            if state.place.id == "makkah" || state.place.id == "madinah" {
                HStack(spacing: 2) {
                    holyCityButton("makkah", label: ui("Makkah", "Мекка", "Makka", "مكة"))
                    holyCityButton("madinah", label: ui("Madinah", "Медина", "Madina", "المدينة"))
                }
                .padding(4)
                .background(.black.opacity(0.20), in: Capsule())
                .frame(maxWidth: 250)
            }
        }
    }

    private func holyCityButton(_ city: String, label: String) -> some View {
        Button {
            guard state.place.id != city,
                  let place = IumrahPrayerPlace.presets.first(where: { $0.id == city }) else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                state.place = place
                holyCityRaw = city
            }
            IumrahHaptics.selection()
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if state.place.id == city {
                        Capsule().fill(Color.white.opacity(0.20))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var countdownContent: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let upcoming = IumrahPrayerCalculator.upcoming(now: context.date, place: state.place,
                method: state.method, hanafi: state.hanafi)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text(ui("Next prayer", "Следующий намаз", "Keyingi namoz", "الصلاة القادمة"))
                    Circle().fill(.white.opacity(0.78)).frame(width: 5, height: 5)
                    Text(upcoming.map { prayerTitle($0.kind) } ?? "—")
                    Text(upcoming.map { timeText($0.date) } ?? "--:--")
                        .monospacedDigit()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)

                Text(upcoming.map { countdown($0.date, since: context.date) } ?? "--:--:--")
                    .font(.system(size: 60, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.white)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(ui("Time until next prayer", "До следующего намаза", "Keyingi namozgacha", "الوقت حتى الصلاة التالية"))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    // The source video uses a translucent prayer list ON the wallpaper, not
    // a white bottom sheet. Tapping any row opens that prayer's real settings.
    private var immersiveScheduleContent: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let prayerKinds: [IumrahPrayerKind] = [.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]
            let prayerOnly: [IumrahPrayerKind] = [.fajr, .dhuhr, .asr, .maghrib, .isha]
            let active = schedule.entries
                .filter { prayerOnly.contains($0.kind) && $0.date <= context.date }
                .max(by: { $0.date < $1.date })?.kind
            let upcoming = IumrahPrayerCalculator.upcoming(
                now: context.date, place: state.place, method: state.method, hanafi: state.hanafi)
            VStack(spacing: 0) {
                ForEach(prayerKinds) { kind in
                    if let prayerTime = schedule.date(for: kind) {
                        Button {
                            IumrahHaptics.selection()
                            editingPrayer = kind
                        } label: {
                            HStack(spacing: 10) {
                                Text(prayerTitle(kind))
                                    .font(.system(size: 14, weight: kind == active ? .bold : .medium))
                                    .lineLimit(1)
                                Spacer(minLength: 5)
                                if state.preference(for: kind).enabled {
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.70))
                                }
                                Text(timeText(prayerTime))
                                    .font(.system(size: 14, weight: kind == active ? .bold : .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 42)
                            .background(kind == active ? Color(red: 0.04, green: 0.59, blue: 0.41).opacity(0.72) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let upcoming {
                    HStack(spacing: 8) {
                        Text(prayerTitle(upcoming.kind))
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Text(countdown(upcoming.date, since: context.date))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 15)
                    .frame(height: 36)
                    .background(Color(red: 0.02, green: 0.56, blue: 0.39))
                }
            }
            .frame(maxWidth: 350)
            .background(Color.black.opacity(0.43), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.20), radius: 25, y: 9)
            .frame(maxWidth: .infinity)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var qiblaContent: some View {
        VStack(spacing: 24) {
            Text(ui("Qibla", "Кибла", "Qibla", "القبلة"))
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.72), lineWidth: 2)
                ForEach(0..<72, id: \.self) { tick in
                    Capsule()
                        .fill(Color.white.opacity(tick.isMultiple(of: 6) ? 0.9 : 0.28))
                        .frame(width: tick.isMultiple(of: 6) ? 2 : 1, height: tick.isMultiple(of: 6) ? 15 : 7)
                        .offset(y: -119)
                        .rotationEffect(.degrees(Double(tick) * 5))
                }
                VStack {
                    Text("N").offset(y: -91)
                    Spacer()
                    Text("S").offset(y: 91)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 85, weight: .ultraLight))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(qibla.relativeQiblaBearing ?? 0))
                    .opacity(qibla.relativeQiblaBearing == nil ? 0.30 : 1)
                    .animation(.easeOut(duration: 0.25), value: qibla.relativeQiblaBearing)
                Circle().fill(.white).frame(width: 11, height: 11)
            }
            .frame(width: 255, height: 255)
            .environment(\.layoutDirection, .leftToRight)
            if qibla.relativeQiblaBearing == nil {
                Button {
                    qibla.activate()
                } label: {
                    Label(ui("Allow location for Qibla direction", "Разрешите геолокацию для Киблы", "Qibla uchun joylashuvga ruxsat bering", "اسمح بالموقع لتحديد القبلة"), systemImage: "location")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.86))
            } else {
                Text(ui("Turn your phone toward the Qibla", "Поверните телефон к Кибле", "Telefoningizni Qiblaga qarating", "وجّه هاتفك نحو القبلة"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomActions: some View {
        VStack(spacing: 22) {
            if !showingQibla {
                Button {
                    IumrahHaptics.selection()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                        showingSchedule.toggle()
                    }
                } label: {
                    Image(systemName: showingSchedule ? "chevron.down" : "chevron.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 65, height: 21)
                        .iumrahGlass(in: Capsule(), interactive: true, tint: Color.black.opacity(0.20), chrome: true)
                }
                .accessibilityLabel(ui("Show prayer schedule", "Показать расписание", "Jadvalni ko‘rish", "عرض مواقيت الصلاة"))
            }
            HStack(alignment: .center) {
                roundAction(showingQibla ? "clock" : "location.north.line.fill",
                            label: showingQibla ? ui("Prayer times", "Время молитв", "Namoz vaqtlari", "مواقيت الصلاة") : ui("Qibla", "Кибла", "Qibla", "القبلة")) {
                    withAnimation(.easeInOut(duration: 0.27)) {
                        showingQibla.toggle()
                        showingSchedule = false
                    }
                    IumrahHaptics.selection()
                    if showingQibla { qibla.activate() } else { qibla.deactivate() }
                }
                Spacer()
                if !showingQibla {
                    Button {
                        IumrahHaptics.selection()
                        if showingSchedule {
                            showingDailySchedule = true
                        } else {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.88)) {
                                showingSchedule = true
                            }
                        }
                    } label: {
                        Text(showingSchedule
                            ? ui("Full schedule", "Календарь", "Taqvim", "التقويم")
                            : ui("Prayer times", "Расписание", "Jadval", "مواقيت الصلاة"))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .iumrahGlass(in: Capsule(), interactive: true, tint: Color.black.opacity(0.20), chrome: true)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                roundAction("ellipsis", label: ui("More", "Ещё", "Yana", "المزيد")) { showingOptions = true }
            }
        }
    }

    private func roundAction(_ symbol: String, label: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 43, height: 43)
                .iumrahGlass(in: Circle(), interactive: true, tint: Color.black.opacity(0.20), chrome: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var scheduleSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 19) {
                    dateSelector
                    scheduleCard
                    additionalPrayers
                    Text(ui("Times are calculated for the chosen location and method. Local mosque times may differ.",
                        "Время рассчитано по выбранным координатам и методу. В местной мечети оно может отличаться.",
                        "Vaqtlar tanlangan joylashuv bo‘yicha hisoblangan. Mahalliy masjid vaqti farq qilishi mumkin.",
                        "تُحسب المواقيت حسب الموقع وطريقة الحساب المحددين، وقد تختلف عن أوقات المسجد المحلي."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle(ui("Prayer times", "Время молитв", "Namoz vaqtlari", "مواقيت الصلاة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ui("Done", "Готово", "Tayyor", "تم")) { showingDailySchedule = false }
                }
            }
            .background(Color.iumrahPageBackground)
        }
        .environment(\.colorScheme, .light)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var dateSelector: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(ui("Daily schedule", "Расписание на день", "Kunlik jadval", "الجدول اليومي"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(dateLabel(chosenDate))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { moveDate(-1) } label: { Image(systemName: "chevron.backward") }
            Button { chosenDate = Date() } label: { Image(systemName: "calendar") }
                .disabled(isToday)
            Button { moveDate(1) } label: { Image(systemName: "chevron.forward") }
        }
        .buttonStyle(.bordered)
        .font(.system(size: 15, weight: .semibold))
    }

    private var scheduleCard: some View {
        VStack(spacing: 0) {
            ForEach([IumrahPrayerKind.fajr, .sunrise, .dhuhr, .asr, .maghrib, .isha]) { kind in
                if let time = schedule.date(for: kind) {
                    Button {
                        IumrahHaptics.selection()
                        editingPrayer = kind
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 16))
                                .frame(width: 32)
                                .foregroundStyle(Color.teal)
                            Text(prayerTitle(kind))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Spacer()
                            if state.preference(for: kind).enabled {
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            }
                            Text(timeText(time))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .environment(\.layoutDirection, .leftToRight)
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if kind != .isha { Divider().padding(.leading, 50) }
                }
            }
        }
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var additionalPrayers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ui("Additional prayers", "Дополнительные молитвы", "Qo‘shimcha namozlar", "صلوات إضافية"))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            ForEach([IumrahPrayerKind.duha, .tahajjud]) { kind in
                if let time = schedule.date(for: kind) {
                    Button { editingPrayer = kind } label: {
                        HStack {
                            Label(prayerTitle(kind), systemImage: kind.symbol)
                            Spacer()
                            Text(timeText(time))
                                .monospacedDigit()
                                .environment(\.layoutDirection, .leftToRight)
                            Image(systemName: "chevron.forward")
                                .font(.caption)
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(15)
                        .foregroundStyle(.primary)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func moveDate(_ offset: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = state.place.timeZone
        if let value = calendar.date(byAdding: .day, value: offset, to: chosenDate) {
            chosenDate = value
            IumrahHaptics.selection()
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = state.place.timeZone
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func hijriDateLabel(_ date: Date) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = state.place.timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.timeZone = state.place.timeZone
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private var localeIdentifier: String {
        switch settings.language.rawValue.lowercased() {
        case "arabic", "ar": return "ar_SA"
        case "russian", "ru": return "ru_RU"
        case "uzbek", "uz": return "uz_UZ"
        case "uzbekcyrillic", "uz-cyrl": return "uz_UZ@cyrillic"
        case "turkish", "tr": return "tr_TR"
        case "indonesian", "id": return "id_ID"
        case "malay", "ms": return "ms_MY"
        default: return "en_US"
        }
    }

    private func countdown(_ date: Date, since now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
    private func timeText(_ date: Date) -> String { schedule.displayTime(date) }
    private func refreshNotifications() {
        Task { _ = await IumrahPrayerNotifications.synchronize(state: state) }
    }

    private func prayerTitle(_ kind: IumrahPrayerKind) -> String {
        switch kind {
        case .fajr: return ui("Fajr", "Фаджр", "Bomdod", "الفجر")
        case .sunrise: return ui("Sunrise", "Восход", "Quyosh chiqishi", "الشروق")
        case .dhuhr: return ui("Dhuhr", "Зухр", "Peshin", "الظهر")
        case .asr: return ui("Asr", "Аср", "Asr", "العصر")
        case .maghrib: return ui("Maghrib", "Магриб", "Shom", "المغرب")
        case .isha: return ui("Isha", "Иша", "Xufton", "العشاء")
        case .duha: return ui("Duha", "Духа", "Zuho", "الضحى")
        case .tahajjud: return ui("Tahajjud", "Тахаджуд", "Tahajjud", "التهجد")
        }
    }

    private func ui(_ en: String, _ ru: String, _ uz: String, _ ar: String) -> String {
        // The raw language identifier avoids introducing an exhaustive enum
        // switch dependency: this page compiles both before and after the
        // global Arabic Language enum update is installed.
        switch settings.language.rawValue {
        case "ar": return ar
        case "ru": return ru
        case "uz": return uz
        case "uz-cyrl": return IumrahPrayerImmersiveTranslations.cyrillic[en] ?? uz
        case "tr": return IumrahPrayerImmersiveTranslations.turkish[en] ?? en
        case "id": return IumrahPrayerImmersiveTranslations.indonesian[en] ?? en
        case "ms": return IumrahPrayerImmersiveTranslations.malay[en] ?? en
        default: return en
        }
    }
}

private enum IumrahPrayerImmersiveTranslations {
    static let cyrillic: [String: String] = [
        "Settings": "Созламалар", "Prayer notifications": "Намоз эслатмалари", "City and location": "Шаҳар ва жойлашув",
        "Calculation method": "Ҳисоблаш усули", "Wallpaper": "Фон расми", "Close": "Ёпиш", "Makkah": "Макка", "Madinah": "Мадина",
        "Next prayer": "Кейинги намоз", "Time until next prayer": "Кейинги намозгача", "Qibla": "Қибла",
        "Allow location for Qibla direction": "Қибла учун жойлашувга рухсат беринг",
        "Turn your phone toward the Qibla": "Телефонни Қиблага қаратинг", "Show prayer schedule": "Намоз жадвалини кўриш",
        "Prayer times": "Намоз вақтлари", "More": "Яна", "Done": "Тайёр", "Daily schedule": "Кунлик жадвал",
        "Additional prayers": "Қўшимча намозлар", "Fajr": "Бомдод", "Sunrise": "Қуёш чиқиши", "Dhuhr": "Пешин",
        "Asr": "Аср", "Maghrib": "Шом", "Isha": "Хуфтон", "Duha": "Зуҳо", "Tahajjud": "Таҳажжуд",
        "Times are calculated for the chosen location and method. Local mosque times may differ.": "Вақтлар танланган жойлашув ва усулга кўра ҳисобланади. Маҳаллий масжид вақтлари фарқ қилиши мумкин."
    ]
    static let turkish: [String: String] = [
        "Settings": "Ayarlar", "Prayer notifications": "Namaz bildirimleri", "City and location": "Şehir ve konum",
        "Calculation method": "Hesaplama yöntemi", "Wallpaper": "Duvar kağıdı", "Close": "Kapat", "Makkah": "Mekke", "Madinah": "Medine",
        "Next prayer": "Sonraki namaz", "Time until next prayer": "Sonraki namaza kalan süre", "Qibla": "Kıble",
        "Allow location for Qibla direction": "Kıble için konuma izin verin", "Turn your phone toward the Qibla": "Telefonunuzu kıbleye çevirin",
        "Show prayer schedule": "Namaz vakitlerini göster", "Prayer times": "Namaz vakitleri", "More": "Diğer",
        "Done": "Bitti", "Daily schedule": "Günlük vakitler", "Additional prayers": "Diğer namazlar",
        "Fajr": "Sabah", "Sunrise": "Güneş", "Dhuhr": "Öğle", "Asr": "İkindi", "Maghrib": "Akşam", "Isha": "Yatsı", "Duha": "Kuşluk", "Tahajjud": "Teheccüd",
        "Times are calculated for the chosen location and method. Local mosque times may differ.": "Vakitler seçilen konum ve hesaplama yöntemine göredir. Yerel cami vakitleri farklı olabilir."
    ]
    static let indonesian: [String: String] = [
        "Settings": "Pengaturan", "Prayer notifications": "Notifikasi salat", "City and location": "Kota dan lokasi",
        "Calculation method": "Metode perhitungan", "Wallpaper": "Latar belakang", "Close": "Tutup", "Makkah": "Makkah", "Madinah": "Madinah",
        "Next prayer": "Salat berikutnya", "Time until next prayer": "Waktu menuju salat berikutnya", "Qibla": "Kiblat",
        "Allow location for Qibla direction": "Izinkan lokasi untuk arah kiblat", "Turn your phone toward the Qibla": "Arahkan ponsel ke kiblat",
        "Show prayer schedule": "Lihat jadwal salat", "Prayer times": "Jadwal salat", "More": "Lainnya",
        "Done": "Selesai", "Daily schedule": "Jadwal harian", "Additional prayers": "Salat tambahan",
        "Fajr": "Subuh", "Sunrise": "Terbit", "Dhuhr": "Zuhur", "Asr": "Asar", "Maghrib": "Magrib", "Isha": "Isya", "Duha": "Duha", "Tahajjud": "Tahajud",
        "Times are calculated for the chosen location and method. Local mosque times may differ.": "Waktu dihitung sesuai lokasi dan metode yang dipilih. Jadwal masjid setempat dapat berbeda."
    ]
    static let malay: [String: String] = [
        "Settings": "Tetapan", "Prayer notifications": "Pemberitahuan solat", "City and location": "Bandar dan lokasi",
        "Calculation method": "Kaedah pengiraan", "Wallpaper": "Latar belakang", "Close": "Tutup", "Makkah": "Makkah", "Madinah": "Madinah",
        "Next prayer": "Solat seterusnya", "Time until next prayer": "Masa ke solat seterusnya", "Qibla": "Kiblat",
        "Allow location for Qibla direction": "Benarkan lokasi untuk arah kiblat", "Turn your phone toward the Qibla": "Halakan telefon ke kiblat",
        "Show prayer schedule": "Lihat waktu solat", "Prayer times": "Waktu solat", "More": "Lagi",
        "Done": "Selesai", "Daily schedule": "Jadual harian", "Additional prayers": "Solat tambahan",
        "Fajr": "Subuh", "Sunrise": "Syuruk", "Dhuhr": "Zohor", "Asr": "Asar", "Maghrib": "Maghrib", "Isha": "Isyak", "Duha": "Duha", "Tahajjud": "Tahajud",
        "Times are calculated for the chosen location and method. Local mosque times may differ.": "Waktu dikira mengikut lokasi dan kaedah dipilih. Jadual masjid setempat mungkin berbeza."
    ]
}


// Qibla is based on the DEVICE'S position and magnetic/true heading, never
// silently on an independently selected timetable city. Location permission is
// requested only when the user opens the compass.
@MainActor
private final class IumrahPrayerQiblaHeading: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private var heading: Double?
    @Published private var currentCoordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    private var active = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.headingFilter = 3
    }

    var relativeQiblaBearing: Double? {
        guard let heading, let coordinate = currentCoordinate else { return nil }
        let kaabaLatitude = 21.4225 * Double.pi / 180
        let longitudeDelta = (39.8262 - coordinate.longitude) * Double.pi / 180
        let latitude = coordinate.latitude * Double.pi / 180
        let east = sin(longitudeDelta) * cos(kaabaLatitude)
        let north = cos(latitude) * sin(kaabaLatitude) - sin(latitude) * cos(kaabaLatitude) * cos(longitudeDelta)
        let bearing = atan2(east, north) * 180 / Double.pi
        return (bearing - heading + 360).truncatingRemainder(dividingBy: 360)
    }

    func activate() {
        active = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: start()
        default: break
        }
    }
    func deactivate() {
        active = false
        manager.stopUpdatingHeading()
        manager.stopUpdatingLocation()
    }
    private func start() {
        guard active else { return }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { start() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            currentCoordinate = coordinate
            manager.stopUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
}

private struct IumrahPrayerWallpaperSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: IumrahPrayerState

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(IumrahPrayerWallpaper.allCases) { wallpaper in
                        Button {
                            state.wallpaper = wallpaper
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack(alignment: .topTrailing) {
                                    Image(wallpaper.assetName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 215)
                                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                                .strokeBorder(state.wallpaper == wallpaper ? Color.orange : Color.white.opacity(0.10), lineWidth: state.wallpaper == wallpaper ? 2.5 : 1)
                                        }
                                    if state.wallpaper == wallpaper {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(.white, .orange)
                                            .padding(10)
                                    }
                                }
                                Text(wallpaper.title(settings.language))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(wallpaper.subtitle(settings.language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
                VStack(alignment: .leading, spacing: 6) {
                    Text(prayerText(settings.language, "All wallpapers are prepared in the same phone-sized portrait format to keep the screen stable while switching.", "Все обои подготовлены в одном вертикальном формате экрана телефона, чтобы при смене всё отображалось стабильно.", "Barcha oboylar telefon ekrani uchun bir xil vertikal formatda tayyorlangan, shuning uchun almashtirish barqaror bo‘ladi.", "Барча обойлар телефон экрани учун бир хил вертикал форматда тайёрланган, шунинг учун алмаштириш барқарор бўлади."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Color.iumrahPageBackground.ignoresSafeArea())
            .navigationTitle(prayerText(settings.language, "Change wallpaper", "Изменить обои", "Fon rasmini o‘zgartirish", "Фон расмини ўзгартириш"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(prayerText(settings.language, "Done", "Готово", "Tayyor", "Тайёр")) { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.65), .large])
    }
}

private struct IumrahPrayerCitySheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: IumrahPrayerState
    @ObservedObject var location: IumrahPrayerLocation
    @State private var cityQuery = ""
    @State private var isSearching = false
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section(prayerText(settings.language, "Search any city", "Поиск города", "Shahar qidirish", "Шаҳар қидириш")) {
                    HStack {
                        TextField(prayerText(settings.language, "City or town", "Город", "Shahar", "Шаҳар"), text: $cityQuery)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.search)
                            .onSubmit { searchCity() }
                        Button { searchCity() } label: {
                            if isSearching { ProgressView() }
                            else { Image(systemName: "magnifyingglass") }
                        }
                        .disabled(cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || isSearching)
                        .accessibilityLabel("Find city")
                    }
                    if let searchError {
                        Text(searchError).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button {
                        location.request()
                    } label: {
                        HStack {
                            Label(prayerText(settings.language, "Use current location", "Моё местоположение", "Joylashuvim", "Жойлашувим"), systemImage: "location.north.circle.fill")
                            Spacer()
                            if location.working { ProgressView() }
                        }
                    }
                    if let message = location.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(prayerText(settings.language, "Cities", "Города", "Shaharlar", "Шаҳарлар")) {
                    ForEach(IumrahPrayerPlace.presets) { city in
                        Button {
                            state.place = city
                            dismiss()
                        } label: {
                            HStack {
                                Text(city.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if state.place.id == city.id { Image(systemName: "checkmark").foregroundStyle(.orange) }
                            }
                        }
                    }
                }
                Section {
                    Text(prayerText(settings.language, "Prayer times are calculated for the chosen city's time zone. Location is only requested when you tap the button above.", "Время молитв рассчитывается для часового пояса выбранного города. Геопозиция запрашивается только после нажатия кнопки выше.", "Namoz vaqtlari tanlangan shahar vaqt mintaqasi bo‘yicha hisoblanadi. Joylashuv faqat yuqoridagi tugma bosilganda so‘raladi.", "Намоз вақтлари танланган шаҳар вақт минтақаси бўйича ҳисобланади. Жойлашув фақат юқоридаги тугма босилганда сўралади."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(prayerText(settings.language, "Choose a city", "Выбрать город", "Shahar tanlash", "Шаҳар танлаш"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(prayerText(settings.language, "Done", "Готово", "Tayyor", "Тайёр")) { dismiss() } } }
            .onChange(of: location.resolved) { _, city in
                if let city { state.place = city; dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func searchCity() {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2, !isSearching else { return }
        isSearching = true
        searchError = nil
        Task { @MainActor in
            defer { isSearching = false }
            guard let placemark = try? await CLGeocoder().geocodeAddressString(query).first,
                  let coordinate = placemark.location?.coordinate,
                  CLLocationCoordinate2DIsValid(coordinate) else {
                searchError = prayerText(settings.language, "City not found. Try another spelling or choose from the list.", "Город не найден. Попробуйте другое написание или выберите из списка.", "Shahar topilmadi. Boshqa yozilishini sinab ko‘ring yoki ro‘yxatdan tanlang.", "Шаҳар топилмади. Бошқа ёзилишини синаб кўринг ёки рўйхатдан танланг.")
                return
            }
            let city = IumrahPrayerPlace(
                id: "searched", name: placemark.locality ?? placemark.name ?? query,
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                timeZoneID: placemark.timeZone?.identifier ?? TimeZone.autoupdatingCurrent.identifier
            )
            state.place = city
            dismiss()
        }
    }
}

private struct IumrahPrayerMethodSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: IumrahPrayerState

    var body: some View {
        NavigationStack {
            Form {
                Section(prayerText(settings.language, "Calculation method", "Метод расчёта", "Hisoblash usuli", "Ҳисоблаш усули")) {
                    Picker("Method", selection: $state.method) {
                        ForEach(IumrahPrayerMethod.allCases) { method in
                            Text(method.title).tag(method)
                        }
                    }
                    .pickerStyle(.inline)
                }
                Section(prayerText(settings.language, "Asr calculation", "Расчёт Асра", "Asr hisobi", "Аср ҳисоби")) {
                    Picker("Juristic method", selection: $state.hanafi) {
                        Text("Standard (Shafi'i / Maliki / Hanbali)").tag(false)
                        Text("Hanafi").tag(true)
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Text(prayerText(settings.language, "Umm al-Qura uses the standard Makkah twilight method and a fixed interval after sunset for Isha. Your selected method is saved on this device.", "Umm al-Qura использует стандартный метод Мекки и фиксированный интервал после заката для Иши. Выбранный метод сохраняется на этом устройстве.", "Umm al-Qura Makka usulidan va Xufton uchun quyosh botgandan keyingi qat'iy oraliqdan foydalanadi. Tanlangan usul qurilmada saqlanadi.", "Umm al-Qura Макка усулидан ва Хуфтон учун қуёш ботгандан кейинги қатъий оралиқдан фойдаланади. Танланган усул қурилмада сақланади."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(prayerText(settings.language, "Calculation settings", "Настройки расчёта", "Hisoblash sozlamalari", "Ҳисоблаш созламалари"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(prayerText(settings.language, "Done", "Готово", "Tayyor", "Тайёр")) { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

// Keep notification controls split into small views. Large nested SwiftUI expressions
// cause the Xcode type-checker to time out, particularly with inline Bindings.
private struct IumrahPrayerNotificationSheet: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: IumrahPrayerState
    @State private var selected: IumrahPrayerKind
    @State private var edited: [String: IumrahPrayerNotificationPreference]
    @State private var message: String?
    @State private var saving = false

    init(start: IumrahPrayerKind, state: IumrahPrayerState) {
        self.state = state
        _selected = State(initialValue: start)
        _edited = State(initialValue: state.notifications)
    }

    private func preference(_ kind: IumrahPrayerKind) -> IumrahPrayerNotificationPreference {
        edited[kind.rawValue] ?? .init()
    }

    private func enabled(_ kind: IumrahPrayerKind) -> Binding<Bool> {
        Binding<Bool>(
            get: { preference(kind).enabled },
            set: { value in
                var item = preference(kind)
                item.enabled = value
                edited[kind.rawValue] = item
            }
        )
    }

    private func sound(_ kind: IumrahPrayerKind) -> Binding<Bool> {
        Binding<Bool>(
            get: { preference(kind).sound },
            set: { value in
                var item = preference(kind)
                item.sound = value
                edited[kind.rawValue] = item
            }
        )
    }

    private func offset(_ kind: IumrahPrayerKind) -> Binding<Double> {
        Binding<Double>(
            get: { Double(preference(kind).offsetMinutes) },
            set: { value in
                var item = preference(kind)
                item.offsetMinutes = Int(value)
                edited[kind.rawValue] = item
            }
        )
    }

    private func earlyEnabled(_ kind: IumrahPrayerKind) -> Binding<Bool> {
        Binding<Bool>(
            get: { preference(kind).earlyReminderMinutes != nil },
            set: { value in
                var item = preference(kind)
                item.earlyReminderMinutes = value ? (item.earlyReminderMinutes ?? 10) : nil
                edited[kind.rawValue] = item
            }
        )
    }

    private func earlyMinutes(_ kind: IumrahPrayerKind) -> Binding<Int> {
        Binding<Int>(
            get: { preference(kind).earlyReminderMinutes ?? 10 },
            set: { value in
                var item = preference(kind)
                item.earlyReminderMinutes = value
                edited[kind.rawValue] = item
            }
        )
    }

    private var showingMessage: Binding<Bool> {
        Binding<Bool>(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                prayerPager
                saveButton
            }
            .background(Color.iumrahPageBackground.ignoresSafeArea())
            .navigationTitle(prayerText(settings.language, "Prayer notifications", "Уведомления о намазе", "Namoz eslatmalari", "Намоз эслатмалари"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(prayerText(settings.language, "Close", "Закрыть", "Yopish", "Ёпиш")) {
                        dismiss()
                    }
                }
            }
            .alert(
                prayerText(settings.language, "Prayer notifications", "Уведомления о намазе", "Namoz eslatmalari", "Намоз эслатмалари"),
                isPresented: showingMessage
            ) {
                Button("OK", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
        .presentationDetents([.large])
    }

    private var prayerPager: some View {
        TabView(selection: $selected) {
            ForEach(IumrahPrayerKind.allCases) { kind in
                prayerPage(kind)
                    .tag(kind)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
    }

    private func prayerPage(_ kind: IumrahPrayerKind) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                prayerHeading(kind)
                notificationControls(kind)
                offsetControls(kind)
                earlyReminderControls(kind)
                testNotificationButton(kind)
                explanation
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
    }

    private func prayerHeading(_ kind: IumrahPrayerKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 29))
                .foregroundStyle(.orange)
                .frame(width: 58, height: 58)
                .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 20))
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Text(prayerText(settings.language, "Configure reminder and sound", "Напоминание и звук", "Eslatma va ovoz", "Эслатма ва овоз"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func notificationControls(_ kind: IumrahPrayerKind) -> some View {
        VStack(spacing: 0) {
            Toggle(isOn: enabled(kind)) {
                Label(
                    prayerText(settings.language, "Notification", "Уведомление", "Bildirishnoma", "Билдиришнома"),
                    systemImage: "bell"
                )
            }
            .tint(.green)
            .padding(16)

            Divider().padding(.leading, 18)

            Toggle(isOn: sound(kind)) {
                Label(
                    prayerText(settings.language, "System notification sound", "Системный звук", "Tizim ovozi", "Тизим овози"),
                    systemImage: "speaker.wave.2"
                )
            }
            .padding(16)
        }
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private func offsetControls(_ kind: IumrahPrayerKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    prayerText(settings.language, "Reminder offset", "Время уведомления", "Eslatma vaqti", "Эслатма вақти"),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.headline)
                Spacer()
                Text(offsetDescription(preference(kind).offsetMinutes))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Slider(value: offset(kind), in: -30...30, step: 5)
                .tint(.orange)
                .accessibilityLabel("Minutes before or after prayer")
            HStack {
                Text("−30 min")
                Spacer()
                Text(prayerText(settings.language, "At prayer time", "Вовремя", "O‘z vaqtida", "Ўз вақтида"))
                Spacer()
                Text("+30 min")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Button(prayerText(settings.language, "Reset offset", "Сбросить", "Qaytarish", "Қайтариш")) {
                var item = preference(kind)
                item.offsetMinutes = 0
                edited[kind.rawValue] = item
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.orange)
        }
        .padding(18)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func earlyReminderControls(_ kind: IumrahPrayerKind) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Toggle(isOn: earlyEnabled(kind)) {
                Label(
                    prayerText(settings.language, "Early reminder", "Предварительное уведомление", "Oldindan eslatma", "Олдиндан эслатма"),
                    systemImage: "bell.badge"
                )
            }
            .tint(.orange)
            if preference(kind).earlyReminderMinutes != nil {
                earlyReminderPicker(kind)
            }
        }
        .padding(17)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
    }

    private func earlyReminderPicker(_ kind: IumrahPrayerKind) -> some View {
        Picker(
            prayerText(settings.language, "Before prayer", "До молитвы", "Namozgacha", "Намозгача"),
            selection: earlyMinutes(kind)
        ) {
            ForEach([5, 10, 15, 30], id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
        .pickerStyle(.segmented)
    }

    private func testNotificationButton(_ kind: IumrahPrayerKind) -> some View {
        Button {
            Task { await sendPreview(kind) }
        } label: {
            Label(
                prayerText(settings.language, "Test notification", "Проверить уведомление", "Eslatmani sinash", "Эслатмани синаш"),
                systemImage: "bell.badge"
            )
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
    }

    private var explanation: some View {
        Text(prayerText(
            settings.language,
            "Swipe left or right to configure another prayer. Alerts use the selected city's local prayer times. Custom adhan audio is not included.",
            "Свайпайте влево или вправо, чтобы настроить другой намаз. Напоминания используют время выбранного города. Пользовательский азан пока не включён.",
            "Boshqa namozni sozlash uchun chapga yoki o‘ngga suring. Eslatmalar tanlangan shahar vaqtlaridan foydalanadi. Maxsus azon ovozi hozircha yo‘q.",
            "Бошқа намозни созлаш учун чапга ёки ўнгга суринг. Эслатмалар танланган шаҳар вақтларидан фойдаланади. Махсус азон овози ҳозирча йўқ."
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var saveButton: some View {
        Button {
            Task { await saveSettings() }
        } label: {
            HStack {
                if saving { ProgressView().tint(.white) }
                Text(prayerText(settings.language, "Save settings", "Сохранить", "Saqlash", "Сақлаш"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 49)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Color.green, in: Capsule())
        .disabled(saving)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    @MainActor
    private func sendPreview(_ kind: IumrahPrayerKind) async {
        let success = await IumrahPrayerNotifications.preview(kind: kind, sound: preference(kind).sound)
        message = success
            ? prayerText(settings.language, "A test notification is scheduled in 5 seconds.", "Тестовое уведомление придёт через 5 секунд.", "Sinov bildirishnomasi 5 soniyada keladi.", "Синов билдиришномаси 5 сонияда келади.")
            : prayerText(settings.language, "Enable notifications for iumrah in iOS Settings to receive reminders.", "Включите уведомления для iumrah в настройках iOS.", "Eslatmalar uchun iOS sozlamalarida iumrah bildirishnomalarini yoqing.", "Эслатмалар учун iOS созламаларида iumrah билдиришномаларини ёқинг.")
    }

    @MainActor
    private func saveSettings() async {
        guard !saving else { return }
        saving = true
        state.notifications = edited
        let success = await IumrahPrayerNotifications.synchronize(state: state, allowPermissionPrompt: true)
        saving = false
        if success {
            dismiss()
        } else {
            message = prayerText(
                settings.language,
                "Enable notifications for iumrah in iOS Settings. Your choices have been saved.",
                "Включите уведомления для iumrah в настройках iOS. Ваши настройки сохранены.",
                "iOS sozlamalarida iumrah bildirishnomalarini yoqing. Tanlovlaringiz saqlandi.",
                "iOS созламаларида iumrah билдиришномаларини ёқинг. Танловларингиз сақланди."
            )
        }
    }

    private func offsetDescription(_ minutes: Int) -> String {
        if minutes == 0 {
            return prayerText(settings.language, "On time", "Вовремя", "O‘z vaqtida", "Ўз вақтида")
        }
        let sign = minutes < 0 ? "−" : "+"
        return "\(sign)\(abs(minutes)) min"
    }
}
