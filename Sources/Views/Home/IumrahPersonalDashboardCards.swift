import SwiftUI

/// Shared presentation components for the Home and Account roots. All amounts and
/// membership levels come from the authenticated account store; no demo values.
struct IumrahDashboardCopy {
    let language: AppSettingsStore.Language
    func t(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(language, ru, en, uz, cy)
    }
}

struct IumrahDashboardBalanceCard: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    private var balance: Double? { account.dashboardRewards?.availableCreditUsd }
    private var validBalance: Double? { balance.flatMap { $0.isFinite ? $0 : nil } }
    private var amount: String { validBalance.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—" }
    private var ink: Color { compact ? Color(red: 0.07, green: 0.25, blue: 0.18) : .white }
    private var subdued: Color { ink.opacity(compact ? 0.78 : 0.73) }
    private var detail: String {
        if !account.isAuthenticated { return c.t("Бонусы после регистрации", "Rewards after registration", "Ro‘yxatdan keyin bonuslar", "Рўйхатдан кейин бонуслар") }
        if validBalance == nil { return account.dashboardRewardsLoading ? c.t("Обновляем баланс…", "Updating balance…", "Balans yangilanmoqda…", "Баланс янгиланмоқда…") : c.t("Баланс недоступен · откройте для обновления", "Balance unavailable · open to refresh", "Balans mavjud emas · yangilash uchun oching", "Баланс мавжуд эмас · янгилаш учун очинг") }
        if account.dashboardRewardsStale { return c.t("Последний подтверждённый баланс", "Last verified balance", "Oxirgi tasdiqlangan balans", "Охирги тасдиқланган баланс") }
        if validBalance == 0 { return c.t("Получайте бонусы за приглашения", "Earn rewards through referrals", "Takliflar orqali bonus oling", "Таклифлар орқали бонус олинг") }
        return c.t("Доступно для бронирования", "Available for booking", "Bron qilish uchun mavjud", "Брон қилиш учун мавжуд")
    }
    var body: some View {
        NavigationLink { IumrahBalanceVisualPage(language: settings.language) } label: {
            VStack(alignment: .leading, spacing: compact ? 9 : 17) {
                HStack {
                    Text("iumrah Balance").font(.system(.headline, design: .rounded)).foregroundStyle(subdued)
                    Spacer(minLength: 4)
                    Image(systemName: "wallet.bifold").font(.system(size: 24, weight: .medium)).accessibilityHidden(true)
                }
                Text(amount).font(.system(size: compact ? 32 : 42, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: amount)
                    .accessibilityIdentifier("iumrah.dashboard.balance.amount")
                Text(detail).font(.subheadline).foregroundStyle(subdued).fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(ink.opacity(0.19)).frame(height: 1)
                HStack {
                    Text(c.t("История операций", "Transaction history", "Amallar tarixi", "Амаллар тарихи")).font(.subheadline.weight(.medium))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                }.foregroundStyle(subdued)
            }
            .foregroundStyle(ink).padding(compact ? 18 : 23)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: compact ? [Color(red: 0.89, green: 0.96, blue: 0.92), Color(red: 0.76, green: 0.88, blue: 0.82)] : [Color(red: 0.13, green: 0.36, blue: 0.29), Color(red: 0.035, green: 0.16, blue: 0.13)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }.buttonStyle(IumrahDashboardPressStyle()).accessibilityIdentifier("iumrah.dashboard.balance")
    }
}

struct IumrahDashboardRewardsCard: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    private let ink = Color(red: 0.37, green: 0.24, blue: 0.09)
    private var level: String? {
        guard let tier = account.dashboardRewards?.tier?.lowercased(), ["member", "plus", "elite"].contains(tier) else { return nil }
        return tier.capitalized
    }
    private var levelIndex: Int? { level.flatMap { ["Member", "Plus", "Elite"].firstIndex(of: $0) } }
    private var caption: String {
        if account.dashboardRewardsStale && level != nil { return c.t("Последний подтверждённый статус", "Last verified status", "Oxirgi tasdiqlangan daraja", "Охирги тасдиқланган даража") }
        return c.t("Ваши персональные преимущества", "Your personal benefits", "Shaxsiy imtiyozlaringiz", "Шахсий имтиёзларингиз")
    }
    var body: some View {
        NavigationLink { IumrahRewardsVisualPage(language: settings.language) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: level == "Elite" ? "crown.fill" : "star").font(.system(size: 25, weight: .medium))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right").font(.caption.weight(.semibold))
                }
                Text(level ?? "Rewards").font(.system(size: compact ? 27 : 35, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.55).contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: level)
                Text("iumrah Rewards").font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text(caption).font(.subheadline).foregroundStyle(ink.opacity(0.83)).fixedSize(horizontal: false, vertical: true)
                if !compact {
                    HStack(spacing: 5) {
                        ForEach(Array(["Member", "Plus", "Elite"].enumerated()), id: \.offset) { index, name in
                            VStack(spacing: 6) {
                                Capsule().fill((levelIndex.map { index <= $0 } ?? false) ? ink : ink.opacity(0.15)).frame(height: 4)
                                Text(name).font(.caption.weight(levelIndex == index ? .bold : .regular)).foregroundStyle(ink.opacity(levelIndex == index ? 1 : 0.75))
                            }.frame(maxWidth: .infinity)
                        }
                    }.accessibilityLabel(level ?? c.t("Уровень не подтверждён", "Level unverified", "Daraja tasdiqlanmagan", "Даража тасдиқланмаган"))
                }
                Spacer(minLength: 0)
            }
            .padding(18).frame(maxWidth: .infinity, minHeight: compact ? 184 : 0, maxHeight: compact ? .infinity : nil, alignment: .topLeading)
            .foregroundStyle(ink)
            .background {
                RoundedRectangle(cornerRadius: 25).fill(LinearGradient(colors: [Color(red: 0.99, green: 0.95, blue: 0.84), Color(red: 0.91, green: 0.79, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { IumrahDashboardMetallicLight().clipShape(RoundedRectangle(cornerRadius: 25)) }
            }
        }.buttonStyle(IumrahDashboardPressStyle()).accessibilityIdentifier("iumrah.dashboard.rewards")
    }
}

struct IumrahDashboardFriendsTile: View {
    @EnvironmentObject private var settings: AppSettingsStore
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    private let ink = Color(red: 0.12, green: 0.25, blue: 0.54)
    var body: some View {
        NavigationLink { IumrahFriendsVisualPage(language: settings.language) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "gift").font(.system(size: 25, weight: .medium)); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
                Text("+$100").font(.system(size: 32, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.55)
                Text(c.t("Пригласите друга", "Invite a friend", "Do‘stingizni taklif qiling", "Дўстингизни таклиф қилинг")).font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text(c.t("За каждую первую подходящую оплаченную поездку друга", "For each friend's first eligible paid trip", "Do‘stning birinchi mos to‘langan safari uchun", "Дўстнинг биринчи мос тўланган сафари учун")).font(.subheadline).foregroundStyle(ink.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 184, maxHeight: .infinity, alignment: .topLeading).foregroundStyle(ink)
                .background(LinearGradient(colors: [Color(red: 0.91, green: 0.94, blue: 1), Color(red: 0.79, green: 0.85, blue: 0.99)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 25))
        }.buttonStyle(IumrahDashboardPressStyle()).accessibilityIdentifier("iumrah.dashboard.friends.tile")
    }
}

struct IumrahDashboardIdentityCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let action: () -> Void
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text("iumrah ID").font(.system(.title2, design: .rounded, weight: .bold)); Spacer(); Image(systemName: "qrcode.viewfinder").font(.title2) }
                IumrahWorldDotsMap(waveSpeed: 0.55, waveIntensity: 0.75, opacity: 0.55).frame(height: 110).frame(maxWidth: .infinity)
                HStack(alignment: .center) {
                    Text(c.t("Ваша персональная карта паломника", "Your personal pilgrim card", "Shaxsiy ziyoratchi kartangiz", "Шахсий зиёратчи картангиз")).font(.subheadline).foregroundStyle(.white.opacity(0.78)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6); Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold))
                }
            }.padding(21).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [Color(red: 0.19, green: 0.21, blue: 0.30), Color(red: 0.075, green: 0.08, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 26))
        }.buttonStyle(IumrahDashboardPressStyle()).accessibilityIdentifier("iumrah.dashboard.identity")
    }
}

