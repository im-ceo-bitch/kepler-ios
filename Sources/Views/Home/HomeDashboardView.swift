import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var journey: JourneyStore
    @ObservedObject private var clientNotifications = ClientNotificationCenter.shared
    @State private var showZiyarats = false
    @State private var showCareRequestBuilder = false
    @State private var showFlightsService = false
    @State private var showTransferService = false
    @State private var buildCarouselID: String? = "configurator"
    @State private var productsCarouselID: String? = "iumrah-system"
    @State private var integrationCarouselID: String? = "plan"
    @State private var expandedHomeFAQID: String?
    @State private var showAboutProject = false
    @State private var showGuidedFlightSelection = false
    @State private var focusJourneySearchRevision = 0
    @State private var journeySearchExpanded = false

    private var activeSession: StoredBookingSession? {
        bookings.sessions.first { $0.effectiveStatus.uppercased() != "COMPLETED" }
    }

    var body: some View {
        marketingHome
            .task(id: activeSession?.id) {
                // Do not compete with the first app frame. Booking refresh begins only
                // after Home is visibly mounted.
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                await bookings.refreshAll()
                while !Task.isCancelled {
                    if let activeSession { _ = try? await bookings.loadESIMs(for: activeSession.id) }
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                }
            }
            .navigationDestination(isPresented: $showZiyarats) {
                ZiyaratJourneyView()
                    .environmentObject(settings)
                    .environmentObject(chrome)
            }
            .navigationDestination(isPresented: $showCareRequestBuilder) {
                IumrahCareRequestView()
            }
            .navigationDestination(isPresented: $showFlightsService) {
                IumrahFlightsView()
            }
            .navigationDestination(isPresented: $showTransferService) {
                IumrahTransferServiceView()
            }
            .navigationDestination(isPresented: $showGuidedFlightSelection) {
                IumrahGuidedFlightSelectionView()
            }
            .navigationDestination(isPresented: $showAboutProject) {
                IumrahStoryView()
            }

    }

    private var marketingHome: some View {
        ScrollViewReader { scrollProxy in
            IumrahRootScrollingPage(onRefresh: {
                await bookings.refreshAll()
                await clientNotifications.refresh(accountToken: account.bearerToken)
            }, searchCardOverlap: 40, header: {
                IumrahHomeJourneySearchHero(onSearch: { showGuidedFlightSelection = true }, presentation: .header, searchExpanded: $journeySearchExpanded)
            }, content: {
                LazyVStack(spacing: 30) {
                    IumrahHomeJourneySearchHero(onSearch: { showGuidedFlightSelection = true }, presentation: .search, searchExpanded: $journeySearchExpanded)
                        .padding(.horizontal, -IumrahDesign.pagePadding)
                        .id("journey-search")
                    IumrahPageHelpCard("home.default")
                if !clientNotifications.homeNotifications.isEmpty {
                    SystemNotificationsCarouselView(
                        notifications: Array(clientNotifications.homeNotifications.prefix(5)),
                        onOpen: { openSystemNotification($0) },
                        onDismiss: { dismissSystemNotification($0) }
                    )
                }
                HomeEmotionalJourneyPrompt()
                HomeVideoCarousel()

                IumrahHomeServicesSection(
                    language: settings.language,
                    onTransfer: { showTransferService = true },
                    onESIM: { chrome.presentESIM() },
                    onFlights: { showFlightsService = true },
                    onZiyarats: { showZiyarats = true }
                )

                buildMyUmrahSection
                JourneyTravelInfoView(showsPageSelector: true)
                IumrahHomeAudienceSection(language: settings.language)
                homeIntegrationsSection

                VStack(alignment: .leading, spacing: 15) {
                    IumrahHomeSectionHeader(title: homeProductsTitle)
                    productsCarousel()
                    IumrahHomeCarouselDots(count: 3, selectedIndex: productsCarouselIndex)
                }

                confidenceStrip
                philosophyCard
                connectedTripCard
                personalUmrahFAQ
                homeAboutFooter
            }
            // Same adaptive page-column rule as Account/Gear. Padding is part of
            // the column first; the outer frame then clamps the whole tree to the viewport.
            .padding(.horizontal, IumrahDesign.pagePadding)
            // The first hero starts flush below the iPhone status-bar safe area.
            // A top gap exposes the page background between the status bar and hero.
            .padding(.bottom, 46)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(IumrahNoVerticalBounce())
            })
            .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
            .onChange(of: focusJourneySearchRevision) { _, _ in
                withAnimation(.easeInOut(duration: 0.28)) {
                    scrollProxy.scrollTo("journey-search", anchor: .top)
                }
            }
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea())
    }


    private func dismissSystemNotification(_ notification: ClientSystemNotification) {
        IumrahHaptics.selection()
        clientNotifications.dismissFromHome(notification)
    }

    private func openSystemNotification(_ notification: ClientSystemNotification) {
        IumrahHaptics.selection()
        Task { await clientNotifications.markOpened(notification, accountToken: account.bearerToken) }
        switch notification.destination {
        case "hotels": chrome.navigate(to: .hotels)
        case "bookings": chrome.navigate(to: .booking)
        case "care": chrome.navigate(to: .care)
        case "account": chrome.navigate(to: .account)
        case "booking":
            if let bookingID = notification.destinationBookingID, bookings.booking(id: bookingID) != nil {
                chrome.openBooking(id: bookingID)
            } else {
                chrome.navigate(to: .booking)
            }
        default: chrome.navigate(to: .home)
        }
    }

    private func activeJourneyHome(_ session: StoredBookingSession) -> some View {
        ZStack {
            Image("MakkahBackground")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.48), Color.black.opacity(0.12), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    IumrahRootPageTitle(
                        title: L10n.text("tab_home", settings.language),
                        showsMakkahTime: true,
                        lightStyle: true,
                        usesBrandLogo: true,
                        showsConnectivityStatus: true
                    )

                    activeBookingCard(session)
                    activeCareCard(session)

                    Color.clear
                        .frame(height: 330)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, IumrahDesign.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 30)
            }
        }
    }

    private func activeBookingCard(_ session: StoredBookingSession) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(alignment: .center) {
                Label(L10n.text("home_hero_kicker", settings.language), systemImage: "moon.stars.fill")
                    .font(.caption.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(Color.black.opacity(0.58))

                Spacer()

                IumrahIconBadge(
                    systemName: statusIcon(session.effectiveStatus),
                    role: IumrahBookingStatusVisual.role(for: session.effectiveStatus),
                    size: 36,
                    symbolSize: 15,
                    shape: .circle
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.status(session.effectiveStatus, settings.language))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(Color.black)

                if let travelerName = session.travelerName, !travelerName.isEmpty {
                    Text(travelerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.58))
                }
            }

            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)

            VStack(spacing: 12) {
                journeySummaryRow(
                    icon: "airplane",
                    title: L10n.text("route_label", settings.language),
                    value: "\(session.booking.route.originCode) → \(session.booking.route.outboundDestination)"
                )
                journeySummaryRow(
                    icon: "calendar",
                    title: L10n.text("detail_dates", settings.language),
                    value: "\(L10n.date(session.booking.input.startDate, settings.language)) – \(L10n.date(session.booking.input.endDate, settings.language))"
                )
                if !session.booking.hotelNames.makkah.isEmpty {
                    journeySummaryRow(
                        icon: "building.2.fill",
                        title: L10n.text("detail_hotel", settings.language),
                        value: session.booking.hotelNames.makkah
                    )
                }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("final_price", settings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.50))
                    Text(money(session.booking.perPilgrimUsd))
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black)
                }
                Spacer()
                if let pilgrimID = session.displayPilgrimID {
                    Text("ID \(pilgrimID)")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.42))
                }
            }

            NavigationLink {
                BookingDetailView(bookingID: session.id)
            } label: {
                HStack {
                    Text(L10n.text("open_booking", settings.language))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(Color.white.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
        }
    }

    private func journeySummaryRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IumrahIconBadge(systemName: icon, size: 34, symbolSize: 14, shape: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.black.opacity(0.48))
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func activeCareCard(_ session: StoredBookingSession) -> some View {
        Button {
            chrome.navigate(to: .care)
        } label: {
            HStack(spacing: 14) {
                Image("CareMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .padding(5)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("iumrah Care")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(L10n.text("care_subtitle", settings.language))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(16)
            .background {
                LinearGradient(
                    colors: [Color.iumrahCareDark.opacity(0.96), Color.iumrahCareLight.opacity(0.88)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(session.displayPilgrimID.map { "ID \($0)" } ?? "")
    }

    private var ziyaratsHomeCard: some View {
        Button {
            IumrahHaptics.selection()
            showZiyarats = true
        } label: {
            ZStack(alignment: .bottomLeading) {
                Image("ZiyaratQuba3")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 255)
                    .clipped()

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.16), Color.black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 7) {
                        Image(systemName: "map.fill")
                        Text("MAKKAH · MADINAH")
                    }
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.86))

                    Text(ziyaratsHomeTitle)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(.white)

                    Text(ziyaratsHomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(ziyaratsHomeCTA)
                    }.frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 255)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("iumrah Ziyarats")
    }

    private var ziyaratsHomeTitle: String {
        "iumrah Ziyarats"
    }

    private var ziyaratsHomeSubtitle: String {
        switch settings.language {
        case .russian: return "Священные и исторические места Мекки и Медины — в одном маршруте. Доступ к iumrah Ziyarats включён в iumrah Services вашего пакета."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Sacred and historic places across Makkah and Madinah in one journey. Access to iumrah Ziyarats is included with your package’s iumrah Services."
        case .uzbek: return "Makka va Madinadagi muqaddas hamda tarixiy joylar — bitta yo‘nalishda. iumrah Ziyarats sizning paketingizdagi iumrah Services tarkibiga kiradi."
        case .uzbekCyrillic: return "Макка ва Мадинадаги муқаддас ҳамда тарихий жойлар — битта йўналишда. iumrah Ziyarats сизнинг пакетингиздаги iumrah Services таркибига киради."
        }
    }

    private var ziyaratsHomeCTA: String {
        switch settings.language {
        case .russian: return "Открыть Ziyarats"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Open Ziyarats"
        case .uzbek: return "Ziyarats’ni ochish"
        case .uzbekCyrillic: return "Ziyarats’ни очиш"
        }
    }

    private var flightsWorldFooter: some View {
        let pageBackground = Color.iumrahPageBackground

        return VStack(spacing: 0) {
            Text("From the world to Mecca")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.7)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 34)
                .padding(.bottom, 8)
                .allowsHitTesting(false)

            ZStack {
                IumrahInteractiveGlobe(presentation: .worldToMakkah)
                    .frame(height: 390)
                    // Fade the complete MapKit surface itself, including its black sky,
                    // so no rectangular map boundary survives against Home's background.
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.00),
                                .init(color: .white.opacity(0.16), location: 0.08),
                                .init(color: .white, location: 0.25),
                                .init(color: .white, location: 0.73),
                                .init(color: .white.opacity(0.20), location: 0.93),
                                .init(color: .clear, location: 1.00)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }

                // A second two-sided blend uses the exact Home page background color.
                // This keeps the transition seamless in both light and dark appearance.
                LinearGradient(
                    stops: [
                        .init(color: pageBackground, location: 0.00),
                        .init(color: pageBackground.opacity(0.82), location: 0.07),
                        .init(color: .clear, location: 0.24),
                        .init(color: .clear, location: 0.74),
                        .init(color: pageBackground.opacity(0.78), location: 0.93),
                        .init(color: pageBackground, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .frame(height: 350)
            .clipped()
            .padding(.bottom, 84)
        }
        .frame(maxWidth: .infinity)
        .background(pageBackground)
    }

    private var buildMyUmrahSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            IumrahHomeSectionHeader(title: buildUmrahSectionTitle, subtitle: buildUmrahSectionSubtitle)

            GeometryReader { proxy in
                let cardWidth = max(298, min(proxy.size.width * 0.94, 352))
                let cardHeight: CGFloat = 540

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        hero
                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                            .id("configurator")
                        careRequestBuilderCard
                            .frame(width: cardWidth, height: cardHeight, alignment: .top)
                            .id("care-request")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $buildCarouselID, anchor: .center)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .scrollClipDisabled()
            }
            .frame(height: 554)

            IumrahHomeCarouselDots(count: 2, selectedIndex: buildCarouselID == "care-request" ? 1 : 0)
        }
        .padding(.bottom, 6)
    }

    private var careRequestBuilderCard: some View {
        Button {
            IumrahHaptics.soft()
            showCareRequestBuilder = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.black
                    Image("IumrahCareShowcaseCard")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(height: 220)
                .clipped()

                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 8) {
                        Label("Iumrah Care", systemImage: "heart.fill")
                            .font(.caption.weight(.bold))
                            .tracking(0.45)
                            .foregroundStyle(Color.black.opacity(0.58))
                        Spacer(minLength: 8)
                        Text(careRequestTimeBadge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.62))
                            .padding(.horizontal, 10)
                            .frame(height: 29)
                            .background(Color.black.opacity(0.055), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(careRequestCardTitle)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.75)
                            .foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(careRequestCardBody)
                            .font(.system(size: 15, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 10) {
                        Text(careRequestCardCTA)
                    }.frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var buildUmrahSectionTitle: String {
        switch settings.language {
        case .russian: return "Собрать свою Умру"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Build your Umrah"
        case .uzbek: return "Umrangizni tuzing"
        case .uzbekCyrillic: return "Умрангизни тузинг"
        }
    }

    private var buildUmrahSectionSubtitle: String {
        switch settings.language {
        case .russian: return "Соберите пакет сами за несколько минут или передайте подбор Iumrah Care."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Build the package yourself in minutes or let Iumrah Care prepare it for you."
        case .uzbek: return "Paketni bir necha daqiqada o‘zingiz tuzing yoki tanlovni Iumrah Care’ga topshiring."
        case .uzbekCyrillic: return "Пакетни бир неча дақиқада ўзингиз тузинг ёки танловни Iumrah Care’га топширинг."
        }
    }

    private var careRequestTimeBadge: String {
        switch settings.language {
        case .russian: return "ответ ≤ 2 ч"
        case .english, .turkish, .indonesian, .malay, .arabic: return "reply ≤ 2h"
        case .uzbek: return "javob ≤ 2 soat"
        case .uzbekCyrillic: return "жавоб ≤ 2 соат"
        }
    }

    private var careRequestCardTitle: String {
        switch settings.language {
        case .russian: return "Собрать Умру за меня"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Build my Umrah for me"
        case .uzbek: return "Umramni men uchun tuzing"
        case .uzbekCyrillic: return "Умрамни мен учун тузинг"
        }
    }

    private var careRequestCardBody: String {
        switch settings.language {
        case .russian: return "Укажите месяц или точные даты, бюджет, уровень отеля и главный приоритет. Iumrah Care соберёт персональный вариант."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Choose a month or exact dates, budget, hotel level and your main priority. Iumrah Care will prepare a personal option."
        case .uzbek: return "Oy yoki aniq sanalar, budjet, mehmonxona darajasi va asosiy ustuvorlikni belgilang. Iumrah Care shaxsiy variant tayyorlaydi."
        case .uzbekCyrillic: return "Ой ёки аниқ саналар, бюджет, меҳмонхона даражаси ва асосий устуворликни белгиланг. Iumrah Care шахсий вариант тайёрлайди."
        }
    }

    private var careRequestCardCTA: String {
        switch settings.language {
        case .russian: return "Рассказать о поездке"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Tell us about the trip"
        case .uzbek: return "Safar haqida aytish"
        case .uzbekCyrillic: return "Сафар ҳақида айтиш"
        }
    }


    private var homeIntegrationsSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            IumrahHomeSectionHeader(title: integrationsTitle, subtitle: integrationsSubtitle)

            GeometryReader { proxy in
                let availableWidth = max(proxy.size.width, 1)
                let cardWidth = min(max(availableWidth * 0.88, 286), availableWidth)
                let cardHeight: CGFloat = 448
                let cardShape = RoundedRectangle(cornerRadius: 34, style: .continuous)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        NavigationLink {
                            UmrahPlanHubView()
                        } label: {
                            integrationCard(
                                asset: "HomeIntegrationCalendar",
                                badge: integrationPlanBadge,
                                title: integrationPlanTitle,
                                body: integrationPlanBody,
                                cta: integrationOpenCTA
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("plan")

                        NavigationLink {
                            IumrahTelegramIntegrationView(preferredBookingID: bookings.sessions.first?.id)
                        } label: {
                            integrationCard(
                                asset: "TelegramIntegrationHero",
                                badge: "Telegram",
                                title: integrationTelegramTitle,
                                body: integrationTelegramBody,
                                cta: integrationConnectCTA
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("telegram")

                        integrationCard(
                            asset: "HomeIntegrationSoon",
                            badge: integrationSoonBadge,
                            title: integrationSoonTitle,
                            body: integrationSoonBody,
                            cta: nil
                        )
                        .frame(width: cardWidth, height: cardHeight)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("soon")
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .scrollPosition(id: $integrationCarouselID, anchor: .center)
                .contentMargins(.horizontal, 0, for: .scrollContent)
                .scrollClipDisabled()
            }
            .frame(height: 448)

            IumrahHomeCarouselDots(count: 3, selectedIndex: integrationCarouselIndex)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func integrationCard(asset: String, badge: String, title: String, body: String, cta: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Color.white
                Image(asset)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 210)
            .clipped()

            VStack(alignment: .leading, spacing: 10) {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .tracking(-0.45)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Text(cta ?? integrationSoonBadge)
                    Spacer(minLength: 8)
                    Image(systemName: cta == nil ? "clock.fill" : "arrow.right")
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(cta == nil ? Color.secondary : Color.white)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(
                    cta == nil ? Color.iumrahRaisedBackground : Color.black,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color.iumrahCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8)
        }
    }

    private var integrationCarouselIndex: Int {
        switch integrationCarouselID {
        case "telegram": return 1
        case "soon": return 2
        default: return 0
        }
    }

    private var integrationsTitle: String {
        switch settings.language {
        case .russian: return "Интеграции"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Integrations"
        case .uzbek: return "Integratsiyalar"
        case .uzbekCyrillic: return "Интеграциялар"
        }
    }

    private var integrationsSubtitle: String {
        switch settings.language {
        case .russian: return "Планируйте следующую Umrah, подключайте Telegram и используйте новые возможности iumrah в одном месте."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Plan your next Umrah, connect Telegram and access new iumrah integrations in one place."
        case .uzbek: return "Keyingi Umrani rejalashtiring, Telegram’ni ulang va yangi iumrah integratsiyalaridan bir joyda foydalaning."
        case .uzbekCyrillic: return "Кейинги Умрани режалаштиринг, Telegram’ни уланг ва янги iumrah интеграцияларидан бир жойда фойдаланинг."
        }
    }

    private var integrationPlanBadge: String {
        switch settings.language {
        case .russian: return "ПЛАНИРОВАНИЕ"
        case .english, .turkish, .indonesian, .malay, .arabic: return "PLANNING"
        case .uzbek: return "REJALASHTIRISH"
        case .uzbekCyrillic: return "РЕЖАЛАШТИРИШ"
        }
    }

    private var integrationPlanTitle: String {
        switch settings.language {
        case .russian: return "Запланировать Umrah"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Plan your Umrah"
        case .uzbek: return "Umrani rejalashtirish"
        case .uzbekCyrillic: return "Умрани режалаштириш"
        }
    }

    private var integrationPlanBody: String {
        switch settings.language {
        case .russian: return "Выберите будущие даты и настройте напоминания за 2 месяца, месяц и последние дни перед поездкой."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Choose future dates and set reminders for two months, one month and the final days before departure."
        case .uzbek: return "Kelajakdagi sanalarni tanlang va safargacha 2 oy, 1 oy hamda so‘nggi kunlar uchun eslatmalarni sozlang."
        case .uzbekCyrillic: return "Келажакдаги саналарни танланг ва сафаргача 2 ой, 1 ой ҳамда сўнгги кунлар учун эслатмаларни созланг."
        }
    }

    private var integrationTelegramTitle: String {
        switch settings.language {
        case .russian: return "Статус бронирования в Telegram"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Booking status in Telegram"
        case .uzbek: return "Bron holati Telegram’da"
        case .uzbekCyrillic: return "Брон ҳолати Telegram’да"
        }
    }

    private var integrationTelegramBody: String {
        switch settings.language {
        case .russian: return "Получайте изменения статуса, оплаты, подтверждения и документов прямо в Telegram."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Receive status, payment, confirmation and document updates directly in Telegram."
        case .uzbek: return "Status, to‘lov, tasdiq va hujjat yangilanishlarini to‘g‘ridan-to‘g‘ri Telegram’da oling."
        case .uzbekCyrillic: return "Статус, тўлов, тасдиқ ва ҳужжат янгиланишларини тўғридан-тўғри Telegram’да олинг."
        }
    }

    private var integrationSoonBadge: String {
        switch settings.language {
        case .russian: return "СКОРО"
        case .english, .turkish, .indonesian, .malay, .arabic: return "COMING SOON"
        case .uzbek: return "TEZ ORADA"
        case .uzbekCyrillic: return "ТЕЗ ОРАДА"
        }
    }

    private var integrationSoonTitle: String {
        switch settings.language {
        case .russian: return "Следующая интеграция"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Next integration"
        case .uzbek: return "Keyingi integratsiya"
        case .uzbekCyrillic: return "Кейинги интеграция"
        }
    }

    private var integrationSoonBody: String {
        switch settings.language {
        case .russian: return "Мы готовим ещё один способ связать iumrah с сервисами, которыми Вы пользуетесь каждый день."
        case .english, .turkish, .indonesian, .malay, .arabic: return "We are preparing another way to connect iumrah with the services you use every day."
        case .uzbek: return "iumrah’ni har kuni foydalanadigan servislaringiz bilan bog‘lashning yana bir usulini tayyorlayapmiz."
        case .uzbekCyrillic: return "iumrah’ни ҳар куни фойдаланадиган сервисларингиз билан боғлашнинг яна бир усулини тайёрлаяпмиз."
        }
    }

    private var integrationOpenCTA: String {
        switch settings.language {
        case .russian: return "Запланировать"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Plan trip"
        case .uzbek: return "Rejalashtirish"
        case .uzbekCyrillic: return "Режалаштириш"
        }
    }

    private var integrationConnectCTA: String {
        switch settings.language {
        case .russian: return "Открыть Telegram"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Open Telegram"
        case .uzbek: return "Telegram’ni ochish"
        case .uzbekCyrillic: return "Telegram’ни очиш"
        }
    }

    private var homeProductsTitle: String {
        switch settings.language {
        case .russian: return "Наши продукты"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Our products"
        case .uzbek: return "Mahsulotlarimiz"
        case .uzbekCyrillic: return "Маҳсулотларимиз"
        }
    }

    private var hero: some View {
        Button {
            IumrahHaptics.soft()
            // Reuse the actual Home search instead of launching the retired
            // Bookings-tab configurator from a second marketing CTA.
            withAnimation(.easeInOut(duration: 0.28)) { journeySearchExpanded = true }
            focusJourneySearchRevision += 1
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Color.black

                    Image("StoreConfiguratorPhones")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipped()

                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 8) {
                        IumrahOrbitIconRing(diameter: 44, lightOnDark: false)
                            .accessibilityIdentifier("iumrah.orbit.home.configurator")
                        Label("Iumrah Configurator", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.bold))
                            .tracking(0.45)
                            .foregroundStyle(Color.black.opacity(0.58))
                        Spacer(minLength: 8)
                        Text(configuratorTimeBadge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.black.opacity(0.62))
                            .padding(.horizontal, 10)
                            .frame(height: 29)
                            .background(Color.black.opacity(0.055), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(configuratorHeroTitle)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.75)
                            .foregroundStyle(.black)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(configuratorHeroBody)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.62))
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 10) {
                        Text(configuratorHeroCTA)
                    }.frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.055), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuratorHeroTitle)
    }

    private var configuratorTimeBadge: String {
        switch settings.language {
        case .russian: return "≈ 5 минут"
        case .english, .turkish, .indonesian, .malay, .arabic: return "≈ 5 min"
        case .uzbek: return "≈ 5 daqiqa"
        case .uzbekCyrillic: return "≈ 5 дақиқа"
        }
    }

    private var configuratorHeroTitle: String {
        switch settings.language {
        case .russian: return "Соберите свою Умру за 5 минут"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Build your Umrah in 5 minutes"
        case .uzbek: return "Umrangizni 5 daqiqada tuzing"
        case .uzbekCyrillic: return "Умрангизни 5 дақиқада тузинг"
        }
    }

    private var configuratorHeroBody: String {
        switch settings.language {
        case .russian: return "Персональный пакет для вас, вашей семьи или друзей — без обязательной туристической группы из 30–50 человек. Перелёт, отель, трансфер и Iumrah Services собираются в одну поездку."
        case .english, .turkish, .indonesian, .malay, .arabic: return "A personal package for you, your family or friends — without having to join a 30–50 person tour group. Flights, hotel, transfer and Iumrah Services come together as one journey."
        case .uzbek: return "Siz, oilangiz yoki do‘stlaringiz uchun shaxsiy paket — 30–50 kishilik majburiy tur guruhisiz. Parvoz, mehmonxona, transfer va Iumrah Services bitta safarga birlashadi."
        case .uzbekCyrillic: return "Сиз, оилангиз ёки дўстларингиз учун шахсий пакет — 30–50 кишилик мажбурий тур гуруҳисиз. Парвоз, меҳмонхона, трансфер ва Iumrah Services битта сафарга бирлашади."
        }
    }

    private var configuratorHeroCTA: String {
        switch settings.language {
        case .russian: return "Собрать мою Умру"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Create my Umrah"
        case .uzbek: return "Umramni yaratish"
        case .uzbekCyrillic: return "Умрамни яратиш"
        }
    }

    private var friendsHomeCard: some View {
        NavigationLink {
            IumrahGiftCardsView()
        } label: {
            HStack(spacing: 16) {
                IumrahIconBadge(systemName: "gift.fill", role: .gift, size: 82, symbolSize: 25, cornerRadius: 22)
                .overlay(alignment: .topTrailing) {
                    Text("3")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(.white, in: Circle())
                        .offset(x: 5, y: -5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Text("iumrah Gift Card")
                            .font(.headline)
                        Text("3 × $100")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    Text(friendsHomeSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .iumrahHomeFlatCard()
        }
        .buttonStyle(.plain)
    }

    private var friendsHomeSubtitle: String {
        switch settings.language {
        case .russian: return "Подарочные карты для близких · $100 на умру и $100 в iUmrah Balance после подтверждения и оплаты."
        case .english, .turkish, .indonesian, .malay, .arabic: return "Gift cards for someone close · $100 toward Umrah and $100 in iUmrah Balance after confirmation and payment."
        case .uzbek: return "Yaqinlar uchun Gift Card · Umrah uchun $100 va tasdiqlanib to‘langach $100 iUmrah Balance."
        case .uzbekCyrillic: return "Яқинлар учун Gift Card · Умра учун $100 ва тасдиқланиб тўлангач $100 iUmrah Balance."
        }
    }

    private var confidenceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(icon: "building.2.fill", text: L10n.text("tab_hotels", settings.language))
                chip(icon: "airplane", text: L10n.text("step_flight", settings.language))
                chip(icon: "heart.fill", text: "iumrah Care")
            }
        }
    }

    private func chip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.iumrahCardBackground)
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.05), lineWidth: 1) }
    }

    private var philosophyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("iumrah")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.iumrahRaisedBackground)
                .clipShape(Capsule())
            Text(L10n.text("home_philosophy_title", settings.language))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(L10n.text("home_philosophy_body", settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iumrahHomeFlatCard(padding: 22, radius: IumrahDesign.heroRadius)
    }

    private var connectedTripCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                journeyIcon("airplane")
                connector
                journeyIcon("building.2.fill")
                connector
                journeyIcon("car.fill")
                connector
                journeyIcon("moon.stars.fill")
                connector
                journeyIcon("heart.fill")
            }

            Text(L10n.text("home_connected_title", settings.language))
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text(L10n.text("home_connected_body", settings.language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iumrahHomeFlatCard(padding: 22, radius: IumrahDesign.heroRadius)
    }

    private var esimHomeCard: some View {
        Button { chrome.presentESIM() } label: {
            homeFeatureCard(
                imageName: "IumrahESIMHomeCard",
                title: "iumrah eSIM",
                body: homeESIMFeatureBody,
                ctaTitle: homeESIMCopy(.details),
                ctaIcon: "antenna.radiowaves.left.and.right",
                ctaRole: .connectivity,
                statusText: homeESIMStatusLine,
                accent: Color(uiColor: .systemTeal)
            )
        }
        .buttonStyle(.plain)
    }

    private enum HomeESIMCopyKey { case left, ready, assigned, activate, open, packageOnly, details }

    private func homeESIMCopy(_ key: HomeESIMCopyKey) -> String {
        switch (settings.language, key) {
        case (.russian, .left): return "осталось"
        case (.russian, .ready): return "Профиль готов. Активируйте eSIM на iPhone."
        case (.russian, .assigned): return "eSIM привязана к вашей поездке."
        case (.russian, .activate): return "Активировать eSIM"
        case (.russian, .open): return "Открыть eSIM"
        case (.russian, .packageOnly): return "В1 версии eSIM доступна только внутри Umra-пакета."
        case (.russian, .details): return "Тарифы и активация"
        case (.english, .left): return "left"
        case (.english, .ready): return "Profile ready. Activate the eSIM on your iPhone."
        case (.english, .assigned): return "eSIM is linked to your trip."
        case (.english, .activate): return "Activate eSIM"
        case (.english, .open): return "Open eSIM"
        case (.english, .packageOnly): return "In V1, eSIM is available only as part of the Umrah package."
        case (.english, .details): return "Plans & activation"
        case (.uzbek, .left): return "qoldi"
        case (.uzbek, .ready): return "Profil tayyor. eSIM’ni iPhone’da faollashtiring."
        case (.uzbek, .assigned): return "eSIM safaringizga biriktirilgan."
        case (.uzbek, .activate): return "eSIM’ni faollashtirish"
        case (.uzbek, .open): return "eSIM’ni ochish"
        case (.uzbek, .packageOnly): return "V1’da eSIM faqat Umra paketi tarkibida mavjud."
        case (.uzbek, .details): return "Tariflar va faollashtirish"
        case (.uzbekCyrillic, .left): return "қолди"
        case (.uzbekCyrillic, .ready): return "Профиль тайёр. eSIM’ни iPhone’да фаоллаштиринг."
        case (.uzbekCyrillic, .assigned): return "eSIM сафарингизга бириктирилган."
        case (.uzbekCyrillic, .activate): return "eSIM’ни фаоллаштириш"
        case (.uzbekCyrillic, .open): return "eSIM’ни очиш"
        case (.uzbekCyrillic, .packageOnly): return "V1’да eSIM фақат Umra пакети таркибида мавжуд."
        case (.uzbekCyrillic, .details): return "Тарифлар ва фаоллаштириш"
                case (.turkish, .left): return "kaldı"
        case (.turkish, .ready): return "Profil hazır. eSIM’i iPhone’unuzda etkinleştirin."
        case (.turkish, .assigned): return "eSIM seyahatinize bağlandı."
        case (.turkish, .activate): return "eSIM’i etkinleştir"
        case (.turkish, .open): return "eSIM’i aç"
        case (.turkish, .packageOnly): return "İlk sürümde eSIM yalnızca Umre paketine dahildir."
        case (.turkish, .details): return "Paketler ve etkinleştirme"
        case (.indonesian, .left): return "tersisa"
        case (.indonesian, .ready): return "Profil siap. Aktifkan eSIM di iPhone Anda."
        case (.indonesian, .assigned): return "eSIM telah ditautkan ke perjalanan Anda."
        case (.indonesian, .activate): return "Aktifkan eSIM"
        case (.indonesian, .open): return "Buka eSIM"
        case (.indonesian, .packageOnly): return "Pada versi pertama, eSIM hanya tersedia dalam paket Umrah."
        case (.indonesian, .details): return "Paket dan aktivasi"
        case (.malay, .left): return "berbaki"
        case (.malay, .ready): return "Profil sedia. Aktifkan eSIM pada iPhone anda."
        case (.malay, .assigned): return "eSIM telah dipautkan kepada perjalanan anda."
        case (.malay, .activate): return "Aktifkan eSIM"
        case (.malay, .open): return "Buka eSIM"
        case (.malay, .packageOnly): return "Dalam versi pertama, eSIM hanya tersedia dalam pakej Umrah."
        case (.malay, .details): return "Pelan dan pengaktifan"
        case (.arabic, .left): return "متبقي"
        case (.arabic, .ready): return "الملف جاهز. فعّل الشريحة الإلكترونية على iPhone."
        case (.arabic, .assigned): return "تم ربط الشريحة الإلكترونية برحلتك."
        case (.arabic, .activate): return "تفعيل الشريحة الإلكترونية"
        case (.arabic, .open): return "فتح الشريحة الإلكترونية"
        case (.arabic, .packageOnly): return "في الإصدار الأول، تتوفر الشريحة الإلكترونية ضمن باقة العمرة فقط."
        case (.arabic, .details): return "الباقات والتفعيل"
        }
    }

    private var homeESIMFeatureBody: String {
        if let session = activeSession, let profile = bookings.primaryESIM(for: session.id) {
            return profile.hasActivationData ? homeESIMCopy(.ready) : homeESIMCopy(.assigned)
        }
        return homeESIMCopy(.packageOnly)
    }

    private var homeESIMStatusLine: String? {
        guard let session = activeSession, let profile = bookings.primaryESIM(for: session.id) else { return nil }
        if profile.usageAvailable {
            return "\(homeDataText(profile.remainingMB)) \(homeESIMCopy(.left))"
        }
        return profile.hasActivationData ? homeESIMCopy(.activate) : homeESIMCopy(.open)
    }

    private func homeDataText(_ value: Double) -> String {
        if value >= 1024 {
            return String(format: "%.1f GB", value / 1024)
        }
        return "\(Int(max(0, value).rounded())) MB"
    }

    private func journeyIcon(_ name: String) -> some View {
        IumrahIconBadge(systemName: name, size: 34, symbolSize: 13, shape: .circle)
    }

    private var connector: some View {
        Capsule()
            .fill(Color.primary.opacity(0.10))
            .frame(maxWidth: .infinity)
            .frame(height: 2)
    }

    private var flightsHomeCard: some View {
        NavigationLink {
            IumrahFlightsView()
        } label: {
            homeFeatureCard(
                imageName: "IumrahFlightsHomeCard",
                title: "iumrah Flights",
                body: homeFlightsFeatureBody,
                ctaTitle: homeFlightsCTA,
                ctaIcon: "airplane",
                ctaRole: .travel,
                statusText: nil,
                accent: Color(uiColor: .systemBlue)
            )
        }
        .buttonStyle(.plain)
    }

    private var careShowcaseCard: some View {
        Button {
            chrome.navigate(to: .care)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image("IumrahCareShowcaseCard")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.015, green: 0.035, blue: 0.09))

                VStack(alignment: .leading, spacing: 12) {
                    Text("iumrah Care")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .tracking(-0.55)
                    Text(L10n.text("hotel_care_card_body", settings.language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 9) {
                        Image(systemName: "phone.fill")
                        Text(homeCareCTA)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.iumrahPrimaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Color.iumrahPrimaryButtonText)
                }
                .padding(20)
            }
            .background(Color.iumrahCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var homeAboutFooter: some View {
        Button {
            IumrahHaptics.soft()
            showAboutProject = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Image("AboutIumrahKaabaCorner")
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 236)
                        .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.62)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(homeSinceTitle)
                            .font(.caption.weight(.bold))
                            .tracking(0.9)
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.76))
                        Text(homeAboutCardTitle)
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                            .tracking(-0.55)
                            .foregroundStyle(.white)
                    }
                    .padding(18)
                }
                .frame(height: 236)

                VStack(alignment: .leading, spacing: 15) {
                    Text(homeSinceBody)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Text(homeAboutCTA)
                    }.frame(maxWidth: .infinity)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.iumrahPrimaryButtonText)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        Color.iumrahPrimaryButtonBackground,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                    )
                }
                .padding(18)
            }
            .background(Color.iumrahCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var homeAboutCardTitle: String {
        switch settings.language {
        case .russian: return "О проекте iumrah"
        case .english, .turkish, .indonesian, .malay, .arabic: return "About iumrah"
        case .uzbek: return "iumrah haqida"
        case .uzbekCyrillic: return "iumrah ҳақида"
        }
    }

    private func productsCarousel() -> some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width, 1)
            let cardWidth = min(max(availableWidth * 0.88, 286), availableWidth)
            let cardHeight: CGFloat = 472
            let cardShape = RoundedRectangle(cornerRadius: 34, style: .continuous)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 16) {
                    IumrahBackendSystemHomeCard()
                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("iumrah-system")

                    homeAdvisorProductCard
                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("iumrah-advisor")

                    homeSundayClubProductCard
                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        .clipShape(cardShape)
                        .contentShape(cardShape)
                        .id("sunday-umrah-club")
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $productsCarouselID, anchor: .center)
            .contentMargins(.horizontal, 0, for: .scrollContent)
            .scrollClipDisabled()
        }
        .frame(height: 472)
    }

    private var productsCarouselIndex: Int {
        switch productsCarouselID {
        case "iumrah-advisor": return 1
        case "sunday-umrah-club": return 2
        default: return 0
        }
    }

    private var homeSundayClubProductCard: some View {
        Button {
            IumrahHaptics.soft()
            chrome.openHotels(board: .sundayClub)
        } label: {
            VStack(spacing: 0) {
                ZStack {
                    Color.white
                    Image("SundayUmrahClubHome")
                        .resizable()
                        .scaledToFit()
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 236)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sunday Umrah Club")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(.black)

                    Text(sundayClubProductBody)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.black.opacity(0.60))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Text(sundayClubProductCTA)
                    }.frame(maxWidth: .infinity)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    private var sundayClubProductBody: String {
        switch settings.language {
        case .russian: return "Короткая Умра на выходные: готовые даты, удобный маршрут и минимум времени вне работы."
        case .english, .turkish, .indonesian, .malay, .arabic: return "A weekend-sized Umrah with ready dates, a compact route and less time away from work."
        case .uzbek: return "Dam olish kunlariga mos qisqa Umra: tayyor sanalar, qulay yo‘nalish va ishdan kamroq uzilish."
        case .uzbekCyrillic: return "Дам олиш кунларига мос қисқа Умра: тайёр саналар, қулай йўналиш ва ишдан камроқ узилиш."
        }
    }

    private var sundayClubProductCTA: String {
        switch settings.language {
        case .russian: return "Открыть Sunday Club"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Open Sunday Club"
        case .uzbek: return "Sunday Club’ni ochish"
        case .uzbekCyrillic: return "Sunday Club’ни очиш"
        }
    }

    private var homeAdvisorProductCard: some View {
        NavigationLink {
            UmrahFlowRootView(
                initialStage: .start,
                guideLanguage: UmrahGuideLanguage.preferred(for: settings.language)
            )
        } label: {
            ZStack {
                // The living Advisor aura now fills the ENTIRE product card.
                // There is no static black lower half: the gradient keeps moving
                // underneath the title, body and CTA as one continuous surface.
                UmrahAdvisorHomeAura()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.badge.mic")
                                .font(.system(size: 13, weight: .bold))
                            Text("iumrah Advisor")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .tracking(0.45)
                        }
                        .foregroundStyle(.white.opacity(0.92))

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 38, height: 38)
                            .iumrahGlass(in: Circle(), tint: .white.opacity(0.09))
                    }

                    Spacer(minLength: 24)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.075))
                            .frame(width: 106, height: 106)
                            .blur(radius: 1)

                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            .frame(width: 106, height: 106)

                        Image(systemName: "waveform")
                            .font(.system(size: 42, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)

                    VStack(alignment: .leading, spacing: 9) {
                        Text(homeAdvisorProductTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .tracking(-0.65)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(homeAdvisorProductBody)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.70))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text(homeAdvisorProductCTA)
                        }.frame(maxWidth: .infinity)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 17)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .padding(.top, 5)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded { IumrahHaptics.soft() }
        )
    }

    private func homeFeatureCard(
        imageName: String,
        title: String,
        body: String,
        ctaTitle: String,
        ctaIcon: String,
        ctaRole: IumrahIconRole,
        statusText: String?,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 214)
                .clipped()
                .background(Color(red: 0.015, green: 0.035, blue: 0.09))

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(.system(size: 15.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusText, !statusText.isEmpty {
                    Text(statusText)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(accent.opacity(0.10), in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 10) {
                    Image(systemName: ctaIcon)
                        .symbolRenderingMode(.monochrome)
                    Text(ctaTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.iumrahPrimaryButtonText)
                .padding(.horizontal, 17)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    Color.iumrahPrimaryButtonBackground,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
            .padding(22)
        }
        .background(Color.iumrahCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
        }
    }

    private var homeFlightsFeatureBody: String {
        switch settings.language {
        case .russian:
            return "Опубликованные рейсы Umrah, подбор направления и перелёта под ваш пакет в одном месте."
        case .english, .turkish, .indonesian, .malay, .arabic:
            return "Published Umrah flights and route selection for your package in one place."
        case .uzbek:
            return "Umra uchun e’lon qilingan reyslar va paketingizga mos parvozni bitta joyda tanlash."
        case .uzbekCyrillic:
            return "Умра учун эълон қилинган рейслар ва пакетингизга мос парвозни битта жойда танлаш."
        }
    }

    private var homeFlightsCTA: String {
        switch settings.language {
        case .russian: return "Подобрать перелёт"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Choose flights"
        case .uzbek: return "Parvozni tanlash"
        case .uzbekCyrillic: return "Парвозни танлаш"
        }
    }

    private var homeCareCTA: String {
        switch settings.language {
        case .russian: return "Связаться с Care"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Contact Care"
        case .uzbek: return "Care bilan bog‘lanish"
        case .uzbekCyrillic: return "Care билан боғланиш"
        }
    }

    private var homeAdvisorProductTitle: String {
        switch settings.language {
        case .russian: return "Голосовой iumrah Advisor"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Voice iumrah Advisor"
        case .uzbek: return "Ovozli iumrah Advisor"
        case .uzbekCyrillic: return "Овозли iumrah Advisor"
        }
    }

    private var homeAdvisorProductBody: String {
        switch settings.language {
        case .russian: return "Пошаговый голосовой гид по Умре с поддержкой нескольких языков, чтобы паломник не оставался один во время ритуалов."
        case .english, .turkish, .indonesian, .malay, .arabic: return "A step-by-step voice guide for Umrah in multiple languages, so the pilgrim is not left alone during the rituals."
        case .uzbek: return "Umra marosimlari davomida ziyoratchi yolg‘iz qolmasligi uchun bir nechta tillarda bosqichma-bosqich ovozli gid."
        case .uzbekCyrillic: return "Умра маросимлари давомида зиёратчи ёлғиз қолмаслиги учун бир нечта тилларда босқичма-босқич овозли гид."
        }
    }

    private var homeAdvisorProductCTA: String {
        switch settings.language {
        case .russian: return "Открыть Advisor"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Open Advisor"
        case .uzbek: return "Advisorni ochish"
        case .uzbekCyrillic: return "Advisorни очиш"
        }
    }

    private var homeAboutCTA: String {
        switch settings.language {
        case .russian: return "Открыть страницу проекта"
        case .english, .turkish, .indonesian, .malay, .arabic: return "Open the project page"
        case .uzbek: return "Loyiha sahifasini ochish"
        case .uzbekCyrillic: return "Лойиҳа саҳифасини очиш"
        }
    }

    private var homeSinceTitle: String {
        switch settings.language {
        case .russian: return "3 года опыта"
        case .english, .turkish, .indonesian, .malay, .arabic: return "3 years of experience"
        case .uzbek: return "3 yillik tajriba"
        case .uzbekCyrillic: return "3 йиллик тажриба"
        }
    }

    private var homeSinceBody: String {
        switch settings.language {
        case .russian:
            return "iumrah — проект персональной и независимой Умры: собрать маршрут, отель, трансфер и сопровождение в одном спокойном приложении."
        case .english, .turkish, .indonesian, .malay, .arabic:
            return "iumrah is a personal independent Umrah project: build your route, hotel, transfer and care in one calm application."
        case .uzbek:
            return "iumrah — shaxsiy va mustaqil Umra loyihasi: yo‘nalish, mehmonxona, transfer va yordamni bitta sokin ilovada jamlash uchun yaratilgan."
        case .uzbekCyrillic:
            return "iumrah — шахсий ва мустақил Умра лойиҳаси: йўналиш, меҳмонхона, трансфер ва ёрдамни битта сокин иловада жамлаш учун яратилган."
        }
    }

    private var personalUmrahFAQ: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("iumrah")
                    .font(.caption.weight(.bold))
                    .tracking(0.9)
                    .foregroundStyle(.secondary)

                Text(personalUmrahFAQTitle)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.6)

                Text(personalUmrahFAQSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(Array(homeFAQItems.enumerated()), id: \.element.id) { index, item in
                    Button {
                        IumrahHaptics.selection()
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                            expandedHomeFAQID = expandedHomeFAQID == item.id ? nil : item.id
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(item.question)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer(minLength: 8)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(expandedHomeFAQID == item.id ? 180 : 0))
                            }
                            .padding(.vertical, 16)

                            if expandedHomeFAQID == item.id {
                                Text(item.answer)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 17)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < homeFAQItems.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 18)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 0)
    }

    private var personalUmrahFAQTitle: String {
        switch settings.language {
        case .russian: return "Персональная Умра — для вас и ваших близких"
        case .english, .turkish, .indonesian, .malay, .arabic: return "A personal Umrah — for you and the people you choose"
        case .uzbek: return "Shaxsiy Umra — siz va yaqinlaringiz uchun"
        case .uzbekCyrillic: return "Шахсий Умра — сиз ва яқинларингиз учун"
        }
    }

    private var personalUmrahFAQSubtitle: String {
        switch settings.language {
        case .russian: return "iumrah не привязывает вас к стандартной группе. Соберите поездку для себя, семьи или друзей и управляйте ею как одной персональной Umrah."
        case .english, .turkish, .indonesian, .malay, .arabic: return "iumrah does not tie you to a standard tour group. Build one personal Umrah for yourself, your family or friends and manage the journey in one place."
        case .uzbek: return "iumrah sizni standart tur guruhiga bog‘lamaydi. O‘zingiz, oilangiz yoki do‘stlaringiz uchun shaxsiy Umra tuzing va safarni bitta joydan boshqaring."
        case .uzbekCyrillic: return "iumrah сизни стандарт тур гуруҳига боғламайди. Ўзингиз, оилангиз ёки дўстларингиз учун шахсий Умра тузинг ва сафарни битта жойдан бошқаринг."
        }
    }

    private var homeFAQItems: [HomeFAQItem] {
        switch settings.language {
        case .russian:
            return [
                HomeFAQItem(id: "what", question: "Что такое iumrah?", answer: "iumrah — платформа для самостоятельной и персональной Умры. Она помогает собрать перелёт, отель, трансфер и сервисы в один понятный пакет и затем вести поездку в одном приложении."),
                HomeFAQItem(id: "why", question: "Почему был создан iumrah?", answer: "Чтобы паломнику не приходилось зависеть от большой туристической группы или разбираться в десятках разрозненных бронирований. Идея iumrah — дать больше контроля, прозрачности и заботы на каждом этапе поездки."),
                HomeFAQItem(id: "personal", question: "Что значит «персональная Умра»?", answer: "Поездка собирается вокруг вас: ваших дат, бюджета, уровня отеля и выбранных услуг. Это не обязательная группа из 30–50 незнакомых людей — вы сами выбираете, с кем совершать Умру."),
                HomeFAQItem(id: "family", question: "Можно поехать только с семьёй или друзьями?", answer: "Да. Пакет можно собрать для одного человека, пары, семьи или друзей. В поездке остаются только те люди, которых вы сами добавили."),
                HomeFAQItem(id: "care", question: "А если я не хочу собирать всё самостоятельно?", answer: "Обратитесь в iumrah Care. Мы поможем подобрать вариант, проверить детали и оформить поездку, сохранив персональный формат без обязательной большой группы.")
            ]
        case .english, .turkish, .indonesian, .malay, .arabic:
            return [
                HomeFAQItem(id: "what", question: "What is iumrah?", answer: "iumrah is a platform for independent, personal Umrah. It brings flights, hotel, transfer and services into one clear package and then keeps the journey in one app."),
                HomeFAQItem(id: "why", question: "Why was iumrah created?", answer: "So a pilgrim does not have to depend on a large tour group or manage many disconnected bookings. iumrah is built around more control, transparency and care throughout the journey."),
                HomeFAQItem(id: "personal", question: "What does ‘personal Umrah’ mean?", answer: "The journey is built around your dates, budget, hotel level and chosen services. There is no required group of 30–50 strangers — you decide who travels with you."),
                HomeFAQItem(id: "family", question: "Can I travel only with family or friends?", answer: "Yes. Build a package for one person, a couple, family or friends. Your journey contains only the people you choose to add."),
                HomeFAQItem(id: "care", question: "What if I do not want to build everything myself?", answer: "Contact iumrah Care. We can help select, verify and arrange the trip while keeping the personal format without a required large group.")
            ]
        case .uzbek:
            return [
                HomeFAQItem(id: "what", question: "iumrah nima?", answer: "iumrah — mustaqil va shaxsiy Umra uchun platforma. U parvoz, mehmonxona, transfer va xizmatlarni bitta tushunarli paketga birlashtiradi va safarni bitta ilovada boshqarishga yordam beradi."),
                HomeFAQItem(id: "why", question: "iumrah nima uchun yaratildi?", answer: "Ziyoratchi katta tur guruhiga bog‘lanib qolmasligi va ko‘plab alohida bronlarni boshqarmasligi uchun. iumrah safar davomida ko‘proq nazorat, shaffoflik va g‘amxo‘rlik berish uchun yaratilgan."),
                HomeFAQItem(id: "personal", question: "«Shaxsiy Umra» nimani anglatadi?", answer: "Safar sizning sanalaringiz, budjetingiz, mehmonxona darajasi va tanlagan xizmatlaringiz asosida tuziladi. 30–50 nafar notanish kishilik majburiy guruh yo‘q — kim bilan borishni o‘zingiz tanlaysiz."),
                HomeFAQItem(id: "family", question: "Faqat oilam yoki do‘stlarim bilan bora olamanmi?", answer: "Ha. Paketni bir kishi, juftlik, oila yoki do‘stlar uchun tuzish mumkin. Safarda faqat o‘zingiz qo‘shgan insonlar bo‘ladi."),
                HomeFAQItem(id: "care", question: "Hammasini o‘zim tuzishni istamasam-chi?", answer: "iumrah Care’ga murojaat qiling. Biz variant tanlash, tafsilotlarni tekshirish va safarni rasmiylashtirishga yordam beramiz — majburiy katta guruhsiz.")
            ]
        case .uzbekCyrillic:
            return [
                HomeFAQItem(id: "what", question: "iumrah нима?", answer: "iumrah — мустақил ва шахсий Умра учун платформа. У парвоз, меҳмонхона, трансфер ва хизматларни битта тушунарли пакетга бирлаштиради ва сафарни битта иловада бошқаришга ёрдам беради."),
                HomeFAQItem(id: "why", question: "iumrah нима учун яратилди?", answer: "Зиёратчи катта тур гуруҳига боғланиб қолмаслиги ва кўплаб алоҳида бронларни бошқармаслиги учун. iumrah сафар давомида кўпроқ назорат, шаффофлик ва ғамхўрлик бериш учун яратилган."),
                HomeFAQItem(id: "personal", question: "«Шахсий Умра» нимани англатади?", answer: "Сафар сизнинг саналарингиз, бюджетингиз, меҳмонхона даражаси ва танлаган хизматларингиз асосида тузилади. 30–50 нафар нотаниш кишилик мажбурий гуруҳ йўқ — ким билан боришни ўзингиз танлайсиз."),
                HomeFAQItem(id: "family", question: "Фақат оилам ёки дўстларим билан бора оламанми?", answer: "Ҳа. Пакетни бир киши, жуфтлик, оила ёки дўстлар учун тузиш мумкин. Сафарда фақат ўзингиз қўшган инсонлар бўлади."),
                HomeFAQItem(id: "care", question: "Ҳаммасини ўзим тузишни истамасам-чи?", answer: "iumrah Care’га мурожаат қилинг. Биз вариант танлаш, тафсилотларни текшириш ва сафарни расмийлаштиришга ёрдам берамиз — мажбурий катта гуруҳсиз.")
            ]
        }
    }

    private func money(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(Int(amount.rounded()))"
    }
}

