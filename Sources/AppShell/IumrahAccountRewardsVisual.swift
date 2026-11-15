import SwiftUI

// Server-backed referral and bonus views. A nil dashboard is not a zero balance.
private struct AccountRewardsCopy {
    let language: AppSettingsStore.Language
    func t(_ en: String, _ ru: String, _ uz: String, _ cy: String) -> String {
        switch language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        default: return en
        }
    }
    var preview: String { t("Rewards data is unavailable. Pull to refresh.", "Данные бонусов недоступны. Обновите страницу.", "Bonus ma’lumotlari mavjud emas. Yangilang.", "Бонус маълумотлари мавжуд эмас. Янгиланг.") }
    var unavailable: String { t("Available after launch", "Будет доступно после запуска", "Ishga tushgach mavjud", "Ишга тушгач мавжуд") }
    var available: String { t("Available for your next trip", "Доступно для следующей поездки", "Keyingi safar uchun mavjud", "Кейинги сафар учун мавжуд") }
    var bonuses: String { t("Bonuses and rewards", "Бонусы и вознаграждения", "Bonuslar va mukofotlar", "Бонуслар ва мукофотлар") }
    var invite: String { t("Invite a friend", "Пригласить друга", "Do‘stni taklif qilish", "Дўстни таклиф қилиш") }
    var giftCards: String { t("Existing Gift Cards", "Ваши Gift Cards", "Mavjud Gift Cards", "Мавжуд Gift Cards") }
}

private struct AccountRewardsGlassIcon: View {
    let symbol: String
    var color: Color = .primary
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .iumrahGlass(in: Circle(), tint: color.opacity(0.12), allowsStaticGlass: true)
            .accessibilityHidden(true)
    }
}

private struct AccountRewardsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, IumrahDesign.pagePadding)
                .padding(.vertical, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.iumrahPageBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .tint(.primary)
        // Deliberately keep the native navigation bar and default back item.
        // iOS 26 renders its native Liquid Glass back button; interactive pop
        // remains owned by UINavigationController. No gesture interception.
    }
}

private struct AccountRewardsPreviewNote: View {
    let copy: AccountRewardsCopy
    var body: some View {
        Label(copy.preview, systemImage: "info.circle")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountRewardsCTA: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(.body, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.iumrahPrimaryButtonText)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 12)
            .background(Color.iumrahPrimaryButtonBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct IumrahAccountBalanceEntry: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var dashboard: IumrahFriendsDashboard?
    @State private var dashboardOwner: String?
    private var live: IumrahFriendsDashboard? { dashboardOwner == account.iumrahID && account.isAuthenticated ? dashboard : nil }
    @MainActor private func reload() async {
        guard let owner = account.iumrahID, account.isAuthenticated else { dashboard = nil; dashboardOwner = nil; return }
        if dashboardOwner != owner { dashboard = nil; dashboardOwner = owner }
        do {
            let data = try await account.rewardsDashboard()
            guard !Task.isCancelled, account.iumrahID == owner, account.isAuthenticated else { return }
            dashboard = data; dashboardOwner = owner
        } catch {
            guard !Task.isCancelled, account.iumrahID == owner else { return }
            dashboard = nil
        }
    }
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        NavigationLink {
            IumrahBalanceVisualPage(language: language)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AccountRewardsGlassIcon(symbol: "wallet.bifold.fill", color: .blue)
                    Text("iumrah Balance").font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer(minLength: 4)
                    AccountRewardsGlassIcon(symbol: "arrow.up.right", size: 34)
                }
                Text(rewardMoney(live?.availableCreditUsd)).font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                    
                Text(c.available).font(.subheadline).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text(c.t("Pending rewards", "Ожидаемые бонусы", "Kutilayotgan bonuslar", "Кутилаётган бонуслар")).font(.subheadline)
                    Spacer()
                    Text(rewardMoney(live?.pendingRewardsUsd)).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                if live == nil { AccountRewardsPreviewNote(copy: c) }
            }
            .foregroundStyle(.primary)
            .iumrahCard()
        }
        .buttonStyle(.plain)
        .task(id: account.iumrahID) {
            while !Task.isCancelled && account.isAuthenticated {
                await reload()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
}

struct IumrahAccountRewardsCarousel<Identity: View>: View {
    let language: AppSettingsStore.Language
    @ViewBuilder let identity: Identity
    @State private var selected = 0
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        VStack(spacing: 10) {
            TabView(selection: $selected) {
                identity.padding(1).tag(0)
                NavigationLink {
                    IumrahRewardsVisualPage(language: language)
                } label: {
                    GeometryReader { proxy in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("iumrah Rewards").font(.system(.headline, design: .rounded, weight: .semibold))
                                Spacer()
                                AccountRewardsGlassIcon(symbol: "arrow.up.right", color: .white, size: 32)
                            }
                            Spacer(minLength: 0)
                            IumrahOrbitV5(services: rewardOrbitServices, diameter: min(112, proxy.size.height * 0.48), isActive: selected == 1, lightOnDark: true, logo: Image(systemName: "star.fill"), accessibilityTitle: "iumrah Rewards")
                                .frame(maxWidth: .infinity)
                                .allowsHitTesting(false)
                            Spacer(minLength: 0)
                            Text(c.t("Your privileges", "Ваши преимущества", "Imtiyozlaringiz", "Имтиёзларингиз"))
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text(c.t("Travel and unlock new benefits", "Путешествуйте и открывайте новые возможности", "Sayohat qiling va yangi imtiyozlarni oching", "Саёҳат қилинг ва янги имтиёзларни очинг"))
                                .font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(2)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(.white)
                    .background(Color(red: 0.06, green: 0.06, blue: 0.08), in: RoundedRectangle(cornerRadius: 22))
                }
                .buttonStyle(.plain)
                .padding(1)
                .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(1.48, contentMode: .fit)
            HStack(spacing: 6) {
                ForEach(0..<2) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { selected = index }
                    } label: {
                        Capsule().fill(selected == index ? Color.primary : Color.secondary.opacity(0.25))
                            .frame(width: selected == index ? 20 : 7, height: 7)
                            .frame(minWidth: 30, minHeight: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 0 ? "iumrah ID" : "iumrah Rewards")
                    .accessibilityAddTraits(selected == index ? .isSelected : [])
                }
            }
        }
    }
}

