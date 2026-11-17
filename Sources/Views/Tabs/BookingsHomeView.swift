import Foundation
import SwiftUI
import UIKit

struct BookingsHomeView: View {
    private enum BookingPanel: String, CaseIterable, Identifiable {
        case booking
        case status
        case package
        case schedule
        var id: String { rawValue }
    }

    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @Environment(\.iumrahTabIsActive) private var activeTab
    @Environment(\.scenePhase) private var scenePhase

    @State private var pendingDeleteID: String?
    @State private var deleteError: String?
    @State private var cancellationSent = false
    @State private var showZiyarats = false
    @State private var showCareRequestBuilder = false
    @State private var bookingPanel: BookingPanel = .booking
    @State private var selectedBookingID: String?
    @State private var activeGuideProfile: IumrahPublicProfile?
    @State private var travelScheduleError = false
    @State private var travelScheduleLoaded = false
    @State private var rating = 0
    @State private var feedbackComment = ""
    @State private var feedbackSending = false
    @State private var feedbackError = false
    @State private var feedbackSaved: IumrahTravelFeedback?
    @State private var feedbackSavedBookingID: String?
    @State private var showRecovery = false
    @State private var showAdvisor = false
    @State private var certificateShare: TravelCertificateFile?
    @State private var certificateShareError = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var completionAppeared = false

    private let chatService = ChatService()

    private var activeSessions: [StoredBookingSession] {
        bookings.sessions.filter { session in
            !["COMPLETED", "CANCELLED"].contains(session.effectiveStatus.uppercased())
        }
    }

    private var pastSessions: [StoredBookingSession] {
        bookings.sessions.filter { session in
            ["COMPLETED", "CANCELLED"].contains(session.effectiveStatus.uppercased())
        }
    }

    private var activeSession: StoredBookingSession? {
        bookings.sessions.first(where: { $0.id == selectedBookingID }) ?? activeSessions.first
    }