/// Gentle native sheen. The performance host pauses updates in inactive tabs,
/// background, Reduce Motion and constrained power/thermal conditions.
private struct IumrahDashboardMetallicLight: View {
    var body: some View {
        IumrahDecorativeTimeline(maxFPS: 12, staticWhenConstrained: true) { date in
            GeometryReader { geometry in
                let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 12) / 12
                LinearGradient(colors: [.clear, .white.opacity(0.20), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geometry.size.width * 0.5)
                    .rotationEffect(.degrees(24)).offset(x: (geometry.size.width * 1.7) * CGFloat(phase) - geometry.size.width * 0.6)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct IumrahDashboardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.87 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { IumrahHaptics.soft() } }
    }
}

enum IumrahDashboardTone {
    case blue, gold, slate, green, violet
    var colors: (Color, Color, Color) {
        switch self {
        case .blue: return (Color(red: 0.90, green: 0.94, blue: 1), Color(red: 0.80, green: 0.87, blue: 0.98), Color(red: 0.14, green: 0.30, blue: 0.55))
        case .gold: return (Color(red: 0.99, green: 0.95, blue: 0.88), Color(red: 0.94, green: 0.87, blue: 0.75), Color(red: 0.45, green: 0.30, blue: 0.12))
        case .slate: return (Color(red: 0.94, green: 0.95, blue: 0.97), Color(red: 0.83, green: 0.87, blue: 0.92), Color(red: 0.25, green: 0.33, blue: 0.44))
        case .green: return (Color(red: 0.91, green: 0.97, blue: 0.93), Color(red: 0.78, green: 0.89, blue: 0.83), Color(red: 0.12, green: 0.36, blue: 0.24))
        case .violet: return (Color(red: 0.96, green: 0.93, blue: 0.99), Color(red: 0.87, green: 0.81, blue: 0.95), Color(red: 0.34, green: 0.22, blue: 0.52))
        }
    }
}

struct IumrahDashboardServiceTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tone: IumrahDashboardTone
    var body: some View {
        let palette = tone.colors
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: symbol).font(.system(size: 26, weight: .medium)); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
            Spacer(minLength: 3)
            Text(title).font(.system(.headline, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(palette.2.opacity(0.83)).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading).foregroundStyle(palette.2)
            .background(LinearGradient(colors: [palette.0, palette.1], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 23))
    }
}