private let rewardOrbitServices: [IumrahOrbitV5Service] = [
    .init(id: "star", symbol: "star.fill"), .init(id: "gift", symbol: "gift.fill"),
    .init(id: "friends", symbol: "person.2.fill"), .init(id: "trip", symbol: "airplane"),
    .init(id: "reward", symbol: "medal.fill"), .init(id: "balance", symbol: "wallet.bifold.fill")
]

struct IumrahAccountFriendsEntry: View {
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        NavigationLink {
            IumrahFriendsVisualPage(language: language)
        } label: {
            HStack(spacing: 14) {
                AccountRewardsGlassIcon(symbol: "gift.fill", color: .purple, size: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.t("Invite loved ones", "Пригласите близких", "Yaqinlaringizni taklif qiling", "Яқинларингизни таклиф қилинг"))
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(c.t("iumrah Friends · rewards for referrals", "iumrah Friends · вознаграждения за рекомендации", "iumrah Friends · tavsiyalar uchun mukofotlar", "iumrah Friends · тавсиялар учун мукофотлар"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .iumrahCard()
        }
        .buttonStyle(.plain)
    }
}

struct IumrahBalanceVisualPage: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var dashboard: IumrahFriendsDashboard?
    @State private var dashboardOwner: String?
    private var live: IumrahFriendsDashboard? { dashboardOwner == account.iumrahID && account.isAuthenticated ? dashboard : nil }
    @MainActor private func reload() async {
        guard let owner = account.iumrahID, account.isAuthenticated else { dashboard = nil; dashboardOwner = nil; return }
        if dashboardOwner != owner { dashboard = nil; dashboardOwner = owner }
        do {
            let data = try await account.rewardsDashboard()
            guard !Task.isCancelled, account.iumrahID == owner, account.isAuthenticated else { return }
            dashboard = data; dashboardOwner = owner
        } catch {
            guard !Task.isCancelled, account.iumrahID == owner else { return }
            dashboard = nil
        }
    }
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        AccountRewardsPage(title: "iumrah Balance") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(c.t("Available balance", "Доступный баланс", "Mavjud balans", "Мавжуд баланс")).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    AccountRewardsGlassIcon(symbol: "wallet.bifold.fill", color: .white)
                }
                Text(rewardMoney(live?.availableCreditUsd)).font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(.white)