private struct HomeFAQItem: Identifiable {
    let id: String
    let question: String
    let answer: String
}

private struct IumrahHomeFlatCardModifier: ViewModifier {
    let padding: CGFloat
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color.iumrahCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.7)
            }
    }
}

private extension View {
    func iumrahHomeFlatCard(padding: CGFloat = 18, radius: CGFloat = IumrahDesign.cardRadius) -> some View {
        modifier(IumrahHomeFlatCardModifier(padding: padding, radius: radius))
    }
}


// MARK: - Violet Signature · home-to-flight-first journey search
/// This search is only a handoff to the live flights catalogue in Hotels.
/// Nothing is priced, booked or marked available by this view.
private struct IumrahHomeJourneySearchHero: View {
    enum Presentation: Equatable { case header, search }
    let onSearch: () -> Void
    var presentation: Presentation = .search
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared
    @Binding var searchExpanded: Bool
    @State private var showingCalendar = false
    @State private var showingPassengers = false

    init(onSearch: @escaping () -> Void, presentation: Presentation = .search, searchExpanded: Binding<Bool>) {
        self.onSearch = onSearch
        self.presentation = presentation
        _searchExpanded = searchExpanded
    }

    private func tr(_ ru: String, _ en: String, _ uz: String, _ uzCyrl: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCyrl
        default: return en
        }
    }

    private var isValidSearch: Bool {
        journey.trip.canContinue &&
        journey.trip.departureDate >= Calendar.current.startOfDay(for: Date()) &&
        journey.trip.infants <= journey.trip.adults
    }

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .header {
                blackTop
            } else {
                searchCard
                    .padding(.horizontal, IumrahDesign.pagePadding)
                    .padding(.top, -40)
                    .padding(.bottom, 2)
                    .task(id: scenePhase == .active && !reduceMotion) {
                        guard scenePhase == .active && !reduceMotion else { return }
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(5))
                            guard !Task.isCancelled else { break }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                headlineIndex = (headlineIndex + 1) % headlineOptions.count
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingCalendar) {
            FlightDateCalendarView(
                trip: journey.trip,
                initialDeparture: journey.trip.departureDate,
                initialReturn: journey.trip.returnDate,
                publishedOnly: true,
                flexibilityDays: $journey.flightSearchFlexDays
            ) { selection in
                journey.resetAfterTripChange()
                journey.clearStagedUmrahFlights()
                journey.trip.departureDate = selection.departure
                journey.trip.returnDate = selection.returnDate
                journey.trip.flightTripType = .roundTrip
                journey.trip.flexibility = .exact
                // The calendar recommends dates, not tickets. The flight pair
                // must still be chosen explicitly in the next stage.
                journey.packageFlightPath = .publishedDirect
            }
            .environmentObject(settings)
            .modifier(IumrahJourneySheetStyle())
        }
        .sheet(isPresented: $showingPassengers) {
            IumrahHomeJourneyPassengersSheet(language: settings.language,
                                              initialAdults: journey.trip.adults,
                                              initialChildren: journey.trip.children,
                                              initialInfants: journey.trip.infants,
                                              initialCabin: journey.trip.effectiveFlightFilters.cabinClass) { adults, children, infants, cabin in
                guard (adults, children, infants, cabin) != (journey.trip.adults, journey.trip.children,
                                                           journey.trip.infants, journey.trip.effectiveFlightFilters.cabinClass) else { return }
                journey.resetAfterTripChange()
                journey.clearStagedUmrahFlights()
                journey.trip.adults = adults
                journey.trip.children = children
                journey.trip.infants = infants
                var filters = journey.trip.effectiveFlightFilters
                filters.cabinClass = cabin
                journey.trip.flightFilters = filters
            }
            .modifier(IumrahJourneySheetStyle())
        }
    }

    // Main-page-only identity: the existing monochrome world atlas and the
    // existing light wordmark, without changing other tabs or global tokens.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var headlineIndex = 0

    private var headlineOptions: [String] {
        [
            tr("Ваша умра. Ваш путь.", "Your Umrah. Your way.", "Umrangiz. O‘z yo‘lingiz.", "Умрангиз. Ўз йўлингиз."),
            tr("Вместе с близкими.", "Together with those you love.", "Yaqinlaringiz bilan birga.", "Яқинларингиз билан бирга."),
            tr("Всё путешествие — в одном месте.", "Your entire journey. One place.", "Butun safar bir joyda.", "Бутун сафар бир жойда.")
        ]
    }

    private var blackTop: some View {
        IumrahPrimaryHeaderBrandRow()
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, IumrahSignatureHeaderGeometry.topInset)
            .padding(.bottom, IumrahSignatureHeaderGeometry.lowerInset)
            .frame(maxWidth: .infinity)
            .background {
                IumrahWorldDotsHeaderBackground(mapOpacity: 0.33)
                    .clipShape(UnevenRoundedRectangle(
                        bottomLeadingRadius: IumrahSignatureHeaderGeometry.bottomRadius,
                        bottomTrailingRadius: IumrahSignatureHeaderGeometry.bottomRadius))
            }
    }

    private var searchCard: some View {
        IumrahGraphiteSearchSurface(isExpanded: $searchExpanded,
            summary: headlineOptions[headlineIndex],
            subtitle: "\(journey.trip.originCode) · \(journey.trip.departureDate.formatted(date: .abbreviated, time: .omitted))") {
            searchFields
        }
    }

    private var searchFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                AirportSelectorButton(airport: $journey.trip.originAirport,
                                      fallbackCode: $journey.trip.origin,
                                      cornerRadius: 0,
                                      monochrome: true)
                    .frame(minHeight: 46)
            }

            Divider()
            VStack(alignment: .leading, spacing: 7) {
                IumrahGlassPillSelector(options: [
                    .init(.makkahOnly, tr("Только Мекка", "Makkah only", "Faqat Makka", "Фақат Макка")),
                    .init(.makkahAndMadinah, tr("Мекка + Медина", "Makkah + Madinah", "Makka + Madina", "Макка + Мадина"))
                ], selection: journey.trip.scope, onSelect: changeRoute, height: 44)
                fieldCaption(tr("Маршрут умры", "Your Umrah route", "Umra yo‘nalishi", "Умра йўналиши"))
            }

            if journey.trip.scope == .makkahAndMadinah {
                IumrahGlassPillSelector(options: [
                    .init(SaudiArrivalAirport.jeddah, tr("Джидда", "Jeddah", "Jidda", "Жидда")),
                    .init(SaudiArrivalAirport.madinah, tr("Медина", "Madinah", "Madina", "Мадина"))
                ], selection: journey.trip.arrivalAirport, onSelect: { airport in
                    guard journey.trip.arrivalAirport != airport else { return }
                    journey.resetAfterTripChange()
                    journey.clearStagedUmrahFlights()
                    journey.trip.arrivalAirport = airport
                    journey.trip.selectedReturnAirport = nil
                })
                fieldCaption(tr("Первый аэропорт прилёта", "First arrival airport", "Birinchi kelish aeroporti", "Биринчи келиш аэропорти"))
            }
            Divider()
            Button { showingCalendar = true } label: {
                HStack(spacing: 8) {
                    dateColumn(title: tr("Вылет", "Departure", "Uchish", "Учиш"), date: journey.trip.departureDate)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(Color.iumrahMuted)
                    dateColumn(title: tr("Обратно", "Return", "Qaytish", "Қайтиш"), date: journey.trip.returnDate)
                    Spacer(minLength: 0)
                    Image(systemName: "calendar")
                        .foregroundStyle(Color.iumrahInk)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: 52)

            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Выбрать даты поездки", "Choose travel dates", "Safar sanalarini tanlash", "Сафар саналарини танлаш"))

            Divider()
            Button { showingPassengers = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .foregroundStyle(Color.iumrahInk)
                    VStack(alignment: .leading, spacing: 3) {
                        fieldCaption(tr("Паломники", "Travelers", "Ziyoratchilar", "Зиёратчилар"))
                        Text(passengerSummary + " · " + cabinTitle(journey.trip.effectiveFlightFilters.cabinClass))
                            .font(IumrahType.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(Color.iumrahInk)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.iumrahMuted)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(minHeight: 52)

            }
            .buttonStyle(.plain)

            Button(action: { searchExpanded = false; findFlights() }) {
                HStack(spacing: 10) {
                    Text(tr("Найти авиабилеты", "Find flights", "Reyslarni topish", "Рейсларни топиш"))
                }
                .font(IumrahType.bold(16, relativeTo: .headline))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: IumrahDesign.controlHeight)
                .background(Color.iumrahSignatureBlack,
                            in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!isValidSearch)
            .opacity(isValidSearch ? 1 : 0.5)


        }
        .padding(18)

    }

    private func cabinTitle(_ cabin: FlightCabinClass) -> String {
        switch cabin {
        case .economy: return tr("Эконом", "Economy", "Ekonom", "Эконом")
        case .premiumEconomy: return tr("Премиум-эконом", "Premium economy", "Premium ekonom", "Премиум эконом")
        case .business: return tr("Бизнес", "Business", "Biznes", "Бизнес")
        case .first: return tr("Первый", "First", "Birinchi klass", "Биринчи класс")
        }
    }

    private func changeRoute(_ scope: JourneyScope) {
        guard journey.trip.scope != scope else { return }
        journey.resetAfterTripChange()
        journey.clearStagedUmrahFlights()
        journey.trip.scope = scope
        if scope == .makkahOnly {
            journey.trip.arrivalAirport = .jeddah
            journey.trip.selectedReturnAirport = .jeddah
        } else {
            journey.trip.selectedReturnAirport = nil
        }
    }

    private func dateColumn(title: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldCaption(title)
            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                .font(IumrahType.bold(16, relativeTo: .headline))
                .foregroundStyle(Color.iumrahInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fieldCaption(_ text: String) -> some View {
        Text(text)
            .font(IumrahType.regular(12, relativeTo: .caption))
            .foregroundStyle(Color.iumrahMuted)
    }

    private var passengerSummary: String {
        tr("\(journey.trip.travelerCount) чел.", "\(journey.trip.travelerCount) travelers",
           "\(journey.trip.travelerCount) kishi", "\(journey.trip.travelerCount) киши")
    }

    private func findFlights() {
        guard isValidSearch else { IumrahHaptics.error(); return }
        // A new search invalidates the previous booking draft and staged fares.
        // We preserve the route, dates, party and hotel scope the traveler chose.
        journey.resetAfterTripChange()
        journey.clearStagedUmrahFlights()
        journey.trip.flightTripType = .roundTrip
        journey.trip.flexibility = .exact
        journey.packageFlightPath = .publishedDirect
        onSearch()
    }
}

/// A restrained, native SwiftUI dissolve: opacity, a small vertical drift,
/// and animated blur. Disabled when Reduce Motion is enabled.
private struct IumrahHomeVaporPhase: AnimatableModifier {
    var amount: CGFloat
    var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(Double(max(0, 1 - amount)))
            .blur(radius: max(0, amount) * 10)
            .offset(y: -amount * 9)
    }
}

private struct IumrahHomeJourneyPassengersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppSettingsStore.Language
    let onSave: (Int, Int, Int, FlightCabinClass) -> Void
    @State private var adults: Int
    @State private var children: Int
    @State private var infants: Int
    @State private var cabin: FlightCabinClass

    init(language: AppSettingsStore.Language, initialAdults: Int, initialChildren: Int,
         initialInfants: Int, initialCabin: FlightCabinClass,
         onSave: @escaping (Int, Int, Int, FlightCabinClass) -> Void) {
        self.language = language
        self.onSave = onSave
        _adults = State(initialValue: initialAdults)
        _children = State(initialValue: initialChildren)
        _infants = State(initialValue: initialInfants)
        _cabin = State(initialValue: initialCabin)
    }

    private func tr(_ ru: String, _ en: String, _ uz: String, _ uzCyrl: String) -> String {
        switch language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCyrl
        default: return en
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 15) {
                    IumrahPageHelpCard("home.passengers")
                    passengerRow(
                    title: tr("Взрослые", "Adults", "Kattalar", "Катталар"),
                    subtitle: tr("12 лет и старше", "Ages 12+", "12 yosh va yuqori", "12 ёшдан катта"),
                    value: adults, canDecrease: adults > max(1, infants), canIncrease: total < 9,
                    decrease: { adults -= 1 }, increase: { adults += 1 }
                )
                passengerRow(
                    title: tr("Дети", "Children", "Bolalar", "Болалар"),
                    subtitle: tr("2–11 лет", "Ages 2–11", "2–11 yosh", "2–11 ёш"),
                    value: children, canDecrease: children > 0, canIncrease: total < 9,
                    decrease: { children -= 1 }, increase: { children += 1 }
                )
                passengerRow(
                    title: tr("Младенцы", "Infants", "Chaqaloqlar", "Чақалоқлар"),
                    subtitle: tr("До 2 лет, не более одного на взрослого", "Under 2, at most one per adult",
                                 "2 yoshgacha, har kattaga bir nafar", "2 ёшгача, ҳар каттага бир нафар"),
                    value: infants, canDecrease: infants > 0, canIncrease: total < 9 && infants < adults,
                    decrease: { infants -= 1 }, increase: { infants += 1 }
                )
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("Класс перелёта", "Cabin class", "Parvoz klassi", "Парвоз класси"))
                        .font(IumrahType.bold(16, relativeTo: .headline))
                    Picker(tr("Класс перелёта", "Cabin class", "Parvoz klassi", "Парвоз класси"), selection: $cabin) {
                        Text(tr("Эконом", "Economy", "Ekonom", "Эконом")).tag(FlightCabinClass.economy)
                        Text(tr("Премиум", "Premium", "Premium", "Премиум")).tag(FlightCabinClass.premiumEconomy)
                        Text(tr("Бизнес", "Business", "Biznes", "Бизнес")).tag(FlightCabinClass.business)
                        Text(tr("Первый", "First", "Birinchi", "Биринчи")).tag(FlightCabinClass.first)
                    }
                    .pickerStyle(.segmented)
                    .frame(minHeight: 44)
                }
                .padding(16)
                .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
                Text(tr("Максимум 9 путешественников в одной заявке.",
                        "Maximum 9 travelers per search.",
                        "Bir qidiruvda ko‘pi bilan 9 nafar yo‘lovchi.",
                        "Бир қидирувда кўпи билан 9 нафар йўловчи."))
                    .font(IumrahType.secondary)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.iumrahPageBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    onSave(adults, children, infants, cabin)
                    dismiss()
                } label: {
                    Text(tr("Готово", "Done", "Tayyor", "Тайёр"))
                        .frame(maxWidth: .infinity)
                        .frame(height: IumrahDesign.controlHeight)
                }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.iumrahPageBackground)
            }
            .navigationTitle(tr("Паломники", "Travelers", "Ziyoratchilar", "Зиёратчилар"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("Закрыть", "Close", "Yopish", "Ёпиш")) { dismiss() } } }
        }
        .presentationDetents([.large])
    }

    private var total: Int { adults + children + infants }

    private func passengerRow(title: String, subtitle: String, value: Int,
                              canDecrease: Bool, canIncrease: Bool,
                              decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(IumrahType.bold(16, relativeTo: .headline))
                Text(subtitle).font(IumrahType.regular(12, relativeTo: .caption))
                    .foregroundStyle(Color.iumrahMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button(action: decrease) {
                Image(systemName: "minus")
                    .frame(width: 46, height: 46)
                    .background(Color.iumrahRaisedBackground, in: Circle())
            }
            .disabled(!canDecrease)
            .accessibilityLabel(tr("Уменьшить", "Decrease", "Kamaytirish", "Камайтириш") + " " + title)
            Text(String(value))
                .font(IumrahType.bold(17, relativeTo: .headline))
                .monospacedDigit()
                .frame(width: 30)
            Button(action: increase) {
                Image(systemName: "plus")
                    .frame(width: 46, height: 46)
                    .background(Color.iumrahRaisedBackground, in: Circle())
            }
            .disabled(!canIncrease)
            .accessibilityLabel(tr("Увеличить", "Increase", "Ko‘paytirish", "Кўпайтириш") + " " + title)
        }
        .buttonStyle(.plain)
        .padding(15)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
