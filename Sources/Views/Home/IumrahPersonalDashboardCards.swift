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
    private var ink: Color { .white }
    private var subdued: Color { ink.opacity(0.73) }
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
                RoundedRectangle(cornerRadius: 26).fill(Color(white: 0.067))
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
    private let ink = Color.black
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
                Text(level ?? "—").font(.system(size: compact ? 27 : 35, weight: .bold, design: .rounded))
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
                RoundedRectangle(cornerRadius: 25).fill(Color.white)
                    .overlay { IumrahDashboardMetallicLight().clipShape(RoundedRectangle(cornerRadius: 25)) }
            }
        }.buttonStyle(IumrahDashboardPressStyle()).accessibilityIdentifier("iumrah.dashboard.rewards")
    }
}

struct IumrahDashboardFriendsTile: View {
    @EnvironmentObject private var settings: AppSettingsStore
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    private let ink = Color.black
    var body: some View {
        NavigationLink { IumrahFriendsVisualPage(language: settings.language) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "gift").font(.system(size: 25, weight: .medium)); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
                Text("+$100").foregroundStyle(Color(red: 0.196, green: 0.588, blue: 0.357)).font(.system(size: 32, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.55)
                Text(c.t("Пригласите друга", "Invite a friend", "Do‘stingizni taklif qiling", "Дўстингизни таклиф қилинг")).font(.system(.headline, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                Text(c.t("Бонус после оплаты подходящей поездки другом", "For each friend's first eligible paid trip", "Do‘stning birinchi mos to‘langan safari uchun", "Дўстнинг биринчи мос тўланган сафари учун")).font(.subheadline).foregroundStyle(ink.opacity(0.82)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 184, maxHeight: .infinity, alignment: .topLeading).foregroundStyle(ink)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 25))
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
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 26))
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

enum IumrahDashboardTone: Equatable {
    case white, silver, graphite
    var surface: Color {
        switch self {
        case .white: return .white
        case .silver: return Color(red: 0.89, green: 0.894, blue: 0.906)
        case .graphite: return Color(white: 0.125)
        }
    }
    var ink: Color { self == .graphite ? .white : .black }
    var secondaryInk: Color { self == .graphite ? Color(white: 0.73) : Color(white: 0.40) }
}

struct IumrahDashboardServiceTile: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tone: IumrahDashboardTone
    var body: some View {
        let palette = tone
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: symbol).font(.system(size: 26, weight: .medium)); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)) }
            Spacer(minLength: 3)
            Text(title).font(.system(.headline, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.subheadline).foregroundStyle(palette.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading).foregroundStyle(palette.ink)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 23))
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

/// Team preview uses the same public directory as the guide catalogue.
/// No photos, names or availability are fabricated when the API is unavailable.
struct IumrahDashboardTeamShowcase: View {
    let trip: TripDraft
    let title: String
    let subtitle: String
    let actionTitle: String
    @State private var members: [IumrahPublicProfile] = []
    @EnvironmentObject private var settings: AppSettingsStore
    private var c: IumrahDashboardCopy { .init(language: settings.language) }
    private var key: String { IumrahGuideDates.day(trip.hotelStayStartDate) + "|" + IumrahGuideDates.day(trip.returnDate) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("THE IUMRAH TEAM").font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.65))
                HStack(spacing: 12) {
                    Spacer(minLength: 0)
                    if members.isEmpty {
                        Image(systemName: "person.2.circle").font(.system(size: 52, weight: .light)).foregroundStyle(.white.opacity(0.8))
                    } else {
                        ForEach(members.prefix(3)) { member in
                            IumrahTeamAvatar(member: member, size: 60)
                                .overlay { Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1) }
                                .accessibilityLabel(member.displayName)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Text(c.t("Команда iumrah", "iumrah team", "iumrah jamoasi", "iumrah жамоаси")).font(.caption).foregroundStyle(.white.opacity(0.74)).frame(maxWidth: .infinity)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.125)).environment(\.colorScheme, .dark)
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.system(.title2, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text(actionTitle).font(.headline); Spacer(minLength: 4); Image(systemName: "arrow.up.right").font(.subheadline.weight(.semibold)) }
            }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(.primary).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26)).clipShape(RoundedRectangle(cornerRadius: 26))
        .task(id: key) {
            do {
                let published = try await ChatService().loadGuideProfiles(start: trip.hotelStayStartDate, end: trip.returnDate, includeTeam: true)
                guard !Task.isCancelled else { return }
                let guides = published.filter { !$0.isOwner && $0.roleKind == "guide" }
                let leads = guides.filter { $0.isHeadGuide == true }
                let other = guides.filter { $0.isHeadGuide != true }
                let founders = published.filter { $0.isOwner }
                let staff = published.filter { !$0.isOwner && $0.roleKind != "guide" }
                members = Array((Array(leads.prefix(1)) + Array(other.prefix(leads.isEmpty ? 2 : 1)) + founders + Array(leads.dropFirst()) + other + staff).reduce(into: [IumrahPublicProfile]()) { result, member in
                    if !result.contains(where: { $0.id == member.id }) { result.append(member) }
                }.prefix(3))
            } catch { /* Existing public avatars remain visible after transient failures. */ }
        }
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