                Divider().overlay(Color.white.opacity(0.16))
                HStack {
                    Text(c.t("Pending rewards", "Ожидаемые бонусы", "Kutilayotgan bonuslar", "Кутилаётган бонуслар")).foregroundStyle(.white.opacity(0.72))
                    Spacer()
                    Text(rewardMoney(live?.pendingRewardsUsd)).foregroundStyle(.white)
                }
                .font(.subheadline)
            }
            .padding(20)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 26))
            if live == nil { AccountRewardsPreviewNote(copy: c) }
            HStack(alignment: .top, spacing: 12) {
                NavigationLink { IumrahCouponVisualPage(language: language) } label: {
                    actionTile("giftcard.fill", .purple, c.t("Add coupon", "Добавить купон", "Kupon qo‘shish", "Купон қўшиш"))
                }.buttonStyle(.plain)
                NavigationLink { IumrahFriendsVisualPage(language: language) } label: {
                    actionTile("person.2.fill", .blue, c.invite)
                }.buttonStyle(.plain)
            }
            Text(c.t("Transaction history", "История операций", "Amallar tarixi", "Амаллар тарихи"))
                .font(.system(.title2, design: .rounded, weight: .bold))
            if let transactions = live?.transactions, !transactions.isEmpty {
                ForEach(transactions) { tx in
                    HStack(spacing: 12) {
                        AccountRewardsGlassIcon(symbol: tx.amountUsd >= 0 ? "plus.circle.fill" : "minus.circle.fill", color: tx.amountUsd >= 0 ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(tx.amountUsd >= 0 ? c.t("Reward", "Начисление", "Bonus", "Бонус") : c.t("Debit / reversal", "Списание / возврат", "Hisobdan chiqarish", "Ҳисобдан чиқариш")).font(.headline)
                            Text(String(tx.createdAt.prefix(10))).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(rewardMoney(tx.amountUsd)).font(.headline).monospacedDigit()
                    }.iumrahCard()
                }
            } else if live?.transactions != nil {
                Text(c.t("No transactions yet", "Пока нет операций", "Hali amallar yo‘q", "Ҳали амаллар йўқ")).foregroundStyle(.secondary).iumrahCard()
            }
            NavigationLink { IumrahGiftCardsView().toolbar(.visible, for: .navigationBar) } label: {
                AccountRewardsCTA(title: c.giftCards)
            }.buttonStyle(.plain)
        }
        .task(id: account.iumrahID) { await reload() }
        .refreshable { await reload() }
    }
    private func actionTile(_ symbol: String, _ color: Color, _ title: String) -> some View {
        VStack(spacing: 10) {
            AccountRewardsGlassIcon(symbol: symbol, color: color, size: 50)
            Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.center)
                .foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 42)
        }.frame(maxWidth: .infinity).iumrahCard()
    }
}

private struct IumrahCouponVisualPage: View {
    let language: AppSettingsStore.Language
    @State private var code = ""
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        AccountRewardsPage(title: c.t("Add coupon", "Добавить купон", "Kupon qo‘shish", "Купон қўшиш")) {
            VStack(spacing: 16) {
                AccountRewardsGlassIcon(symbol: "giftcard.fill", color: .purple, size: 72)
                Text(c.t("Enter your coupon code", "Введите код купона", "Kupon kodini kiriting", "Купон кодини киритинг")).font(.title2.bold())
                TextField(c.t("Coupon code", "Код купона", "Kupon kodi", "Купон коди"), text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .padding(14).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 14))
                Button {} label: {
                    AccountRewardsCTA(title: c.t("Apply coupon", "Применить купон", "Kuponni qo‘llash", "Купонни қўллаш"))
                }.buttonStyle(.plain).disabled(true).opacity(0.4)
                Text(c.t("Existing Gift Cards are applied during booking payment. New coupon redemption is not yet available.", "Действующие Gift Cards применяются при оплате бронирования. Новые купоны пока недоступны.", "Gift Cards bron to‘lovida qo‘llanadi.", "Gift Cards брон тўловида қўлланади.")).font(.footnote).foregroundStyle(.secondary)
            }.iumrahCard()
        }
    }
}