    private var bookingTabContent: some View {
        VStack(spacing: 12) {
            if let activeSession { AnyView(activeBookingHub(activeSession)) }
            if !pastSessions.isEmpty { archiveList.padding(.horizontal, IumrahDesign.pagePadding).padding(.bottom, 28) }
            if activeSession == nil { AnyView(emptyBookingHome) }
            Button { showRecovery = true } label: {
                Label(localized("Восстановить бронирование", "Recover booking", "Bronni tiklash", "Бронни тиклаш"), systemImage: "lock.shield")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(14)
                    .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).padding(.horizontal, IumrahDesign.pagePadding).padding(.bottom, 20)
        }
    }
    private var bookingScrollRoot: AnyView {
        AnyView(IumrahRootScrollingPage(onRefresh: { await refreshBookings() }, helpContext: activeSession == nil ? "bookings.empty" : bookingPanel == .booking ? "bookings.active" : bookingPanel == .status ? "bookings.status" : bookingPanel == .package ? "bookings.active" : "bookings.schedule", fixedRefreshHeader: true, header: {
            AnyView(bookingHeader(hasActiveBooking: activeSession != nil))
        }, content: { AnyView(bookingTabContent) })
        .modifier(IumrahPrimaryTabScrollChrome()))
    }
    var body: some View {
        bookingScrollRoot
        .task(id: activeTab && scenePhase == .active) {
            guard activeTab, scenePhase == .active else { return }
            await bookings.refreshAll()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                guard !Task.isCancelled else { break }
                await bookings.refreshAll()
            }
        }
        .task(id: activeTab && scenePhase == .active ? activeSession.map { "\($0.id):\($0.effectiveStatus)" } : nil) {
            guard let id = activeSession?.id, activeTab, scenePhase == .active else { return }
            while !Task.isCancelled {
                _ = try? await bookings.loadCheckout(id: id, token: account.bearerToken, force: true)
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .task(id: activeTab && scenePhase == .active ? activeSession.map { "\($0.id):\($0.effectiveStatus)" } : nil) {
            travelScheduleError = false; travelScheduleLoaded = false
            rating = 0; feedbackComment = ""; feedbackSaved = nil; feedbackError = false; certificateShareError = false; completionAppeared = false
            guard let session = activeSession, activeTab, scenePhase == .active, ["IN_TRIP", "READY_TO_TRAVEL", "DOCUMENTS_READY"].contains(session.effectiveStatus.uppercased()) else { return }
            while !Task.isCancelled {
                do { _ = try await bookings.loadItinerary(for: session.id, language: settings.language); if !Task.isCancelled { travelScheduleLoaded = true; travelScheduleError = false } }
                catch { if !Task.isCancelled { travelScheduleError = true } }
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .sheet(isPresented: $showRecovery) {
            BookingRecoverySheet(language: settings.language) { session in
                selectedBookingID = session.id; bookingPanel = .status
                Task { await bookings.refreshAll() }
            }.environmentObject(bookings)
        }
        .sheet(item: $certificateShare, onDismiss: {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iumrah-certificates", isDirectory: true)
            try? FileManager.default.removeItem(at: directory)
        }) { file in
            IumrahFileShareSheet(url: file.url)
        }
        .fullScreenCover(isPresented: $showAdvisor) {
            UmrahFlowRootView(guideLanguage: settings.language == .russian ? .russian : ([AppSettingsStore.Language.uzbek, .uzbekCyrillic].contains(settings.language) ? .uzbek : .english))
        }
        .task(id: activeSession?.guide?.id) {
            await loadActiveGuideProfile()
        }
        .confirmationDialog(
            localized("Запросить отмену?", "Request cancellation?", "Bekor qilishni so‘rash?", "Бекор қилишни сўраш?"),
            isPresented: Binding(
                get: { pendingDeleteID != nil },
                set: { if !$0 { pendingDeleteID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(localized("Отправить запрос", "Send request", "So‘rov yuborish", "Сўров юбориш"), role: .destructive) {
                guard let id = pendingDeleteID else { return }
                pendingDeleteID = nil
                Task { await deleteBooking(id) }
            }
            Button(L10n.text("cancel", settings.language), role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text(localized("Менеджер рассмотрит запрос. Бронирование и документы сохранятся.", "A manager will review your request. Your booking and documents will remain available.", "Menejer so‘rovni ko‘rib chiqadi. Bron va hujjatlar saqlanadi.", "Менежер сўровни кўриб чиқади. Брон ва ҳужжатлар сақланади."))
        }
        .alert(localized("Запрос отправлен", "Request sent", "So‘rov yuborildi", "Сўров юборилди"), isPresented: $cancellationSent) {
            Button("OK", role: .cancel) {}
        } message: { Text(localized("Менеджер рассмотрит отмену.", "Your manager will review the cancellation.", "Menejer bekor qilishni ko‘rib chiqadi.", "Менежер бекор қилишни кўриб чиқади.")) }
        .navigationDestination(isPresented: $chrome.shouldStartTripBuilder) {
            TripBuilderView()
        }
        .navigationDestination(isPresented: $chrome.shouldStartFlightFirstBuilder) {
            FlightFirstPackageFlowView()
        }
        .onAppear { openRequestedPackage() }
        .onChange(of: chrome.requestedBookingID) { _, _ in openRequestedPackage() }
        .onChange(of: bookings.sessions) { _, _ in
            if activeSession == nil { bookingPanel = .booking; selectedBookingID = nil }
            openRequestedPackage()
        }
        .navigationDestination(isPresented: $showZiyarats) {
            ZiyaratJourneyView()
                .environmentObject(settings)
                .environmentObject(chrome)
        }
        .navigationDestination(isPresented: $showCareRequestBuilder) {
            IumrahCareRequestView()
        }
    }

    private func openRequestedPackage() {
        guard chrome.currentTab == .booking, let id = chrome.requestedBookingID,
              bookings.booking(id: id) != nil else { return }
        selectedBookingID = id
        bookingPanel = chrome.requestedBookingSchedule ? .schedule : (chrome.requestedBookingStatus ? .status : (chrome.requestedBookingOverview ? .booking : .package))
        chrome.requestedBookingStatus = false
        chrome.requestedBookingSchedule = false
        chrome.requestedBookingOverview = false
        chrome.requestedBookingID = nil
    }

    @MainActor private func refreshBookings() async {
        let owner = account.bearerToken
        let id = activeSession?.id
        let panel = bookingPanel
        await bookings.refreshAll()
        guard !Task.isCancelled, owner == account.bearerToken, let id, bookings.booking(id: id) != nil else { return }
        switch panel {
        case .status:
            _ = try? await bookings.loadCheckout(id: id, token: owner, force: true)
            if let owner { _ = try? await bookings.loadCheckoutFriends(id: id, token: owner, force: true) }
        case .schedule:
            _ = try? await bookings.loadItinerary(for: id, language: settings.language)
        case .booking:
            _ = try? await bookings.loadCheckout(id: id, token: owner, force: true)
            if ["IN_TRIP", "READY_TO_TRAVEL", "DOCUMENTS_READY"].contains(bookings.booking(id: id)?.effectiveStatus.uppercased() ?? "") { _ = try? await bookings.loadItinerary(for: id, language: settings.language) }
        case .package: break
        }
    }

    // MARK: - Active booking

    private func bookingPanelContent(_ session: StoredBookingSession) -> AnyView {
        switch bookingPanel {
        case .booking:
            let status = session.effectiveStatus.uppercased()
            if status == "COMPLETED" || status == "CANCELLED" { return AnyView(completedTrip(session).padding(.bottom, 28)) }
            if ["IN_TRIP", "READY_TO_TRAVEL", "DOCUMENTS_READY"].contains(status) { return AnyView(travelCompanion(session).padding(.bottom, 38)) }
            return AnyView(VStack(spacing: 20) { nextBookingAction(session); bookingProgress(session); tripManagement(session) }.padding(.bottom, 38))
        case .status: return AnyView(bookingStatusPanel(session))
        case .package: return AnyView(BookingDetailView(bookingID: session.id, embedded: true).id(session.id))
        case .schedule: return AnyView(BookingItineraryCalendarView(bookingID: session.id,
            startDate: session.booking.input.startDate, endDate: session.booking.input.endDate,
            booking: session.booking, presentation: .fullScreen).padding(.bottom, 28))
        }
    }
    private func nextBookingAction(_ session: StoredBookingSession) -> some View {
        let status = session.effectiveStatus.uppercased()
        let title: String
        let body: String
        let icon: String
        if bookings.cachedCheckout(id: session.id, token: account.bearerToken)?.cancellationRequestedAt != nil && status != "CANCELLED" {
            title = localized("Запрос отмены отправлен", "Cancellation requested", "Bekor qilish so‘rovi yuborildi", "Бекор қилиш сўрови юборилди")
            body = localized("Менеджер свяжется с вами. Бронирование пока активно.", "Your manager will contact you. The booking remains active.", "Menejer siz bilan bog‘lanadi. Bron hozircha faol.", "Менежер сиз билан боғланади. Брон ҳозирча фаол."); icon = "clock"
        } else { switch status {
        case "AVAILABILITY_CHECK":
            title = localized("Данные паломников", "Pilgrim details", "Ziyoratchilar ma’lumotlari", "Зиёратчилар маълумотлари")
            body = localized("Заполните анкеты, пока мы проверяем наличие.", "Complete the forms while we check availability.", "Mavjudlik tekshirilayotganda anketalarni to‘ldiring.", "Мавжудлик текширилаётганда анкеталарни тўлдиринг."); icon = "person.text.rectangle"
        case "PAYMENT_PENDING":
            let checkout = bookings.cachedCheckout(id: session.id, token: account.bearerToken)
            if checkout?.paymentReview?.satisfied == true || session.operationPaymentStatus == "paid" {
                title = localized("Оплата подтверждена", "Payment verified", "To‘lov tasdiqlandi", "Тўлов тасдиқланди")
                body = localized("Проверьте данные паломников и статус бронирования.", "Review pilgrim details and booking status.", "Ziyoratchi ma’lumotlari va bron holatini tekshiring.", "Зиёратчи маълумотлари ва брон ҳолатини текширинг.")
            } else if checkout?.receipts.contains(where: { $0.reviewStatus == "submitted" }) == true || session.operationPaymentStatus == "receipt_submitted" {
                title = localized("Чек на проверке", "Receipt under review", "Chek tekshiruvda", "Чек текширувда")
                body = localized("Ожидайте подтверждения поступления средств.", "Wait for payment verification.", "To‘lov tasdig‘ini kuting.", "Тўлов тасдиғини кутинг.")
            } else {
                title = localized("Данные и оплата", "Details and payment", "Ma’lumotlar va to‘lov", "Маълумотлар ва тўлов")
                body = localized("Проверьте анкеты, реквизиты и остаток к оплате.", "Review forms, payment details and remaining balance.", "Anketalar, rekvizitlar va to‘lov qoldig‘ini tekshiring.", "Анкеталар, реквизитлар ва тўлов қолдиғини текширинг.")
            }
            icon = "creditcard"
        default:
            title = localized("Документы поездки", "Travel documents", "Safar hujjatlari", "Сафар ҳужжатлари")
            body = localized("Готовые файлы, прогресс и сохранение офлайн.", "Published files, progress and offline saving.", "Tayyor fayllar, holat va oflayn saqlash.", "Тайёр файллар, ҳолат ва офлайн сақлаш."); icon = "doc.on.doc"
        }
        }
        return Button { withAnimation(.snappy(duration: 0.24)) { bookingPanel = .status } } label: {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.title2).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(body).font(.caption).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.bold())
            }.foregroundStyle(.white).padding(16).background(Color.black, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain)
    }

    private func bookingStatusPanel(_ session: StoredBookingSession) -> some View {
        VStack(spacing: 18) {
            PilgrimCheckoutView(bookingID: session.id, presentation: .bookingStatus).id(session.id)
        }
        .padding(.bottom, 24)
    }

    private func activeBookingHub(_ session: StoredBookingSession) -> some View {
        VStack(spacing: 0) {
            LazyVStack(spacing: 0) {
                if bookingPanel == .booking { bookingIdentity(session).padding(.bottom, 18) }

                bookingPanelContent(session)

                if activeSessions.count > 1 {
                    otherTrips(excluding: session.id)
                        .padding(.bottom, 12)
                }

                if let deleteError {
                    Text(deleteError)
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: .systemRed))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color(uiColor: .systemRed).opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 8)
                }


            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 44)
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
        .animation(.snappy(duration: 0.34), value: session.effectiveStatus)
    }

    /// The top deliberately avoids another large card. Like the reference flow,
    /// hierarchy comes from whitespace and typography before the process begins.
    private func bookingIdentity(_ session: StoredBookingSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(activeEyebrow).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(session.booking.route.originCode) → \(session.booking.route.outboundDestination)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .tracking(-0.9).lineLimit(1).minimumScaleFactor(0.72)
                Text("\(L10n.date(session.booking.input.startDate, settings.language)) – \(L10n.date(session.booking.input.endDate, settings.language))")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Label(pilgrimCountText(session.booking.input.travelers.totalPeople), systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                BookingIdentityCopyRow(title: localized("Номер брони", "Booking number", "Bron raqami", "Брон рақами"),
                    value: session.displayBookingNumber == "#----" ? "—" : session.displayBookingNumber, canCopy: session.displayBookingNumber != "#----")
                if let id = session.displayPilgrimID {
                    BookingIdentityCopyRow(title: localized("ID паломника", "Pilgrim ID", "Ziyoratchi ID", "Зиёратчи ID"), value: id, canCopy: true)
                } else {
                    BookingIdentityCopyRow(title: localized("ID паломника", "Pilgrim ID", "Ziyoratchi ID", "Зиёратчи ID"), value: "—", canCopy: false)
                }
                if let name = session.travelerName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                    BookingIdentityCopyRow(title: localized("Имя и фамилия", "Full name", "Ism va familiya", "Исм ва фамилия"), value: name, canCopy: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.iumrahRaisedBackground)
                    .frame(width: 94, height: 94)
                    .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.7) }
                Image(systemName: "suitcase.fill").font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
            }.accessibilityHidden(true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func identityPill(_ text: String, systemName: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemName {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .frame(height: 31)
        .background(Color.iumrahRaisedBackground, in: Capsule())
    }

    private func bookingHeader(hasActiveBooking: Bool) -> some View {
        IumrahPrimaryTabHeader(
            title: localized("Бронирование", "Bookings", "Bronlar", "Бронлар"),
            footer: hasActiveBooking ? AnyView(
                IumrahHeaderPills(
                    labels: [
                        localized("Статус брони", "Booking status", "Bron holati", "Брон ҳолати"),
                        localized("Документы", "Documents", "Hujjatlar", "Ҳужжатлар"),
                        localized("Пакет Умры", "Umrah package", "Umra paketi", "Умра пакети"),
                        localized("Расписание", "Schedule", "Jadval", "Жадвал")
                    ],
                    symbols: ["suitcase", "doc.text", "shippingbox", "calendar"],
                    selection: bookingPanel == .booking ? 0 : (bookingPanel == .status ? 1 : (bookingPanel == .package ? 2 : 3)),
                    onSelect: { index in
                        bookingPanel = index == 0 ? .booking : (index == 1 ? .status : (index == 2 ? .package : .schedule))
                    }
                )
            ) : nil
        )
    }

    @ViewBuilder
    private func bookingTimerOverview(_ session: StoredBookingSession) -> some View {
        if lifecyclePhase(for: session) != nil {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(IumrahBookingStatusVisual.color(for: session.effectiveStatus).opacity(0.12))
                            .frame(width: 48, height: 48)
                        if ["AVAILABILITY_CHECK", "PAYMENT_PENDING", "BOOKING_CONFIRMED"].contains(session.effectiveStatus.uppercased()) {
                            ProgressView()
                                .tint(IumrahBookingStatusVisual.color(for: session.effectiveStatus))
                        } else {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(IumrahBookingStatusVisual.color(for: session.effectiveStatus))
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized("Работа идёт", "Work is in progress", "Jarayon davom etmoqda", "Жараён давом этмоқда"))
                            .font(.headline)
                        Text(localized("Вы можете закрыть приложение — статус обновится автоматически.", "You can close the app — the status will update automatically.", "Ilovani yopishingiz mumkin — holat avtomatik yangilanadi.", "Иловани ёпишингиз мумкин — ҳолат автоматик янгиланади."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                lifecycleTimerPanel(session, tint: IumrahBookingStatusVisual.color(for: session.effectiveStatus))
            }
            .padding(18)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7) }
        }
    }

    private func bookingFulfillmentCenter(_ session: StoredBookingSession, checkout: IumrahCheckoutResponse?) -> some View {
        let passportCount = checkout?.travelers.filter(\.hasPassport).count ?? 0
        let total = checkout?.travelers.count ?? session.booking.input.travelers.totalPeople
        let passportsReady = total > 0 && passportCount == total

        return VStack(alignment: .leading, spacing: 15) {
            sectionHeader(title: localized("Что нужно сделать", "What to do next", "Keyingi qadamlar", "Кейинги қадамлар"), trailing: nil)
            Text(localized(
                "Каждый этап открывается тогда, когда он нужен. Сейчас достаточно прикрепить паспорта — без KYC и длинных анкет.",
                "Each stage opens when it is needed. For now, attaching the passports is enough — no KYC or long forms.",
                "Har bir bosqich kerak bo‘lganda ochiladi. Hozir pasportlarni biriktirishning o‘zi yetarli — KYC va uzun anketalarsiz.",
                "Ҳар бир босқич керак бўлганда очилади. Ҳозир паспортларни бириктиришнинг ўзи етарли — KYC ва узун анкеталарсиз."
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            NavigationLink {
                IumrahBookingPassportsView(bookingID: session.id)
            } label: {
                bookingActionCard(
                    icon: "person.text.rectangle.fill",
                    role: .document,
                    title: localized("Прикрепить паспорт", "Attach passports", "Pasportlarni biriktirish", "Паспортларни бириктириш"),
                    body: passportsReady
                        ? localized("Паспорта всех паломников прикреплены. Можно переходить к следующему этапу.", "Every pilgrim passport is attached. You are ready for the next stage.", "Barcha ziyoratchilar pasporti biriktirilgan. Keyingi bosqichga tayyor.", "Барча зиёратчилар паспорти бириктирилган. Кейинги босқичга тайёр.")
                        : localized("Прикреплено: \(passportCount) из \(total). Для каждого паломника нужна чёткая фотография страницы с данными.", "Attached: \(passportCount) of \(total). Each pilgrim needs a clear photo of the passport information page.", "Biriktirilgan: \(passportCount)/\(total). Har bir ziyoratchi uchun pasport ma’lumotlar sahifasining aniq rasmi kerak.", "Бириктирилган: \(passportCount)/\(total). Ҳар бир зиёратчи учун паспорт маълумотлар саҳифасининг аниқ расми керак."),
                    action: passportsReady
                        ? localized("Проверить паспорта", "Review passports", "Pasportlarni tekshirish", "Паспортларни текшириш")
                        : localized("Прикрепить паспорта", "Attach passports", "Pasportlarni biriktirish", "Паспортларни бириктириш"),
                    ready: passportsReady
                )
            }
            .buttonStyle(.plain)

            paymentReceiptStatusCard(session, checkout: checkout)
            documentReadinessCard(session, checkout: checkout)
            if let guide = session.guide {
                assignedGuideCard(session, guide: guide)
            }
            guideTransferStatusCard(session, checkout: checkout)

            NavigationLink {
                IumrahPolicyDetailView(kind: .refund)
            } label: {
                Label(localized("Условия возврата", "Refund policy", "Qaytarish shartlari", "Қайтариш шартлари"), systemImage: "doc.text.magnifyingglass")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func paymentReceiptStatusCard(_ session: StoredBookingSession, checkout: IumrahCheckoutResponse?) -> some View {
        let locked = session.effectiveStatus.uppercased() == "AVAILABILITY_CHECK"
        let receiptReady = checkout?.paymentReview?.satisfied == true || checkout?.paymentReview?.historicalConfirmed == true
        let reviewing = checkout?.receipts.contains { $0.reviewStatus == "submitted" } == true

        return NavigationLink {
            PilgrimCheckoutView(bookingID: session.id)
        } label: {
            bookingActionCard(
                icon: locked ? "lock.fill" : "creditcard.fill",
                role: .payment,
                title: localized("Оплата", "Payment", "To‘lov", "Тўлов"),
                body: locked
                    ? localized("Оплата откроется после подтверждения наличия. Пока ничего оплачивать не нужно.", "Payment opens after availability is confirmed. Nothing needs to be paid yet.", "To‘lov mavjudlik tasdiqlangach ochiladi. Hozircha hech narsa to‘lash shart emas.", "Тўлов мавжудлик тасдиқлангач очилади. Ҳозирча ҳеч нарса тўлаш шарт эмас.")
                    : (receiptReady
                       ? localized("Оплата подтверждена. Доплачивать не нужно.", "Payment verified. No further payment is required.", "To‘lov tasdiqlandi. Qo‘shimcha to‘lov kerak emas.", "Тўлов тасдиқланди. Қўшимча тўлов керак эмас.")
                       : reviewing ? localized("Чек отправлен. Проверяем поступление средств.", "Receipt submitted. Checking the transfer.", "Chek yuborildi. Mablag‘ tekshirilmoqda.", "Чек юборилди. Маблағ текширилмоқда.")
                       : localized("Наличие подтверждено. Откройте реквизиты, оплатите и прикрепите чек.", "Availability is confirmed. Open payment details, pay and attach the receipt.", "Mavjudlik tasdiqlandi. Rekvizitlarni oching, to‘lang va chekni biriktiring.", "Мавжудлик тасдиқланди. Реквизитларни очинг, тўланг ва чекни бириктиринг.")),
                action: locked
                    ? localized("Откроется после подтверждения", "Opens after confirmation", "Tasdiqdan keyin ochiladi", "Тасдиқдан кейин очилади")
                    : ((receiptReady || reviewing) ? localized("Открыть оплату", "Open payment", "To‘lovni ochish", "Тўловни очиш") : localized("Перейти к оплате", "Go to payment", "To‘lovga o‘tish", "Тўловга ўтиш")),
                ready: receiptReady,
                enabled: !locked
            )
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func documentReadinessCard(_ session: StoredBookingSession, checkout: IumrahCheckoutResponse?) -> some View {
        let documents = checkout?.documents ?? []
        let paidOrLater = ["PAID", "BOOKING_CONFIRMED", "DOCUMENTS_READY", "READY_TO_TRAVEL", "IN_TRIP", "COMPLETED"]
            .contains(session.effectiveStatus.uppercased())
        let enabled = paidOrLater || !documents.isEmpty
        let ready = checkout?.documentRequirements.map { !$0.isEmpty && $0.allSatisfy(\.ready) } ?? false

        return NavigationLink {
            PilgrimCheckoutView(bookingID: session.id)
        } label: {
            bookingActionCard(
                icon: enabled ? "doc.on.doc.fill" : "lock.doc.fill",
                role: .document,
                title: localized("Документы поездки", "Travel documents", "Safar hujjatlari", "Сафар ҳужжатлари"),
                body: ready
                    ? localized("Готово документов: \(documents.count). Авиабилеты, подтверждения отеля и остальные файлы находятся внутри.", "Documents ready: \(documents.count). Tickets, hotel confirmations and the other files are inside.", "Tayyor hujjatlar: \(documents.count). Chiptalar, mehmonxona tasdiqlari va boshqa fayllar shu yerda.", "Тайёр ҳужжатлар: \(documents.count). Чипталар, меҳмонхона тасдиқлари ва бошқа файллар шу ерда.")
                    : localized("Авиабилеты, виза и номера бронирований будут доступны после оплаты и подтверждения бронирования.", "Airline tickets, visa and booking references become available after payment and booking confirmation.", "Aviachiptalar, viza va bron raqamlari to‘lov hamda bron tasdiqlangach ochiladi.", "Авиачипталар, виза ва брон рақамлари тўлов ҳамда брон тасдиқлангач очилади."),
                action: enabled
                    ? localized("Посмотреть документы", "View documents", "Hujjatlarni ko‘rish", "Ҳужжатларни кўриш")
                    : localized("Откроется после оплаты", "Opens after payment", "To‘lovdan keyin ochiladi", "Тўловдан кейин очилади"),
                ready: ready,
                enabled: enabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func assignedGuideCard(_ session: StoredBookingSession, guide: BookingGuideSnapshot) -> some View {
        NavigationLink {
            IumrahGuideTransferView(bookingID: session.id)
        } label: {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 14) {
                    guidePreviewAvatar

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(guide.displayName.isEmpty ? localized("Ваш гид", "Your guide", "Gidingiz", "Гидингиз") : guide.displayName)
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(uiColor: .systemBlue))
                                .accessibilityLabel(localized("Подтверждённый профиль", "Verified profile", "Tasdiqlangan profil", "Тасдиқланган профиль"))
                        }

                        Text(guide.roleTitle.isEmpty ? localized("Персональный гид iumrah", "Personal iumrah guide", "iumrah shaxsiy gidi", "iumrah шахсий гиди") : guide.roleTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    Label(localized("Контакты", "Contacts", "Kontaktlar", "Контактлар"), systemImage: "phone.fill")
                    Spacer()
                    Text(localized("Гид и трансфер", "Guide & transfer", "Gid va transfer", "Гид ва трансфер"))
                    Image(systemName: "arrow.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .padding(17)
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.095), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var guidePreviewAvatar: some View {
        if let url = AppConfig.absoluteURL(activeGuideProfile?.photoURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable().scaledToFit().padding(12).foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color.iumrahRaisedBackground)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 60, height: 60)
                .background(Color.iumrahRaisedBackground, in: Circle())
        }
    }

    private func guideTransferStatusCard(_ session: StoredBookingSession, checkout: IumrahCheckoutResponse?) -> some View {
        let unlockedStatuses = ["BOOKING_CONFIRMED", "DOCUMENTS_READY", "READY_TO_TRAVEL", "IN_TRIP", "COMPLETED"]
        let enabled = session.guide != nil || unlockedStatuses.contains(session.effectiveStatus.uppercased())
        let ready = session.guide != nil

        return NavigationLink {
            IumrahGuideTransferView(bookingID: session.id)
        } label: {
            bookingActionCard(
                icon: enabled ? "person.badge.shield.checkmark.fill" : "lock.fill",
                role: .transfer,
                title: localized("Гид и трансфер", "Guide & transfer", "Gid va transfer", "Гид ва трансфер"),
                body: ready
                    ? localized("Гид назначен. Здесь доступны его контакты, данные трансфера и фото для быстрой встречи в аэропорту.", "Your guide is assigned. Contacts, transfer details and the airport recognition photo are available here.", "Gid tayinlangan. Kontaktlar, transfer ma’lumotlari va aeroportda tezroq topish uchun rasm shu yerda.", "Гид тайинланган. Контактлар, трансфер маълумотлари ва аэропортда тезроқ топиш учун расм шу ерда.")
                    : localized("Контакты гида и детали встречи откроются после подтверждения бронирования и назначения команды.", "Guide contacts and meeting details open after the booking is confirmed and the team is assigned.", "Gid kontaktlari va kutib olish ma’lumotlari bron tasdiqlanib, jamoa tayinlangach ochiladi.", "Гид контактлари ва кутиб олиш маълумотлари брон тасдиқланиб, жамоа тайинлангач очилади."),
                action: enabled
                    ? localized("Открыть данные встречи", "Open meeting details", "Kutib olish ma’lumotlarini ochish", "Кутиб олиш маълумотларини очиш")
                    : localized("Откроется после подтверждения", "Opens after confirmation", "Tasdiqdan keyin ochiladi", "Тасдиқдан кейин очилади"),
                ready: ready,
                enabled: enabled
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func bookingActionCard(
        icon: String,
        role: IumrahIconRole,
        title: String,
        body: String,
        action: String,
        ready: Bool,
        enabled: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                IumrahIconBadge(
                    systemName: ready ? "checkmark.circle.fill" : icon,
                    role: ready ? .success : role,
                    size: 54,
                    symbolSize: 21,
                    cornerRadius: 18
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text(action)
                Spacer()
                Image(systemName: enabled ? "arrow.right" : "lock.fill")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(enabled ? Color.iumrahPrimaryButtonText : Color.secondary)
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(
                enabled ? Color.iumrahPrimaryButtonBackground : Color.iumrahRaisedBackground,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
        }
        .padding(17)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(enabled ? 0.095 : 0.055), lineWidth: 0.75)
        }
        .shadow(color: enabled ? .black.opacity(0.032) : .clear, radius: 11, y: 5)
        .opacity(enabled ? 1 : 0.66)
    }

    // MARK: - Booking progress

    private func bookingProgress(_ session: StoredBookingSession) -> some View {
        let stages = progressStages
        let current = progressIndex(for: session.effectiveStatus)
        let isCancelled = session.effectiveStatus.uppercased() == "CANCELLED"

        return VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: statusTitle,
                trailing: isCancelled ? cancelledText : progressCounter(current: current, total: stages.count)
            )

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    processStep(
                        stage,
                        index: index,
                        current: current,
                        isLast: index == stages.count - 1,
                        session: session,
                        isCancelled: isCancelled
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func bookingStatusWorkspace(_ session: StoredBookingSession) -> some View {
        if session.effectiveStatus.uppercased() != "CANCELLED" {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader(
                    title: localized("Данные бронирования", "Booking details", "Bron ma’lumotlari", "Брон маълумотлари"),
                    trailing: nil
                )

                PilgrimCheckoutView(bookingID: session.id, presentation: .bookingStatus)

                if shouldShowTravelReadyFlights(session) {
                    bookingStatusFlights(session)
                }
            }
        }
    }

    private func shouldShowTravelReadyFlights(_ session: StoredBookingSession) -> Bool {
        ["READY_TO_TRAVEL", "IN_TRIP"].contains(session.effectiveStatus.uppercased())
    }

    private func bookingStatusFlights(_ session: StoredBookingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                IumrahIconBadge(systemName: "airplane", role: .travel, size: 46, symbolSize: 19, cornerRadius: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(localized("Ваши авиабилеты", "Your flights", "Aviachiptalaringiz", "Авиачипталарингиз"))
                        .font(.headline)
                    Text(localized("Полные данные рейсов закреплены в статусе поездки.", "Full flight details stay attached to your trip status.", "Parvozning to‘liq ma’lumotlari safar holatida saqlanadi.", "Парвознинг тўлиқ маълумотлари сафар ҳолатида сақланади."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let outbound = session.outboundFlight {
                bookingStatusFlightCard(outbound, label: localized("Туда", "Outbound", "Borish", "Бориш"))
            } else {
                bookingStatusLegacyFlightCard(
                    title: localized("Туда", "Outbound", "Borish", "Бориш"),
                    route: "\(session.booking.route.originCode) → \(session.booking.route.outboundDestination)",
                    date: session.booking.input.startDate,
                    value: session.booking.flight
                )
            }

            if let inbound = session.inboundFlight {
                bookingStatusFlightCard(inbound, label: localized("Обратно", "Return", "Qaytish", "Қайтиш"))
            } else {
                bookingStatusLegacyFlightCard(
                    title: localized("Обратно", "Return", "Qaytish", "Қайтиш"),
                    route: "\(session.booking.route.returnOrigin) → \(session.booking.route.originCode)",
                    date: session.booking.input.endDate,
                    value: session.booking.flight
                )
            }

            NavigationLink {
                IumrahFlightsView(preferredBookingID: session.id)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.wave.radiowaves.left.and.right")
                    Text(localized("Отслеживать рейс", "Track flight", "Reysni kuzatish", "Рейсни кузатиш"))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.iumrahPrimaryButtonText)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.iumrahPrimaryButtonBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(17)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }

    private func bookingStatusFlightCard(_ offer: FlightOffer, label: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AirlineLogoView(airlineCode: offer.primaryAirlineCode, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    Text(offer.flightNumbersSummary.isEmpty ? offer.flightNumber : offer.flightNumbersSummary)
                        .font(.headline.monospaced())
                    Text(offer.airlinesSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(offer.stops == 0 ? localized("Прямой", "Direct", "To‘g‘ridan", "Тўғридан") : localized("С пересадкой", "Connection", "Ulanish", "Уланиш"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(offer.displaySegments.enumerated()), id: \.element.id) { index, segment in
                if index > 0 { Divider() }
                VStack(spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(segment.flightNumber)
                            .font(.caption.monospaced().weight(.bold))
                        if let operatingCarrier = nonBlankFlightValue(segment.operatingCarrier), operatingCarrier != segment.airline {
                            Text(operatingCarrier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let aircraft = nonBlankFlightValue(segment.aircraft) {
                            Text(aircraft)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.origin.code)
                                .font(.title3.weight(.bold))
                            Text(segment.origin.displayCity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(segment.origin.displayAirport)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "airplane")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(segment.destination.code)
                                .font(.title3.weight(.bold))
                            Text(segment.destination.displayCity)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(segment.destination.displayAirport)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusFlightTime(segment.departureAt, zone: segment.origin.timeZoneIdentifier))
                            Text(statusFlightDate(segment.departureAt, zone: segment.origin.timeZoneIdentifier))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(statusFlightDuration(segment.durationMinutes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(statusFlightTime(segment.arrivalAt, zone: segment.destination.timeZoneIdentifier))
                            Text(statusFlightDate(segment.arrivalAt, zone: segment.destination.timeZoneIdentifier))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline.monospacedDigit().weight(.semibold))

                    HStack(spacing: 8) {
                        if let terminal = nonBlankFlightValue(segment.origin.terminal) {
                            flightMetaPill(localized("Вылет", "Dep", "Uchish", "Учиш") + " T\(terminal)")
                        }
                        if let terminal = nonBlankFlightValue(segment.destination.terminal) {
                            flightMetaPill(localized("Прилёт", "Arr", "Qo‘nish", "Қўниш") + " T\(terminal)")
                        }
                        if let cabin = nonBlankFlightValue(segment.cabin) {
                            flightMetaPill(cabin)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if let carry = offer.baggage?.carryOn { flightMetaPill(localized("Ручная", "Carry-on", "Qo‘l yuki", "Қўл юки") + " \(carry) kg") }
                if let checked = offer.baggage?.checked { flightMetaPill(localized("Багаж", "Checked", "Bagaj", "Багаж") + " \(checked) kg") }
            }
        }
        .padding(14)
        .background(Color.iumrahRaisedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private func bookingStatusLegacyFlightCard(title: String, route: String, date: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(route)
                .font(.headline)
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(L10n.date(date, settings.language))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.iumrahRaisedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }

    private func flightMetaPill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(Color.primary.opacity(0.045), in: Capsule())
    }

    private func statusFlightDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return "\(mins)m" }
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h \(mins)m"
    }

    private func nonBlankFlightValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func statusFlightTime(_ date: Date, zone: String?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        if let zone, let timeZone = TimeZone(identifier: zone) { formatter.timeZone = timeZone }
        return formatter.string(from: date)
    }

    private func statusFlightDate(_ date: Date, zone: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        if let zone, let timeZone = TimeZone(identifier: zone) { formatter.timeZone = timeZone }
        return formatter.string(from: date)
    }

    private func processStep(
        _ stage: BookingProgressStage,
        index: Int,
        current: Int,
        isLast: Bool,
        session: StoredBookingSession,
        isCancelled: Bool
    ) -> some View {
        let completed = isCancelled ? index == 0 : index < current
        let active = index == current
        let future = index > current
        let effectiveStage = isCancelled && active ? cancelledStage : stage
        let nodeColor = active
            ? IumrahBookingStatusVisual.color(for: session.effectiveStatus)
            : (completed ? Color(uiColor: .systemGreen) : Color(uiColor: .secondaryLabel).opacity(0.62))
        let lineColor = completed
            ? Color(uiColor: .systemGreen).opacity(0.36)
            : Color.primary.opacity(0.12)

        return HStack(alignment: .top, spacing: 17) {
            ZStack {
                Circle()
                    .fill(completed || active ? nodeColor : Color.iumrahPageBackground)
                    .frame(width: 25, height: 25)
                    .overlay {
                        if future {
                            Circle()
                                .strokeBorder(Color(uiColor: .secondaryLabel).opacity(0.52), lineWidth: 1.6)
                        }
                    }

                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                } else if active {
                    Circle()
                        .fill(activeNodeForeground(for: session.effectiveStatus))
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 26, height: 25, alignment: .top)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(effectiveStage.title)
                        .font(.system(size: active ? 18 : 17, weight: active ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(future ? Color(uiColor: .secondaryLabel) : Color.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if index <= current,
                       let rawTimestamp = lifecycleStageTimestamp(index: index, session: session, isCancelled: isCancelled),
                       let date = createdDateText(rawTimestamp) {
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    if active {
                        Text(activeStageSubtitle(session, fallback: effectiveStage.activeSubtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if active {
                    activeStageCard(session, stage: effectiveStage)
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 13)
        }
        .overlay(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(lineColor)
                    .frame(width: 1)
                    .padding(.top, 25)
                    .offset(x: 12.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func activeStageCard(_ session: StoredBookingSession, stage: BookingProgressStage) -> some View {
        let tint = IumrahBookingStatusVisual.color(for: session.effectiveStatus)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint)
                        .frame(width: 34, height: 34)
                    if session.effectiveStatus.uppercased() == "AVAILABILITY_CHECK" {
                        Image(systemName: "hourglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(activeNodeForeground(for: session.effectiveStatus))
                            .symbolEffect(.pulse, options: .repeating)
                    } else {
                        Image(systemName: IumrahBookingStatusVisual.symbol(for: session.effectiveStatus))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(activeNodeForeground(for: session.effectiveStatus))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(activeCardTitle(session, fallback: stage.cardTitle))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .tracking(-0.25)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(activeCardBody(session, fallback: stage.cardBody))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            lifecycleTimerPanel(session, tint: tint)

            Divider()
                .overlay(Color.primary.opacity(0.05))

            VStack(spacing: 13) {
                progressFact(title: routeTitle, value: "\(session.booking.route.originCode) → \(session.booking.route.outboundDestination)")
                progressFact(title: dateTitle, value: "\(L10n.date(session.booking.input.startDate, settings.language)) – \(L10n.date(session.booking.input.endDate, settings.language))")
                if !session.booking.hotelNames.makkah.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    progressFact(title: hotelTitle, value: session.booking.hotelNames.makkah)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(priceTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PackagePriceView(amount: Decimal(session.booking.perPilgrimUsd), currency: "USD", showsPerPerson: false)
                }

                Spacer(minLength: 12)

                Text(pilgrimCountText(session.booking.input.travelers.totalPeople))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            statusCardActions(session)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.iumrahCardBackground)
                .overlay {
                    LinearGradient(
                        colors: [tint.opacity(0.13), tint.opacity(0.025), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
        }
    }

    @ViewBuilder
    private func lifecycleTimerPanel(_ session: StoredBookingSession, tint: Color) -> some View {
        if let phase = lifecyclePhase(for: session), let deadline = phase.deadline {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, deadline.timeIntervalSince(context.date))
                let expired = remaining <= 0

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lifecycleTimerTitle(phase, expired: expired))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(phase.isAvailability && expired
                                 ? localized("Проверяем", "Checking", "Tekshirilmoqda", "Текширилмоқда")
                                 : lifecycleCountdown(remaining))
                                .font(.system(size: 31, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .tracking(-0.7)
                                .contentTransition(.numericText())
                        }
                        Spacer(minLength: 12)
                        Image(systemName: phase.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 38, height: 38)
                            .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    Text(lifecycleTimerFootnote(phase, expired: expired))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func statusCardActions(_ session: StoredBookingSession) -> some View {
        VStack(spacing: 10) {
            Button { selectedBookingID = session.id; bookingPanel = .status } label: {
                statusCardButtonLabel(title: openStatusTitle, isPrimary: true)
            }
            .buttonStyle(.plain)

            Button { selectedBookingID = session.id; bookingPanel = .package } label: {
                statusCardButtonLabel(title: openBookingTitle, isPrimary: false)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }

    private func statusCardButtonLabel(title: String, isPrimary: Bool) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
            Spacer(minLength: 8)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
        }
        .foregroundStyle(isPrimary ? Color.white : Color.primary)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            isPrimary ? Color.black : Color.iumrahRaisedBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            if !isPrimary {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
    }

    private func lifecyclePhase(for session: StoredBookingSession) -> BookingLifecyclePhase? {
        switch session.effectiveStatus.uppercased() {
        case "NEW", "AVAILABILITY_CHECK":
            return .availability(session.availabilityEstimateDeadline)
        case "PAYMENT_PENDING":
            if session.operationPaymentStatus?.lowercased() == "paid" { return nil }
            if session.operationPaymentStatus?.lowercased() == "receipt_submitted" || (session.operationPaymentStatus == nil && session.paymentReceivedAt != nil) {
                let deadline = lifecycleDeadline(
                    explicit: session.paymentConfirmationDeadlineAt,
                    start: session.paymentReceivedAt,
                    duration: 10 * 60
                )
                return .paymentConfirmation(deadline)
            }
            let deadline = lifecycleDeadline(
                explicit: session.priceLockExpiresAt,
                start: session.priceLockStartedAt ?? transitionDate("payment_pending", session: session) ?? session.booking.updatedAt,
                duration: 30 * 60
            )
            return .priceLock(deadline)
        case "PAID", "BOOKING_CONFIRMED":
            let deadline = lifecycleDeadline(
                explicit: session.documentsDeadlineAt,
                start: session.documentsStartedAt ?? transitionDate("booking_confirmed", session: session) ?? session.booking.updatedAt,
                duration: 24 * 60 * 60
            )
            return .documents(deadline)
        default:
            return nil
        }
    }

    private func lifecycleDeadline(explicit: String?, start: String?, duration: TimeInterval) -> Date? {
        if let explicit, let value = Self.isoDate(explicit) { return value }
        guard let start, let value = Self.isoDate(start) else { return nil }
        return value.addingTimeInterval(duration)
    }

    private func lifecycleCountdown(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func lifecycleTimerTitle(_ phase: BookingLifecyclePhase, expired: Bool) -> String {
        switch phase {
        case .availability:
            return expired
                ? localized("Проверка занимает дольше обычного", "The check is taking longer than usual", "Tekshiruv odatdagidan uzoqroq davom etmoqda", "Текширув одатдагидан узоқроқ давом этмоқда")
                : localized("Ориентировочное время проверки", "Estimated check time", "Taxminiy tekshiruv vaqti", "Тахминий текshiruv vaqti")
        case .priceLock:
            return expired
                ? localized("Срок фиксации цены завершён", "Price hold has ended", "Narxni saqlash muddati tugadi", "Нархни сақлаш муддати тугади")
                : localized("Цена зафиксирована ещё", "Price held for", "Narx yana shuncha vaqtga saqlanadi", "Нарх яна шунча вақтга сақланади")
        case .paymentConfirmation:
            return expired
                ? localized("Подтверждение занимает дольше обычного", "Confirmation is taking longer than usual", "Tasdiqlash odatdagidan uzoqroq davom etmoqda", "Тасдиқлаш одатдагидан узоқроқ давом этмоқда")
                : localized("Подтверждаем оплату", "Confirming payment", "To‘lov tasdiqlanmoqda", "Тўлов тасдиқланмоқда")
        case .documents:
            return expired
                ? localized("Подготовка занимает дольше обычного", "Preparation is taking longer than usual", "Tayyorlash odatdagidan uzoqroq davom etmoqda", "Тайёрлаш одатдагидан узоқроқ давом этмоқда")
                : localized("Плановый срок подготовки", "Planned preparation time", "Rejalashtirilgan tayyorlash muddati", "Режалаштирилган тайёрлаш муддати")
        }
    }

    private func lifecycleTimerFootnote(_ phase: BookingLifecyclePhase, expired: Bool) -> String {
        switch phase {
        case .availability:
            return expired
                ? localized("Мы продолжаем проверку. Статус обновится автоматически, как только все компоненты будут подтверждены.", "We are continuing the check. The status will update automatically once all components are confirmed.", "Tekshiruv davom etmoqda. Barcha qismlar tasdiqlangach holat avtomatik yangilanadi.", "Текширув давом этмоқда. Барча қисмлар тасдиқлангач ҳолат автоматик янгиланади.")
                : localized("Обычно проверка занимает около 30 минут, иногда дольше. Можно закрыть приложение — статус обновится автоматически.", "The check usually takes about 30 minutes, sometimes longer. You can close the app — the status will update automatically.", "Tekshiruv odatda 30 daqiqa, ba’zan uzoqroq davom etadi. Ilovani yopishingiz mumkin — holat avtomatik yangilanadi.", "Текширув одатда 30 дақиқа, баъзан узоқроқ давом этади. Иловани ёпишингиз мумкин — ҳолат автоматик янгиланади.")
        case .priceLock:
            return expired
                ? localized("Перед подтверждением оплаты iumrah повторно проверит актуальную итоговую стоимость.", "Before confirming payment, iumrah will recheck the current total price.", "To‘lovni tasdiqlashdan oldin iumrah yakuniy narxning dolzarbligini qayta tekshiradi.", "Тўловни тасдиқлашдан олдин iumrah якуний нархнинг долзарблигини қайта текширади.")
                : localized("Авиабилеты и некоторые другие компоненты имеют динамическую стоимость и после окончания периода могут потребовать повторной проверки.", "Flights and some other components have dynamic pricing and may require a fresh check after this period.", "Aviachiptalar va ayrim boshqa qismlar dinamik narxga ega, muddat tugagach qayta tekshiruv talab qilinishi mumkin.", "Авиачипталар ва айрим бошқа қисмлар динамик нархга эга, муддат тугагач қайта текширув талаб қилиниши мумкин.")
        case .paymentConfirmation:
            return localized("Чек отправлен. Проверяем поступление средств; обычно это занимает около 10 минут.", "Receipt submitted. We are checking the transfer; this usually takes about 10 minutes.", "Chek yuborildi. Mablag‘ tushganini tekshiryapmiz; odatda 10 daqiqa.", "Чек юборилди. Маблағ тушганини текширяпмиз; одатда 10 дақиқа.")
        case .documents:
            return localized("Обычно доступные документы готовятся в течение 24 часов. Срок визы может зависеть от доступности официальных визовых систем Саудовской Аравии и внешних ограничений.", "Available travel documents are usually prepared within 24 hours. Visa timing can depend on the availability of Saudi Arabia’s official visa systems and external restrictions.", "Mavjud safar hujjatlari odatda 24 soat ichida tayyorlanadi. Viza muddati Saudiya Arabistonining rasmiy viza tizimlari mavjudligi va tashqi cheklovlarga bog‘liq bo‘lishi mumkin.", "Мавжуд сафар ҳужжатлари одатда 24 соат ичида тайёрланади. Виза муддати Саудия Арабистонининг расмий виза тизимлари мавжудлиги ва ташқи чекловларга боғлиқ бўлиши мумкин.")
        }
    }

    private func activeStageSubtitle(_ session: StoredBookingSession, fallback: String) -> String {
        if session.effectiveStatus.uppercased() == "PAYMENT_PENDING", session.operationPaymentStatus == "paid" { return localized("Оплата подтверждена · проверяем данные", "Payment verified · checking details", "To‘lov tasdiqlandi · ma’lumotlar tekshirilmoqda", "Тўлов тасдиқланди · маълумотлар текширилмоқда") }
        switch lifecyclePhase(for: session) {
        case .paymentConfirmation:
            return localized("Чек отправлен · проверяем оплату", "Receipt submitted · checking payment", "Chek yuborildi · to‘lov tekshirilmoqda", "Чек юборилди · тўлов текширилмоқда")
        case .documents:
            return localized("Бронирование подтверждено · готовим документы", "Booking confirmed · preparing documents", "Bron tasdiqlandi · hujjatlar tayyorlanmoqda", "Брон тасдиқланди · ҳужжатлар тайёрланмоқда")
        default:
            return fallback
        }
    }

    private func activeCardTitle(_ session: StoredBookingSession, fallback: String) -> String {
        if session.effectiveStatus.uppercased() == "PAYMENT_PENDING", session.operationPaymentStatus == "paid" { return localized("Оплата подтверждена", "Payment verified", "To‘lov tasdiqlandi", "Тўлов тасдиқланди") }
        switch lifecyclePhase(for: session) {
        case .priceLock: return localized("Цена зафиксирована", "Price held", "Narx saqlandi", "Нарх сақланди")
        case .paymentConfirmation: return localized("Чек отправлен", "Receipt submitted", "Chek yuborildi", "Чек юборилди")
        case .documents: return localized("Подготавливаем документы", "Preparing documents", "Hujjatlar tayyorlanmoqda", "Ҳужжатлар тайёрланмоқда")
        default: return fallback
        }
    }

    private func activeCardBody(_ session: StoredBookingSession, fallback: String) -> String {
        if session.effectiveStatus.uppercased() == "PAYMENT_PENDING", session.operationPaymentStatus == "paid" { return localized("Доплачивать не нужно. Мы проверяем данные и подтверждаем бронирование.", "No further payment is needed. We are checking details and confirming the booking.", "Qo‘shimcha to‘lov kerak emas. Ma’lumotlarni tekshirib, bronni tasdiqlayapmiz.", "Қўшимча тўлов керак эмас. Маълумотларни текшириб, бронни тасдиқлаяпмиз.") }
        switch lifecyclePhase(for: session) {
        case .availability:
            return localized("iumrah подтверждает перелёт, отель и выбранные услуги. Обычно это занимает около 30 минут, иногда дольше.", "iumrah is confirming your flight, hotel and selected services. This usually takes about 30 minutes, sometimes longer.", "iumrah parvoz, mehmonxona va tanlangan xizmatlarni tasdiqlamoqda. Odatda 30 daqiqa, ba’zan uzoqroq.", "iumrah парвоз, меҳмонхона ва танланган хизматларни тасдиқламоқда. Одатда 30 дақиқа, баъзан узоқроқ.")
        case .priceLock:
            return localized("Итоговая цена пакета зафиксирована на время оплаты.", "Your package total is held during the payment window.", "Paketning yakuniy narxi to‘lov oynasi davomida saqlanadi.", "Пакетнинг якуний нархи тўлов ойнаси давомида сақланади.")
        case .paymentConfirmation:
            return localized("Проверяем поступление средств. Отправленный чек не является подтверждением оплаты.", "We are checking the transfer. A submitted receipt is not payment confirmation.", "Mablag‘ tushganini tekshiryapmiz. Chek to‘lov tasdig‘i emas.", "Маблағ тушганини текширяпмиз. Чек тўлов тасдиғи эмас.")
        case .documents:
            return localized("Бронирование подтверждено. Теперь готовим доступные документы поездки.", "Your booking is confirmed. We are now preparing the available travel documents.", "Bron tasdiqlandi. Endi mavjud safar hujjatlari tayyorlanmoqda.", "Брон тасдиқланди. Энди мавжуд сафар ҳужжатлари тайёрланмоқда.")
        case nil:
            return fallback
        }
    }

    private func progressFact(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cancelledStage: BookingProgressStage {
        BookingProgressStage(
            title: localized("Бронирование отменено", "Booking cancelled", "Bron bekor qilindi", "Брон бекор қилинди"),
            activeSubtitle: localized("Поездка остановлена", "The trip has been stopped", "Safar to‘xtatildi", "Сафар тўхтатилди"),
            cardTitle: localized("Бронирование отменено", "Booking cancelled", "Bron bekor qilindi", "Брон бекор қилинди"),
            cardBody: localized("Откройте бронирование, чтобы посмотреть сохранённые детали поездки и доступные действия.", "Open the booking to review the saved trip details and available actions.", "Saqlangan safar tafsilotlari va mavjud amallarni ko‘rish uchun bronni oching.", "Сақланган сафар тафсилотлари ва мавжуд амалларни кўриш учун бронни очинг.")
        )
    }

    private var progressStages: [BookingProgressStage] {
        [
            BookingProgressStage(
                title: createdTitle,
                activeSubtitle: createdSubtitle,
                cardTitle: createdTitle,
                cardBody: createdSubtitle
            ),
            BookingProgressStage(
                title: availabilityTitle,
                activeSubtitle: availabilitySubtitle,
                cardTitle: availabilityCardTitle,
                cardBody: availabilityCardBody
            ),
            BookingProgressStage(
                title: paymentStageTitle,
                activeSubtitle: paymentStageSubtitle,
                cardTitle: paymentCardTitle,
                cardBody: paymentCardBody
            ),
            BookingProgressStage(
                title: confirmedStageTitle,
                activeSubtitle: confirmedStageSubtitle,
                cardTitle: confirmedCardTitle,
                cardBody: confirmedCardBody
            ),
            BookingProgressStage(
                title: documentsStageTitle,
                activeSubtitle: documentsStageSubtitle,
                cardTitle: documentsCardTitle,
                cardBody: documentsCardBody
            ),
            BookingProgressStage(
                title: inTripStageTitle,
                activeSubtitle: inTripStageSubtitle,
                cardTitle: inTripCardTitle,
                cardBody: inTripCardBody
            ),
            BookingProgressStage(
                title: completedStageTitle,
                activeSubtitle: completedStageSubtitle,
                cardTitle: completedCardTitle,
                cardBody: completedCardBody
            )
        ]
    }

    private func progressIndex(for status: String) -> Int {
        switch status.uppercased() {
        case "NEW", "AVAILABILITY_CHECK": return 1
        case "PAYMENT_PENDING": return 2
        case "PAID", "BOOKING_CONFIRMED": return 3
        case "DOCUMENTS_READY", "READY_TO_TRAVEL": return 4
        case "IN_TRIP": return 5
        case "COMPLETED": return 6
        case "CANCELLED": return 1
        default: return 1
        }
    }

    private func progressCounter(current: Int, total: Int) -> String {
        localized("\(current + 1) из \(total)", "\(current + 1) of \(total)", "\(current + 1) / \(total)", "\(current + 1) / \(total)")
    }

    @MainActor
    private func loadActiveGuideProfile() async {
        guard let guideID = activeSession?.guide?.id, !guideID.isEmpty else {
            activeGuideProfile = nil
            return
        }
        activeGuideProfile = try? await chatService.loadTeamProfile(id: guideID)
    }

    private func activeNodeForeground(for status: String) -> Color {
        switch IumrahBookingStatusVisual.role(for: status) {
        case .waiting, .warning, .rating:
            return Color.black.opacity(0.78)
        default:
            return .white
        }
    }

    // MARK: - Trip plan preview

    private func tripPlanPreview(_ session: StoredBookingSession) -> some View {
        let items = previewItineraryItems(session)

        return VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: tripPlanTitle, trailing: nil)

            VStack(spacing: 0) {
                if items.isEmpty {
                    Text(tripPlanEmptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                        .padding(.horizontal, 17)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        tripPlanRow(item)
                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }

                Divider()
                    .padding(.leading, 17)

                Button {
                    withAnimation(.snappy(duration: 0.24)) { bookingPanel = .schedule }
                    IumrahHaptics.selection()
                } label: {
                    HStack {
                        Text(openFullPlanTitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 17)
                    .frame(height: 54)
                }
                .buttonStyle(.plain)
            }
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
        }
    }

    private func tripPlanRow(_ item: BookingItineraryItem) -> some View {
        HStack(alignment: .top, spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.iumrahRaisedBackground)
                    .frame(width: 39, height: 39)
                Image(systemName: safeIcon(item.icon))
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(compactDate(item.dateLocal))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(2)
                }

                if !item.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !item.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.location)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
    }

    private func previewItineraryItems(_ session: StoredBookingSession) -> [BookingItineraryItem] {
        let remote = bookings.itineraries[session.id] ?? []
        let source: [BookingItineraryItem]
        let distinctRemoteDays = Set(remote.map(\.dateLocal)).count
        if distinctRemoteDays >= 2 {
            source = remote.sorted { lhs, rhs in
                if lhs.dateLocal == rhs.dateLocal { return lhs.sortOrder < rhs.sortOrder }
                return lhs.dateLocal < rhs.dateLocal
            }
        } else {
            source = BookingItineraryPlanner.make(booking: session.booking, language: settings.language)
        }

        guard !source.isEmpty else { return [] }
        let today = Self.riyadhDayFormatter.string(from: Date())
        let upcoming = source.filter { $0.dateLocal >= today }
        if !upcoming.isEmpty { return Array(upcoming.prefix(3)) }
        return Array(source.suffix(3))
    }

    // MARK: - Management

    private var archiveList: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: localized("История поездок", "Trip history", "Safar tarixi", "Сафар тарихи"), trailing: nil)
            ForEach(pastSessions) { session in
                Button { selectedBookingID = session.id; bookingPanel = .booking } label: { compactBookingCard(session) }.buttonStyle(.plain)
            }
            if let selectedBookingID, pastSessions.contains(where: { $0.id == selectedBookingID }) {
                Button(localized("К активным поездкам", "Back to active trips", "Faol safarlarga", "Фаол сафарларга")) { self.selectedBookingID = nil; bookingPanel = .booking }.font(.subheadline.weight(.semibold))
            }
        }
    }

    private func travelDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Riyadh"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }
    private var saudiToday: String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Riyadh"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: Date())
    }
    private func travelDayLabel(_ session: StoredBookingSession) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Riyadh") ?? .current
        guard let start = travelDate(session.booking.input.startDate), let end = travelDate(session.booking.input.endDate), let today = travelDate(saudiToday) else { return "" }
        let total = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let elapsed = (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1
        if elapsed < 1 { return localized("До вылета: \(1-elapsed) дн.", "Days to departure: \(1-elapsed)", "Uchishga \(1-elapsed) kun", "Учишга \(1-elapsed) кун") }
        if elapsed > total { return localized("Ожидаем подтверждения завершения", "Awaiting trip completion", "Safar yakuni tasdiqlanmoqda", "Сафар якуни тасдиқланмоқда") }
        return localized("День \(elapsed) из \(total)", "Day \(elapsed) of \(total)", "\(total) kundan \(elapsed)-kun", "\(total) кундан \(elapsed)-кун")
    }
    private func executionLabel(_ value: String?) -> String {
        switch value {
        case "completed": return localized("Выполнено", "Completed", "Bajarildi", "Бажарилди")
        case "delayed": return localized("Задерживается", "Delayed", "Kechikmoqda", "Кечикмоқда")
        case "rescheduled": return localized("Перенесено", "Rescheduled", "Ko‘chirildi", "Кўчирилди")
        case "in_progress": return localized("Выполняется", "In progress", "Bajarilmoqda", "Бажарилмоқда")
        default: return localized("Запланировано", "Planned", "Rejalashtirilgan", "Режалаштирилган")
        }
    }
    private func travelCompanion(_ session: StoredBookingSession) -> some View {
        let items = (bookings.itineraries[session.id] ?? []).sorted { $0.dateLocal == $1.dateLocal ? $0.sortOrder < $1.sortOrder : $0.dateLocal < $1.dateLocal }
        let today = items.filter { $0.dateLocal == saudiToday }
        let attention = items.first { $0.executionState == "in_progress" || $0.executionState == "delayed" || $0.executionState == "rescheduled" }
        let next = attention ?? items.first { $0.dateLocal >= saudiToday && $0.executionState != "completed" }
        let inTrip = session.effectiveStatus.uppercased() == "IN_TRIP"
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("iumrah", systemImage: "globe.europe.africa").font(.headline)
                Text(inTrip ? localized("Ваша поездка", "Your journey", "Safaringiz", "Сафарингиз") : localized("Всё готово к поездке", "Ready to travel", "Safarga tayyor", "Сафарга тайёр")).font(.largeTitle.bold())
                Text(travelDayLabel(session)).font(.headline).foregroundStyle(.white.opacity(0.8))
                Text(session.displayBookingNumber).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.7))
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).foregroundStyle(.white).background(Color.black, in: RoundedRectangle(cornerRadius: 26))
            if travelScheduleError { Text(localized("Не удалось обновить расписание. Показана последняя доступная версия.", "Schedule refresh failed. Showing the last available version.", "Jadval yangilanmadi. Oxirgi mavjud nusxa ko‘rsatilmoqda.", "Жадвал янгиланмади. Охирги мавжуд нусха кўрсатилмоқда.")).font(.caption).foregroundStyle(.secondary) }
            if !travelScheduleLoaded && items.isEmpty && !travelScheduleError { ProgressView().frame(maxWidth: .infinity) }
            if let next {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Ближайшее событие", "Next event", "Keyingi tadbir", "Кейинги тадбир")).font(.caption.bold()).foregroundStyle(.secondary)
                    Text(next.title).font(.title2.bold())
                    Text([next.dateLocal, next.timeLocal ?? "", next.location].filter { !$0.isEmpty }.joined(separator: " · ")).font(.subheadline)
                    Text(executionLabel(next.executionState)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
            }
            if !today.isEmpty {
                sectionHeader(title: localized("Сегодня", "Today", "Bugun", "Бугун"), trailing: nil)
                ForEach(today) { item in
                    HStack { Image(systemName: item.executionState == "completed" ? "checkmark.circle.fill" : "clock"); VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.headline); Text([item.timeLocal ?? "", executionLabel(item.executionState)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }; Spacer() }.padding(12)
                }
            }
            Button { bookingPanel = .schedule } label: { managementRow(icon: "calendar", title: localized("Полное расписание", "Full schedule", "To‘liq jadval", "Тўлиқ жадвал"), subtitle: localized("Программа поездки", "Trip programme", "Safar dasturi", "Сафар дастури")) }.buttonStyle(.plain)
            if let guide = session.guide { assignedGuideCard(session, guide: guide) }
            else { guideTransferStatusCard(session, checkout: nil) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                Button { bookingPanel = .status } label: { travelTile("doc.on.doc", localized("Документы", "Documents", "Hujjatlar", "Ҳужжатлар")) }.buttonStyle(.plain)
                Button { bookingPanel = .package } label: { travelTile("building.2", localized("Отели и рейсы", "Hotels & flights", "Mehmonxonalar va reyslar", "Меҳмонхоналар ва рейслар")) }.buttonStyle(.plain)
                if session.booking.customization?.esim == true || session.booking.includedServices?.contains(where: { $0.lowercased() == "esim" }) == true || !bookings.esimProfiles(for: session.id).isEmpty {
                    NavigationLink { ESIMView(bookingID: session.id) } label: { travelTile("simcard", "eSIM") }.buttonStyle(.plain)
                }
                Button { showAdvisor = true } label: { travelTile("headphones", "Advisor") }.buttonStyle(.plain)
                Button { showZiyarats = true } label: { travelTile("map", localized("Зияраты", "Ziyarats", "Ziyoratlar", "Зиёратлар")) }.buttonStyle(.plain)
                if bookings.canUseBookingCare(session.id) {
                    NavigationLink { BookingChatView(bookingID: session.id) } label: { travelTile("message", localized("Поддержка", "Support", "Yordam", "Ёрдам")) }.buttonStyle(.plain)
                } else {
                    Link(destination: URL(string: "tel:+998508898845")!) { travelTile("phone", localized("Позвонить в поддержку", "Call support", "Yordamga qo‘ng‘iroq", "Ёрдамга қўнғироқ")) }.buttonStyle(.plain)
                }
            }
        }
    }
    private func travelTile(_ icon: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).font(.title2); Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).padding(14).foregroundStyle(.primary).background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
    }
    private func completedTrip(_ session: StoredBookingSession) -> some View {
        let complete = session.effectiveStatus.uppercased() == "COMPLETED"
        let checkout = bookings.cachedCheckout(id: session.id, token: account.bearerToken)
        let feedback = checkout?.feedback ?? (feedbackSavedBookingID == session.id ? feedbackSaved : nil)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: complete ? "checkmark.circle" : "xmark.circle").font(.system(size: 48, weight: .light))
                    .scaleEffect(!complete || reduceMotion || completionAppeared ? 1 : 0.72)
                    .opacity(!complete || reduceMotion || completionAppeared ? 1 : 0.4)
                    .task(id: session.id) { withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.75)) { completionAppeared = true } }
                Text(complete ? localized("Поездка завершена", "Trip completed", "Safar yakunlandi", "Сафар якунланди") : localized("Поездка отменена", "Trip cancelled", "Safar bekor qilindi", "Сафар бекор қилинди")).font(.largeTitle.bold())
                if complete { Text(localized("Пусть Аллах примет вашу умру.", "May Allah accept your Umrah.", "Alloh umrangizni qabul qilsin.", "Аллоҳ умрангизни қабул қилсин.")).foregroundStyle(.white.opacity(0.8)) }
                Text(session.displayBookingNumber).font(.caption.monospaced())
            }.frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).padding(20).background(Color.black, in: RoundedRectangle(cornerRadius: 26))
            Button { bookingPanel = .status } label: { managementRow(icon: "folder", title: localized("Архив документов", "Document archive", "Hujjatlar arxivi", "Ҳужжатлар архиви"), subtitle: localized("Файлы поездки", "Travel files", "Safar fayllari", "Сафар файллари")) }.buttonStyle(.plain)
            Button { bookingPanel = .package } label: { managementRow(icon: "suitcase", title: localized("Детали поездки", "Trip details", "Safar tafsilotlari", "Сафар тафсилотлари"), subtitle: session.displayBookingNumber) }.buttonStyle(.plain)
            Button { bookingPanel = .schedule } label: { managementRow(icon: "calendar", title: localized("Расписание", "Schedule", "Jadval", "Жадвал"), subtitle: localized("История поездки", "Trip history", "Safar tarixi", "Сафар тарихи")) }.buttonStyle(.plain)
            if complete {
                if let certificates = checkout?.certificates, !certificates.isEmpty {
                    sectionHeader(title: localized("Памятные сертификаты", "Memorial certificates", "Esdalik sertifikatlari", "Эсдалик сертификатлари"), trailing: nil)
                    ForEach(certificates) { certificate in
                        Button { shareCertificate(certificate, session: session) } label: { managementRow(icon: "rosette", title: certificate.name, subtitle: localized("Сохранить PDF", "Save PDF", "PDF saqlash", "PDF сақлаш")) }.buttonStyle(.plain)
                    }
                    if certificateShareError { Text(localized("Не удалось создать PDF", "Could not create PDF", "PDF yaratilmadi", "PDF яратилмади")).font(.caption).foregroundStyle(.red) }
                }
                if let feedback { Text(localized("Спасибо за отзыв", "Thank you for your feedback", "Fikringiz uchun rahmat", "Фикрингиз учун раҳмат")).font(.headline); Text("\(feedback.rating)/5").font(.title2.bold()); if !feedback.comment.isEmpty { Text(feedback.comment).font(.subheadline) } }
                else {
                    Text(localized("Как прошла ваша поездка?", "How was your trip?", "Safaringiz qanday o‘tdi?", "Сафарингиз қандай ўтди?")).font(.title2.bold())
                    HStack { ForEach(1...5, id: \.self) { value in Button { rating = value } label: { Image(systemName: value <= rating ? "star.fill" : "star").font(.title2).foregroundStyle(Color.primary).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.plain).accessibilityLabel("\(value)/5") } }
                    TextField(localized("Комментарий (необязательно)", "Comment (optional)", "Izoh (ixtiyoriy)", "Изоҳ (ихтиёрий)"), text: $feedbackComment, axis: .vertical).lineLimit(2...5).padding(12).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 12))
                    Button { Task { await sendTravelFeedback(session.id) } } label: { Text(localized("Отправить отзыв", "Send feedback", "Fikr yuborish", "Фикр юбориш")).font(.headline).frame(maxWidth: .infinity).padding(14).foregroundStyle(.white).background(Color.black, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).disabled(rating == 0 || feedbackSending || feedbackComment.count > 1500).opacity(rating == 0 ? 0.5 : 1)
                    if feedbackError { Text(localized("Не удалось отправить отзыв. Повторите попытку.", "Could not submit feedback. Please retry.", "Fikr yuborilmadi. Qayta urinib ko‘ring.", "Фикр юборилмади. Қайта уриниб кўринг.")).font(.caption).foregroundStyle(.red) }
                }
            }
        }
    }
    private struct TravelCertificateFile: Identifiable { let id = UUID(); let url: URL }
    @MainActor private func shareCertificate(_ certificate: IumrahUmrahCertificate, session: StoredBookingSession) {
        certificateShareError = false
        let page = CGRect(x: 0, y: 0, width: 842, height: 595)
        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            UIColor.black.setFill(); context.cgContext.fill(page)
            UIColor.white.setStroke(); context.cgContext.setLineWidth(1); context.cgContext.stroke(page.insetBy(dx: 24, dy: 24))
            func draw(_ value: String, y: CGFloat, size: CGFloat, weight: UIFont.Weight, color: UIColor = .white, height: CGFloat = 55) {
                let style = NSMutableParagraphStyle(); style.alignment = .center
                (value as NSString).draw(in: CGRect(x: 60, y: y, width: 722, height: height), withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style])
            }
            draw("iumrah", y: 65, size: 42, weight: .bold)
            draw(localized("Памятный сертификат умры", "Umrah memorial certificate", "Umra esdalik sertifikati", "Умра эсдалик сертификати"), y: 155, size: 27, weight: .semibold)
            draw(certificate.name, y: 231, size: 31, weight: .bold, height: 112)
            draw(localized("Пусть Аллах примет вашу умру.", "May Allah accept your Umrah.", "Alloh umrangizni qabul qilsin.", "Аллоҳ умрангизни қабул қилсин."), y: 360, size: 19, weight: .regular)
            draw("\(session.booking.input.startDate) – \(session.booking.input.endDate)", y: 419, size: 15, weight: .medium)
            draw(certificate.id, y: 475, size: 11, weight: .regular, color: UIColor.lightGray)
            draw(localized("Памятный документ iumrah · не официальный религиозный документ", "iumrah keepsake · not an official religious document", "iumrah esdaligi · rasmiy diniy hujjat emas", "iumrah эсдалиги · расмий диний ҳужжат эмас"), y: 513, size: 11, weight: .regular, color: UIColor.lightGray)
        }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("iumrah-certificates", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            let url = directory.appendingPathComponent("iumrah-\(UUID().uuidString).pdf")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            certificateShare = TravelCertificateFile(url: url)
        } catch { certificateShareError = true }
    }
    @MainActor private func sendTravelFeedback(_ id: String) async {
        guard !feedbackSending else { return }; feedbackSending = true; feedbackError = false; defer { feedbackSending = false }
        do { let result = try await bookings.submitTravelFeedback(id: id, rating: rating, comment: feedbackComment); if activeSession?.id == id { feedbackSavedBookingID = id; feedbackSaved = result } }
        catch { if activeSession?.id == id { feedbackError = true } }
    }

    private func tripManagement(_ session: StoredBookingSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: manageSectionTitle, trailing: nil)

            VStack(spacing: 0) {
                Button { selectedBookingID = session.id; bookingPanel = .package } label: {
                    managementRow(icon: "slider.horizontal.3", title: manageTitle, subtitle: manageSubtitle)
                }
                .buttonStyle(.plain)

                managementDivider

                if bookings.canUseBookingCare(session.id) {
                    NavigationLink {
                        BookingChatView(bookingID: session.id)
                    } label: {
                        managementRow(icon: "person.badge.plus", title: addPilgrimTitle, subtitle: addPilgrimSubtitle)
                    }.buttonStyle(.plain)
                } else {
                    Button { chrome.navigate(to: .care) } label: {
                        managementRow(icon: "lock.fill", title: addPilgrimTitle, subtitle: localized("Свяжитесь с поддержкой", "Contact support", "Yordam bilan bog‘laning", "Ёрдам билан боғланинг"))
                    }.buttonStyle(.plain)
                }

                managementDivider

                Button {
                    showZiyarats = true
                } label: {
                    managementRow(icon: "map", title: ziyaratsBookingTitle, subtitle: ziyaratsBookingSubtitle)
                }
                .buttonStyle(.plain)

                managementDivider

                Button {
                    startNewTrip()
                } label: {
                    managementRow(icon: "plus", title: newUmrahTitle, subtitle: newUmrahSubtitle)
                }
                .buttonStyle(.plain)
            }
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
            }
            Button(role: .destructive) { pendingDeleteID = session.id } label: {
                Label(localized("Запросить отмену", "Request cancellation", "Bekor qilishni so‘rash", "Бекор қилишни сўраш"), systemImage: "xmark.circle").font(.subheadline.weight(.semibold)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }.buttonStyle(.plain)
        }
    }

    private var managementDivider: some View {
        Divider().padding(.leading, 65)
    }

    private func managementRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.iumrahRaisedBackground)
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    // MARK: - Other trips

    private func otherTrips(excluding bookingID: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: otherTripsTitle, trailing: nil)

            VStack(spacing: 10) {
                ForEach(activeSessions.filter { $0.id != bookingID }) { session in
                    Button { selectedBookingID = session.id; bookingPanel = .package } label: {
                        compactBookingCard(session)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeleteID = session.id
                        } label: {
                            Label(localized("Запросить отмену", "Request cancellation", "Bekor qilishni so‘rash", "Бекор қилишни сўраш"), systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
    }

    private func compactBookingCard(_ session: StoredBookingSession) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Circle()
                .fill(IumrahBookingStatusVisual.color(for: session.effectiveStatus))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(session.booking.route.originCode) → \(session.booking.route.outboundDestination)")
                        .font(.subheadline.weight(.bold))
                    Text(session.displayBookingNumber)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                Text(L10n.status(session.effectiveStatus, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let name = session.travelerName, !name.isEmpty {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 4) {
                Text(formatPrice(session.booking.perPilgrimUsd))
                    .font(.subheadline.weight(.bold))
                Text(L10n.date(session.booking.input.startDate, settings.language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var explorePackagesButton: some View {
        Button {
            chrome.openHotels(board: .flights)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "suitcase.rolling.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text(explorePackagesTitle)
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var emptyBookingHome: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                bookingEmptyStatusCard

                NavigationLink {
                    IumrahTelegramIntegrationView()
                } label: {
                    IumrahTelegramEntryCard(language: settings.language, large: false)
                }
                .buttonStyle(.plain)

                explorePackagesButton

                emptyConfiguratorCard
                emptyCareCard
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 10)
            .padding(.bottom, 42)
        }
        .background(Color.iumrahPageBackground.ignoresSafeArea(edges: .bottom))
    }

    private var bookingEmptyStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color.primary.opacity(0.055))
                    .frame(width: 58, height: 58)

                Image(systemName: "tray.fill")
                    .font(.system(size: 23, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.primary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(emptyBookingTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(emptyBookingNote)
                    .font(.system(size: 14.5, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.7)
        }
    }


    private var emptyConfiguratorCard: some View {
        emptyShowcaseCard(
            imageName: "IumrahConfiguratorHero",
            imageBackground: .black,
            eyebrow: "Iumrah Configurator",
            badge: localized("5 минут", "5 minutes", "5 daqiqa", "5 дақиқа"),
            title: L10n.text("booking_hero_title", settings.language),
            body: L10n.text("booking_hero_body", settings.language),
            cta: L10n.text("booking_hero_cta", settings.language),
            dark: true,
            imageTopPadding: 0,
            imageHorizontalPadding: 0,
            action: startNewTrip
        )
    }

    private var emptyCareCard: some View {
        emptyShowcaseCard(
            imageName: "IumrahCareShowcaseCard",
            imageBackground: .white,
            eyebrow: "Iumrah Care",
            badge: localized("За вас", "For you", "Siz uchun", "Сиз учун"),
            title: careBookingCardTitle,
            body: careBookingCardBody,
            cta: careBookingCardCTA,
            dark: false,
            imageTopPadding: 0,
            imageHorizontalPadding: 0,
            action: { showCareRequestBuilder = true }
        )
    }

    private func emptyShowcaseCard(
        imageName: String,
        imageBackground: Color,
        eyebrow: String,
        badge: String,
        title: String,
        body: String,
        cta: String,
        dark: Bool,
        imageTopPadding: CGFloat,
        imageHorizontalPadding: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            IumrahHaptics.soft()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    imageBackground

                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(1.08)
                        .padding(.horizontal, imageHorizontalPadding)
                        .padding(.top, imageTopPadding)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 236)
                .clipped()

                VStack(alignment: .leading, spacing: 15) {
                    HStack(spacing: 8) {
                        Label(eyebrow, systemImage: dark ? "slider.horizontal.3" : "heart.fill")
                            .font(.caption.weight(.bold))
                            .tracking(0.45)
                            .foregroundStyle(dark ? Color.white.opacity(0.78) : Color.black.opacity(0.58))
                        Spacer(minLength: 8)
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(dark ? Color.white.opacity(0.82) : Color.black.opacity(0.62))
                            .padding(.horizontal, 10)
                            .frame(height: 29)
                            .background((dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)), in: Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 31, weight: .bold, design: .rounded))
                            .tracking(-0.75)
                            .foregroundStyle(dark ? .white : .black)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(body)
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(dark ? Color.white.opacity(0.68) : Color.black.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 10) {
                        Text(cta)
                    }.frame(maxWidth: .infinity)
                    .font(.headline)
                    .foregroundStyle(dark ? .black : .white)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(dark ? Color.black : Color.white)
            }
            .frame(maxWidth: .infinity, minHeight: 458, alignment: .topLeading)
            .background(dark ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder((dark ? Color.white : Color.black).opacity(dark ? 0.06 : 0.055), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shared helpers

    private func sectionHeader(title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(-0.35)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startNewTrip() {
        journey.resetAfterTripChange()
        chrome.startNewTrip()
    }

    @MainActor
    private func deleteBooking(_ id: String) async {
        do {
            try await bookings.requestCancellation(id: id)
            _ = try? await bookings.loadCheckout(id: id, token: account.bearerToken, force: true)
            cancellationSent = true
            deleteError = nil
            IumrahHaptics.success()
        } catch {
            deleteError = L10n.error(error, settings.language)
            IumrahHaptics.error()
        }
    }

    private func deleteErrorMessage(_ error: Error) -> String {
        switch error {
        case APIError.status(let code) where code == 401 || code == 403:
            return localized(
                "Сессия аккаунта устарела. Обновите Account и повторите удаление.",
                "Your account session expired. Refresh Account and try deleting again.",
                "Akkaunt sessiyasi eskirgan. Account bo‘limini yangilang va o‘chirishni qayta urinib ko‘ring.",
                "Аккаунт сессияси эскирган. Account бўлимини янгиланг ва ўчиришни қайта уриниб кўринг."
            )
        case APIError.server(let code, let message):
            let normalized = message.uppercased()
            if code == 401 || code == 403 || normalized.contains("UNAUTHORIZED") || normalized.contains("TOKEN_EXPIRED") {
                return localized(
                    "Сессия аккаунта устарела. Обновите Account и повторите удаление.",
                    "Your account session expired. Refresh Account and try deleting again.",
                    "Akkaunt sessiyasi eskirgan. Account bo‘limini yangilang va o‘chirishni qayta urinib ko‘ring.",
                    "Аккаунт сессияси эскирган. Account бўлимини янгиланг ва ўчиришни қайта уриниб кўринг."
                )
            }
            return L10n.error(error, settings.language)
        default:
            return L10n.error(error, settings.language)
        }
    }

    private func safeIcon(_ value: String) -> String {
        let icon = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return icon.isEmpty ? "calendar" : icon
    }

    private func compactDate(_ raw: String) -> String {
        guard let date = Self.dayParser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func createdDateText(_ raw: String) -> String? {
        guard let date = Self.isoDate(raw) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }

    private func transitionDate(_ status: String, session: StoredBookingSession) -> String? {
        session.orderedStatusHistory.last(where: { $0.newStatus.lowercased() == status.lowercased() })?.createdAt
    }

    private func lifecycleStageTimestamp(index: Int, session: StoredBookingSession, isCancelled: Bool) -> String? {
        switch index {
        case 0:
            return session.booking.createdAt
        case 1:
            if isCancelled {
                return session.latestStatusTimestamp(matching: ["cancelled"])
                    ?? transitionDate("cancelled", session: session)
                    ?? session.booking.updatedAt
            }
            return session.availabilityStartedAt
                ?? session.latestStatusTimestamp(matching: ["availability_check", "new"])
                ?? session.booking.createdAt
        case 2:
            return session.priceLockStartedAt
                ?? session.latestStatusTimestamp(matching: ["payment_pending"])
                ?? session.booking.updatedAt
        case 3:
            return session.documentsStartedAt
                ?? session.latestStatusTimestamp(matching: ["booking_confirmed", "paid"])
                ?? session.paymentReceivedAt
                ?? session.booking.updatedAt
        case 4:
            return session.latestStatusTimestamp(matching: ["ready_to_travel", "documents_ready"])
                ?? transitionDate("ready_to_travel", session: session)
                ?? session.booking.updatedAt
        case 5:
            return session.latestStatusTimestamp(matching: ["in_trip"])
                ?? transitionDate("in_trip", session: session)
                ?? session.booking.updatedAt
        case 6:
            return session.latestStatusTimestamp(matching: ["completed"])
                ?? transitionDate("completed", session: session)
                ?? session.booking.updatedAt
        default:
            return nil
        }
    }

    private func formatPrice(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = " "
        let value = formatter.string(from: NSNumber(value: amount)) ?? String(Int(amount.rounded()))
        return "\(value) $"
    }

    private func pilgrimCountText(_ count: Int) -> String {
        switch settings.language {
        case .russian:
            let mod10 = count % 10
            let mod100 = count % 100
            if mod10 == 1 && mod100 != 11 { return "\(count) паломник" }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(count) паломника" }
            return "\(count) паломников"
        case .english, .turkish, .indonesian, .malay, .arabic:
            return count == 1 ? "1 pilgrim" : "\(count) pilgrims"
        case .uzbek:
            return "\(count) ziyoratchi"
        case .uzbekCyrillic:
            return "\(count) зиёратчи"
        }
    }


    private static func isoDate(_ raw: String) -> Date? {
        if let date = isoFormatterFractional.date(from: raw) { return date }
        return isoFormatter.date(from: raw)
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dayParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let riyadhDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // MARK: - Copy

    private var activeEyebrow: String { localized("Ваша Umrah", "Your Umrah", "Sizning Umrangiz", "Сизнинг Умрангиз") }
    private var routeTitle: String { localized("Маршрут", "Route", "Yo‘nalish", "Йўналиш") }
    private var dateTitle: String { localized("Даты", "Dates", "Sanalar", "Саналар") }
    private var hotelTitle: String { localized("Отель", "Hotel", "Mehmonxona", "Меҳмонхона") }
    private var priceTitle: String { localized("На паломника", "Per pilgrim", "Bir ziyoratchiga", "Бир зиёратчига") }
    private var openBookingTitle: String { localized("Открыть бронирование", "Open booking", "Bronni ochish", "Бронни очиш") }
    private var openStatusTitle: String { localized("Открыть статус бронирования", "Open booking status", "Bron holatini ochish", "Брон ҳолатини очиш") }
    private var statusTitle: String { localized("Статус бронирования", "Booking status", "Bron holati", "Брон ҳолати") }
    private var cancelledText: String { localized("Отменено", "Cancelled", "Bekor qilingan", "Бекор қилинган") }

    private var createdTitle: String { localized("Пакет создан", "Package created", "Paket yaratildi", "Пакет яратилди") }
    private var createdSubtitle: String { localized("Поездка добавлена в iumrah", "Trip added to iumrah", "Safar iumrah'ga qo‘shildi", "Сафар iumrah'га қўшилди") }

    private var availabilityTitle: String { localized("Проверка наличия", "Availability check", "Mavjudlik tekshiruvi", "Мавжудлик текшируви") }
    private var availabilitySubtitle: String { localized("Подтверждаем перелёт, отель и услуги", "Confirming flight, hotel and services", "Parvoz, mehmonxona va xizmatlar tasdiqlanmoqda", "Парвоз, меҳмонхона ва хизматлар тасдиқланмоқда") }
    private var availabilityCardTitle: String { localized("Проверяем ваш пакет", "Checking your package", "Paketingiz tekshirilmoqda", "Пакетингиз текширилмоқда") }
    private var availabilityCardBody: String { localized("iumrah подтверждает выбранные позиции. Пока от вас ничего не требуется.", "iumrah is confirming the selected items. No action is required from you yet.", "iumrah tanlangan xizmatlarni tasdiqlamoqda. Hozircha sizdan hech narsa talab qilinmaydi.", "iumrah танланган хизматларни тасдиқламоқда. Ҳозирча сиздан ҳеч нарса талаб қилинмайди.") }

    private var paymentStageTitle: String { localized("Оплата и данные паломников", "Payment and pilgrim details", "To‘lov va ziyoratchi ma’lumotlari", "Тўлов ва зиёратчи маълумотлари") }
    private var paymentStageSubtitle: String { localized("Наличие подтверждено · требуется действие", "Availability confirmed · action required", "Mavjudlik tasdiqlandi · amal kerak", "Мавжудлик тасдиқланди · амал керак") }
    private var paymentCardTitle: String { localized("Наличие подтверждено", "Availability confirmed", "Mavjudlik tasdiqlandi", "Мавжудлик тасдиқланди") }
    private var paymentCardBody: String { localized("Проверьте данные паломников и перейдите к оплате, чтобы закрепить бронирование.", "Review pilgrim details and continue to payment to secure the booking.", "Bronni mustahkamlash uchun ziyoratchilar ma’lumotlarini tekshiring va to‘lovga o‘ting.", "Бронни мустаҳкамлаш учун зиёратчилар маълумотларини текширинг ва тўловга ўтинг.") }

    private var confirmedStageTitle: String { localized("Подготавливаем поездку", "Preparing your trip", "Safaringizni tayyorlayapmiz", "Сафарингизни тайёрлаяпмиз") }
    private var confirmedStageSubtitle: String { localized("Оплата подтверждена", "Payment confirmed", "To‘lov tasdiqlandi", "Тўлов тасдиқланди") }
    private var confirmedCardTitle: String { confirmedStageTitle }
    private var confirmedCardBody: String { localized("Готовим документы и услуги. Каждый опубликованный файл доступен в разделе статуса.", "We are preparing documents and services. Each published file is available in the status section.", "Hujjatlar va xizmatlar tayyorlanmoqda. Har bir fayl holat bo‘limida mavjud.", "Ҳужжатлар ва хизматлар тайёрланмоқда. Ҳар бир файл ҳолат бўлимида мавжуд.") }

    private var documentsStageTitle: String { localized("Документы готовы", "Documents ready", "Hujjatlar tayyor", "Ҳужжатлар тайёр") }
    private var documentsStageSubtitle: String { localized("Всё готово к поездке", "Everything is ready for travel", "Safar uchun hammasi tayyor", "Сафар учун ҳаммаси тайёр") }
    private var documentsCardTitle: String { localized("Готово к поездке", "Ready to travel", "Safarga tayyor", "Сафарга тайёр") }
    private var documentsCardBody: String { localized("Проверьте билеты, бронирования и документы перед выездом.", "Review tickets, reservations and travel documents before departure.", "Jo‘nashdan oldin chiptalar, bronlar va hujjatlarni tekshiring.", "Жўнашдан олдин чипталар, бронлар ва ҳужжатларни текширинг.") }

    private var inTripStageTitle: String { localized("Паломник в поездке", "Pilgrim in trip", "Ziyoratchi safarda", "Зиёратчи сафарда") }
    private var inTripStageSubtitle: String { localized("iumrah сопровождает вашу поездку", "iumrah is accompanying your trip", "iumrah safaringizga hamroh", "iumrah сафарингизга ҳамроҳ") }
    private var inTripCardTitle: String { localized("Ваша Umrah идёт", "Your Umrah is underway", "Umrangiz davom etmoqda", "Умрангиз давом этмоқда") }
    private var inTripCardBody: String { localized("Маршрут, отель, расписание и помощь iumrah остаются под рукой на протяжении поездки.", "Your route, hotel, schedule and iumrah support stay close throughout the trip.", "Yo‘nalish, mehmonxona, jadval va iumrah yordami safar davomida doimo yoningizda.", "Йўналиш, меҳмонхона, жадвал ва iumrah ёрдами сафар давомида доимо ёнингизда.") }

    private var completedStageTitle: String { localized("Поездка завершена", "Trip completed", "Safar yakunlandi", "Сафар якунланди") }
    private var completedStageSubtitle: String { localized("История поездки сохранена", "Your trip history is saved", "Safar tarixi saqlandi", "Сафар тарихи сақланди") }
    private var completedCardTitle: String { completedStageTitle }
    private var completedCardBody: String { localized("Бронирование и история поездки останутся доступны в iumrah.", "The booking and trip history remain available in iumrah.", "Bron va safar tarixi iumrah'da saqlanadi.", "Брон ва сафар тарихи iumrah'да сақланади.") }

    private var tripPlanTitle: String { localized("План поездки", "Trip plan", "Safar rejasi", "Сафар режаси") }
    private var tripPlanEmptyText: String { localized("События поездки появятся после подтверждения деталей.", "Trip events will appear after the details are confirmed.", "Tafsilotlar tasdiqlangach safar voqealari paydo bo‘ladi.", "Тафсилотлар тасдиқлангач сафар воқеалари пайдо бўлади.") }
    private var openFullPlanTitle: String { localized("Открыть полное расписание", "Open full schedule", "To‘liq jadvalni ochish", "Тўлиқ жадвални очиш") }

    private var manageSectionTitle: String { localized("Управление поездкой", "Trip management", "Safarni boshqarish", "Сафарни бошқариш") }
    private var bookingScopePickerTitle: String { localized("Поездки", "Trips", "Safarlar", "Сафарлар") }
    private var activeScopeTitle: String { localized("Активные", "Upcoming", "Faol", "Фаол") }
    private var pastScopeTitle: String { localized("Прошлые", "Past", "O‘tgan", "Ўтган") }
    private var explorePackagesTitle: String { localized("Смотреть готовые пакеты", "Explore Packages", "Tayyor paketlarni ko‘rish", "Тайёр пакетларни кўриш") }
    private var noPastBookingsTitle: String { localized("Прошлых поездок пока нет", "No past trips yet", "O‘tgan safarlar hozircha yo‘q", "Ўтган сафарлар ҳозирча йўқ") }
    private var noPastBookingsBody: String { localized("Завершённые и отменённые поездки будут храниться здесь.", "Completed and cancelled trips will appear here.", "Yakunlangan va bekor qilingan safarlar shu yerda ko‘rinadi.", "Якунланган ва бекор қилинган сафарлар шу ерда кўринади.") }
    private var emptyBookingTitle: String { localized("Пока бронирований нет", "No bookings yet", "Hozircha bron yo‘q", "Ҳозирча брон йўқ") }
    private var emptyBookingNote: String { localized("Пока здесь нет активных бронирований. Начните с Конфигуратора или передайте сборку iumrah Care.", "There are no active bookings here yet. Start with the Configurator or let iumrah Care prepare the trip for you.", "Hozircha bu yerda faol bronlar yo‘q. Konfiguratorni oching yoki safarni iumrah Care’ga topshiring.", "Ҳозирча бу ерда фаол бронлар йўқ. Конфигураторни очинг ёки сафарни iumrah Care’га топширинг.") }
    private var careBookingCardTitle: String { localized("Соберите Umrah за меня", "Build my Umrah for me", "Umramni men uchun yig‘ing", "Умрамни мен учун йиғинг") }
    private var careBookingCardBody: String { localized("Расскажите даты, бюджет и пожелания. Iumrah Care соберёт для вас персональный вариант поездки.", "Tell us your dates, budget and preferences. Iumrah Care will prepare a personal Umrah option for you.", "Sanalar, budjet va istaklaringizni ayting. Iumrah Care siz uchun shaxsiy Umra variantini tayyorlaydi.", "Саналар, бюджет ва истакларингизни айтинг. Iumrah Care сиз учун шахсий Умра вариантини тайёрлайди.") }
    private var careBookingCardCTA: String { localized("Собрать мою Umrah", "Build my Umrah", "Mening Umramni yig‘ish", "Менинг Умрамни йиғиш") }
    private var newUmrahTitle: String { localized("Новая Umrah", "New Umrah", "Yangi Umra", "Янги Умра") }
    private var newUmrahSubtitle: String { localized("Собрать новый пакет", "Build a new package", "Yangi paket tuzish", "Янги пакет тузиш") }
    private var addPilgrimTitle: String { localized("Добавить паломника", "Add pilgrim", "Ziyoratchi qo‘shish", "Зиёратчи қўшиш") }
    private var addPilgrimSubtitle: String { localized("Запрос через iumrah Care", "Request via iumrah Care", "iumrah Care orqali so‘rov", "iumrah Care орқали сўров") }
    private var manageTitle: String { localized("Управлять бронированием", "Manage booking", "Bronni boshqarish", "Бронни бошқариш") }
    private var manageSubtitle: String { localized("Отели, данные, услуги и документы", "Hotels, details, services and documents", "Mehmonxona, ma’lumotlar, xizmatlar va hujjatlar", "Меҳмонхона, маълумотлар, хизматлар ва ҳужжатлар") }
    private var otherTripsTitle: String { localized("Другие поездки", "Other trips", "Boshqa safarlar", "Бошқа сафарлар") }
    private var ziyaratsBookingTitle: String { localized("Зияраты", "Ziyarat", "Ziyorat", "Зиёрат") }
    private var ziyaratsBookingSubtitle: String { localized("Маршрут и места посещения", "Route and places to visit", "Yo‘nalish va tashrif joylari", "Йўналиш ва ташриф жойлари") }

    private func localized(_ ru: String, _ en: String, _ uz: String, _ uzCy: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .english, .turkish, .indonesian, .malay, .arabic: return en
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCy
        }
    }
}

private enum BookingLifecyclePhase {
    case availability(Date?)
    case priceLock(Date?)
    case paymentConfirmation(Date?)
    case documents(Date?)

    var isAvailability: Bool {
        if case .availability = self { return true }
        return false
    }

    var deadline: Date? {
        switch self {
        case .availability(let value), .priceLock(let value), .paymentConfirmation(let value), .documents(let value):
            return value
        }
    }

    var symbol: String {
        switch self {
        case .availability: return "clock.badge.checkmark"
        case .priceLock: return "lock.clock"
        case .paymentConfirmation: return "creditcard.and.123"
        case .documents: return "doc.badge.clock"
        }
    }
}

private struct BookingProgressStage {
    let title: String
    let activeSubtitle: String
    let cardTitle: String
    let cardBody: String
}


/// Copy feedback is local to the row and resets independently after 2.5s.
private struct BookingIdentityCopyRow: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let title: String
    let value: String
    let canCopy: Bool
    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    private var copyLabel: String { IumrahFlightCopy.text(settings.language, "Копировать", "Copy", "Nusxalash", "Нусхалаш") }
    private var copiedLabel: String { IumrahFlightCopy.text(settings.language, "Скопировано", "Copied", "Nusxalandi", "Нусхаланди") }
    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline.weight(.semibold)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
                if canCopy {
                    Button {
                        UIPasteboard.general.string = value
                        IumrahHaptics.success()
                        resetTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.18)) { copied = true }
                        resetTask = Task { @MainActor in
                            do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
                            withAnimation(.easeInOut(duration: 0.18)) { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(copied ? Color.green : Color.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(copied ? copiedLabel : copyLabel + " " + title)
                }
        }.frame(minHeight: 44)
        .onChange(of: value) { _, _ in resetTask?.cancel(); copied = false }
        .onDisappear { resetTask?.cancel(); copied = false }
    }
}


// Booking-specific access recovery: verified contact proof, not an account login.
private struct BookingRecoverySheet: View {
    let language: AppSettingsStore.Language
    let onRecovered: (StoredBookingSession) -> Void
    @EnvironmentObject private var bookings: BookingStore
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var contact = ""
    @State private var code = ""
    @State private var channel = "sms"
    @State private var challenge: String?
    @State private var working = false
    @State private var errorMessage = false
    private let contacts = IumrahBookingContactService()
    private let service = BookingService()
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch language { case .russian: return ru; case .uzbek: return uz; case .uzbekCyrillic: return cy; default: return en }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tr("Введите номер бронирования и ранее подтверждённый контакт. Аккаунт не нужен.", "Enter your booking number and previously verified contact. No account needed.", "Bron raqami va avval tasdiqlangan kontaktni kiriting. Hisob shart emas.", "Брон рақами ва аввал тасдиқланган контактни киритинг. Ҳисоб шарт эмас."))
                    TextField(tr("Номер бронирования", "Booking number", "Bron raqami", "Брон рақами"), text: $number).textInputAutocapitalization(.characters).autocorrectionDisabled().disabled(challenge != nil || working)
                    Picker(tr("Способ получения кода", "Get code by", "Kod olish usuli", "Код олиш усули"), selection: $channel) { Text("SMS").tag("sms"); Text("Email").tag("email") }.pickerStyle(.segmented).disabled(challenge != nil || working)
                    TextField(channel == "sms" ? "+998" : "Email", text: $contact).keyboardType(channel == "sms" ? .phonePad : .emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().disabled(challenge != nil || working)
                    if challenge != nil { TextField(tr("Код из сообщения", "Verification code", "Tasdiqlash kodi", "Тасдиқлаш коди"), text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode) }
                    if errorMessage { Text(tr("Не удалось восстановить доступ. Проверьте номер и подтверждённый контакт, затем запросите новый код.", "Could not restore access. Check your booking number and verified contact, then request a new code.", "Kirish tiklanmadi. Raqam va tasdiqlangan kontaktni tekshirib, yangi kod oling.", "Кириш тикланмади. Рақам ва тасдиқланган контактни текшириб, янги код олинг.")).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Button { Task { await advance() } } label: {
                        HStack { Spacer(); if working { ProgressView() } else { Text(challenge == nil ? tr("Получить код", "Get code", "Kod olish", "Код олиш") : tr("Открыть бронирование", "Open booking", "Bronni ochish", "Бронни очиш")) }; Spacer() }
                    }.disabled(working || number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (challenge != nil && code.count != 6))
                    if challenge != nil { Button(tr("Запросить новый код", "Request a new code", "Yangi kod olish", "Янги код олиш")) { challenge = nil; code = ""; errorMessage = false }.disabled(working) }
                }
            }.navigationTitle(tr("Моё бронирование", "My booking", "Mening bronim", "Менинг броним")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Закрыть", "Close", "Yopish", "Ёпиш")) { dismiss() }.disabled(working) } }
        }
    }
    @MainActor private func advance() async {
        guard !working else { return }; working = true; errorMessage = false; defer { working = false }
        do {
            if let challenge {
                let proof: String; let email: String?; let phone: String?
                if channel == "sms" { let result = try await contacts.confirmCode(challengeID: challenge, code: code); proof = result.verificationToken; phone = result.phone; email = nil }
                else { let result = try await contacts.confirmEmailCode(challengeID: challenge, code: code); proof = result.verificationToken; email = result.email; phone = nil }
                let response = try await service.recoverBooking(number: number, channel: channel, proof: proof)
                let session = try bookings.adoptRecoveredBooking(response, email: email, phone: phone)
                onRecovered(session); dismiss()
            } else {
                let result: BookingContactStartResponse
                if channel == "sms" { result = try await contacts.requestCode(phone: contact) }
                else { result = try await contacts.requestEmailCode(email: contact, locale: language.rawValue) }
                challenge = result.challengeID
            }
        } catch { errorMessage = true; challenge = nil; code = "" }
    }
}