struct IumrahDashboardPhotoCard: View {
    let image: String
    let title: String
    let subtitle: String
    let actionTitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                Image(image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }.frame(height: 172).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text(actionTitle).font(.headline); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)) }.padding(.top, 4)
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.primary).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26)).clipShape(RoundedRectangle(cornerRadius: 26))
    }
}

/// Keeps the two roots synchronized through a single account-owned cache and
/// coalesced request. Only the active visible tab polls.
struct IumrahDashboardRewardsRefresh: ViewModifier {
    @EnvironmentObject private var account: IumrahAccountStore
    @Environment(\.iumrahTabIsActive) private var activeTab
    @Environment(\.scenePhase) private var scenePhase
    func body(content: Content) -> some View {
        content.task(id: "\(account.bearerToken ?? "guest")|\(activeTab)|\(scenePhase == .active)") {
            guard activeTab, scenePhase == .active, account.isAuthenticated else { return }
            while !Task.isCancelled && account.isAuthenticated {
                await account.refreshDashboardRewards()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }
}

struct IumrahDashboardEntryMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    func body(content: Content) -> some View {
        content.opacity(appeared || reduceMotion ? 1 : 0.86)
            .offset(y: appeared || reduceMotion ? 0 : 7)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.36)) { appeared = true } }
    }
}