struct IumrahRewardsVisualPage: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var dashboard: IumrahFriendsDashboard?
    @State private var dashboardOwner: String?
    private var live: IumrahFriendsDashboard? { dashboardOwner == account.iumrahID && account.isAuthenticated ? dashboard : nil }
    @MainActor private func reload() async {
        guard let owner = account.iumrahID, account.isAuthenticated else { dashboard = nil; dashboardOwner = nil; return }
        if dashboardOwner != owner { dashboard = nil; dashboardOwner = owner }
        do {
            let data = try await account.rewardsDashboard()
            guard !Task.isCancelled, account.iumrahID == owner, account.isAuthenticated else { return }
            dashboard = data; dashboardOwner = owner
        } catch {
            guard !Task.isCancelled, account.iumrahID == owner else { return }
            dashboard = nil
        }
    }
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        AccountRewardsPage(title: "iumrah Rewards") {
            VStack(spacing: 8) {
                IumrahOrbitAdaptive(maxDiameter: 230, logo: Image(systemName: "star.fill"), services: rewardOrbitServices, lightOnDark: true, accessibilityTitle: "iumrah Rewards")
                Text(c.t("Travel more. Unlock more.", "Путешествуйте. Открывайте больше.", "Ko‘proq sayohat, ko‘proq imtiyoz.", "Кўпроқ саёҳат, кўпроқ имтиёз.")).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(c.t("Benefits for journeys and recommendations", "Преимущества за поездки и рекомендации", "Safarlar va tavsiyalar uchun imtiyozlar", "Сафарлар ва тавсиялар учун имтиёзлар"))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
            }.padding(18).frame(maxWidth: .infinity).background(Color.black, in: RoundedRectangle(cornerRadius: 26))
            if let live, let tier = live.tier {
                Text("iumrah " + tier.capitalized).font(.title.bold()).iumrahCard()
                Text(c.t("Completed trips / paid referrals", "Завершённые поездки / оплаченные приглашения", "Yakunlangan safarlar / to‘langan takliflar", "Якунланган сафарлар / тўланган таклифлар") + ": \(live.completedTrips ?? 0) / \(live.paidReferrals ?? 0)").font(.subheadline)
            } else { AccountRewardsPreviewNote(copy: c) }
            tier("iumrah Member", "01", .gray, "person.crop.circle.fill",
                 c.t("Access to rewards and referrals", "Доступ к бонусам и приглашениям", "Bonuslar va takliflarga kirish", "Бонуслар ва таклифларга кириш"),
                 c.t("After registration", "После регистрации", "Ro‘yxatdan o‘tgach", "Рўйхатдан ўтгач"))
            tier("iumrah Plus", "02", .blue, "star.fill",
                 c.t("Additional savings on eligible services", "Дополнительные скидки на участвующие услуги", "Mos xizmatlarga qo‘shimcha chegirmalar", "Мос хизматларга қўшимча чегирмалар"),
                 c.t("1 completed trip or 3 successful referrals", "1 завершённая поездка или 3 успешных приглашения", "1 yakunlangan safar yoki 3 muvaffaqiyatli taklif", "1 якунланган сафар ёки 3 муваффақиятли таклиф"))
            tier("iumrah Elite", "03", .orange, "crown.fill",
                 c.t("Maximum privileges and priority support", "Максимальные привилегии и приоритетное обслуживание", "Eng yuqori imtiyozlar va ustuvor yordam", "Энг юқори имтиёзлар ва устувор ёрдам"),
                 c.t("3 completed trips or 7 successful referrals", "3 завершённые поездки или 7 успешных приглашений", "3 yakunlangan safar yoki 7 muvaffaqiyatli taklif", "3 якунланган сафар ёки 7 муваффақиятли таклиф"))
            Text(c.t("Levels track your progress. Additional discounts will be announced separately.", "Уровни показывают ваш прогресс. Дополнительные скидки будут объявлены отдельно.", "Darajalar rivojlanishingizni ko‘rsatadi. Qo‘shimcha chegirmalar alohida e’lon qilinadi.", "Даражалар ривожланишингизни кўрсатади. Қўшимча чегирмалар алоҳида эълон қилинади."))
                .font(.footnote).foregroundStyle(.secondary)
            NavigationLink { IumrahFriendsVisualPage(language: language) } label: { AccountRewardsCTA(title: c.invite) }.buttonStyle(.plain)
        }
        .task(id: account.iumrahID) { await reload() }
        .refreshable { await reload() }
    }
    private func tier(_ name: String, _ level: String, _ color: Color, _ symbol: String, _ benefit: String, _ condition: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AccountRewardsGlassIcon(symbol: symbol, color: color, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(.title3, design: .rounded, weight: .bold))
                    Text(c.t("Level", "Уровень", "Daraja", "Даража") + " " + level).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                if let active = live?.tier, let current = ["member":1,"plus":2,"elite":3][active], let target = Int(level) {
                    Image(systemName: current >= target ? "checkmark.seal.fill" : "lock.fill").foregroundStyle(current >= target ? Color.green : Color.secondary)
                } else { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
            }
            Text(benefit).font(.subheadline.weight(.semibold))
            Text(condition).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(color.opacity(0.19), lineWidth: 1) }
    }
}

struct IumrahFriendsVisualPage: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var dashboard: IumrahFriendsDashboard?
    @State private var dashboardOwner: String?
    private var live: IumrahFriendsDashboard? { dashboardOwner == account.iumrahID && account.isAuthenticated ? dashboard : nil }
    @MainActor private func reload() async {
        guard let owner = account.iumrahID, account.isAuthenticated else { dashboard = nil; dashboardOwner = nil; return }
        if dashboardOwner != owner { dashboard = nil; dashboardOwner = owner }
        do {
            let data = try await account.rewardsDashboard()
            guard !Task.isCancelled, account.iumrahID == owner, account.isAuthenticated else { return }
            dashboard = data; dashboardOwner = owner
        } catch {
            guard !Task.isCancelled, account.iumrahID == owner else { return }
            dashboard = nil
        }
    }
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    var body: some View {
        AccountRewardsPage(title: "iumrah Friends") {
            VStack(spacing: 14) {
                IumrahOrbitAdaptive(maxDiameter: 245, logo: Image(systemName: "gift.fill"), services: rewardOrbitServices, lightOnDark: true, accessibilityTitle: "iumrah Friends")
                Text(c.t("A good journey starts with an invitation.", "Доброе путешествие начинается с приглашения.", "Yaxshi safar taklifdan boshlanadi.", "Яхши сафар таклифдан бошланади.")).font(.system(.title2, design: .rounded, weight: .bold)).multilineTextAlignment(.center)
                Text(c.t("Invite loved ones and earn rewards after confirmed payment.", "Приглашайте близких и получайте вознаграждения после подтверждения оплаты.", "Yaqinlaringizni taklif qiling va to‘lov tasdiqlangach mukofot oling.", "Яқинларингизни таклиф қилинг ва тўлов тасдиқлангач мукофот олинг.")).font(.subheadline).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
                if let link = live?.invitation?.url, let url = URL(string: link) {
                    ShareLink(item: url) {
                        Text(c.invite).font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.black).frame(maxWidth: .infinity, minHeight: 52)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain)
                    if let code = live?.invitation?.code { Text(code).font(.caption.monospaced()).textSelection(.enabled) }
                } else { Text(c.preview).font(.caption).foregroundStyle(.white.opacity(0.75)) }
                Divider().overlay(Color.white.opacity(0.15))
                HStack(alignment: .top, spacing: 6) {
                    stat(c.t("Invited", "Приглашено", "Takliflar", "Таклифлар"), live?.referrals.map { String($0.count) } ?? "—")
                    stat(c.t("Paid", "Оплачено", "To‘langan", "Тўланган"), live?.paidReferrals.map { String($0) } ?? "—")
                    stat(c.t("Earned", "Получено", "Mukofot", "Мукофот"), rewardMoney(live?.earnedRewardsUsd))
                }
            }.foregroundStyle(.white).padding(20).background(Color.black, in: RoundedRectangle(cornerRadius: 26))
            if let referrals = live?.referrals {
                Text(c.t("Your invitations", "Ваши приглашения", "Takliflaringiz", "Таклифларингиз")).font(.title2.bold())
                if referrals.isEmpty { Text(c.t("No invited friends yet", "Пока нет приглашённых друзей", "Hali takliflar yo‘q", "Ҳали таклифлар йўқ")).foregroundStyle(.secondary).iumrahCard() }
                ForEach(referrals) { friend in friendCard(friend) }
            } else { AccountRewardsPreviewNote(copy: c) }
            Text(c.t("How it will work", "Как это будет работать", "Qanday ishlaydi", "Қандай ишлайди")).font(.system(.title2, design: .rounded, weight: .bold))
            VStack(alignment: .leading, spacing: 16) {
                explanation("square.and.arrow.up", c.t("Share your personal invitation", "Поделитесь персональным приглашением", "Shaxsiy taklifingizni ulashing", "Шахсий таклифингизни улашинг"))
                explanation("airplane", c.t("Your friend pays for an eligible trip", "Друг оплачивает подходящую поездку", "Do‘stingiz safar uchun to‘lov qiladi", "Дўстингиз сафар учун тўлов қилади"))
                explanation("wallet.bifold.fill", c.t("Rewards appear in your balance", "Вознаграждение поступает на баланс", "Mukofot balansingizga tushadi", "Мукофот балансингизга тушади"))
            }.iumrahCard()
            NavigationLink { IumrahGiftCardsView().toolbar(.visible, for: .navigationBar) } label: { AccountRewardsCTA(title: c.giftCards) }.buttonStyle(.plain)
        }
        .task(id: account.iumrahID) {
            while !Task.isCancelled && account.isAuthenticated {
                await reload()
                do { try await Task.sleep(for: .seconds(25)) } catch { break }
            }
        }
        .refreshable { await reload() }
    }
    private func friendCard(_ friend: IumrahReferralFriend) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AccountRewardsGlassIcon(symbol: "person.crop.circle.fill", color: .blue)
                VStack(alignment: .leading) {
                    Text(friend.name.isEmpty ? c.t("Name not provided", "Имя ещё не указано", "Ism ko‘rsatilmagan", "Исм кўрсатилмаган") : friend.name).font(.headline)
                    Text("iumrah ID · " + friend.id).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if friend.status == "earned" { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            switch friend.status {
            case "pending":
                Text(c.t("Awaiting payment", "Ожидается оплата", "To‘lov kutilmoqda", "Тўлов кутилмоқда")).font(.headline)
                Text(rewardMoney(friend.rewardUsd) + " · " + c.t("will be credited after your friend's payment", "начислим после оплаты вашего друга", "do‘stingiz to‘lagach hisoblanadi", "дўстингиз тўлагач ҳисобланади")).font(.subheadline).foregroundStyle(.secondary)
            case "earned": Text(rewardMoney(friend.rewardUsd) + " · " + c.t("Credited to your balance", "Начислено на баланс", "Balansga qo‘shildi", "Балансга қўшилди")).foregroundStyle(.green)
            case "cancelled", "ineligible": Text(c.t("Reward unavailable", "Вознаграждение недоступно", "Mukofot mavjud emas", "Мукофот мавжуд эмас")).foregroundStyle(.secondary)
            default: Text(c.t("Registered · no booking yet", "Зарегистрировался · ещё нет бронирования", "Ro‘yxatdan o‘tdi · hali bron yo‘q", "Рўйхатдан ўтди · ҳали брон йўқ")).foregroundStyle(.secondary)
            }
        }.iumrahCard()
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.72)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    private func explanation(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            AccountRewardsGlassIcon(symbol: symbol, color: .blue)
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
    }
}


struct IumrahAccountSavedHotelsEntry: View {
    let language: AppSettingsStore.Language
    private var c: AccountRewardsCopy { .init(language: language) }
    private var title: String { c.t("Saved hotels", "Сохранённые отели", "Saqlangan mehmonxonalar", "Сақланган меҳмонхоналар") }
    var body: some View {
        NavigationLink {
            AccountRewardsPage(title: title) {
                Text(c.t("Hotels saved on this device", "Отели, сохранённые на этом устройстве", "Bu qurilmada saqlangan mehmonxonalar", "Бу қурилмада сақланган меҳмонхоналар"))
                    .font(.subheadline).foregroundStyle(.secondary)
                NuiteeHotelsCatalogView(refreshSignal: 0, favoritesOnly: true)
            }
        } label: {
            HStack(spacing: 14) {
                AccountRewardsGlassIcon(symbol: "heart.fill", color: .red)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.title3, design: .rounded, weight: .bold))
                    Text(c.t("Your favorite stays", "Ваши избранные отели", "Sevimli mehmonxonalaringiz", "Севимли меҳмонхоналарингиз"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.foregroundStyle(.primary).iumrahCard()
        }.buttonStyle(.plain)
    }
}

private func rewardMoney(_ amount: Double?) -> String {
    guard let amount, amount.isFinite else { return "—" }
    return amount.formatted(.currency(code: "USD"))
}
