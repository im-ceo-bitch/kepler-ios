import SwiftUI

/// Passwordless access to a previously created trip. The UI never requests account
/// registration. Only the server can issue a session; booking proofs never grant
/// access to passports or payments by themselves.
struct IumrahBookingAccessCard: View {
    @EnvironmentObject private var account: IumrahAccountStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var settings: AppSettingsStore
    let bookingID: String?

    private enum Channel: String { case email, sms }
    private enum Mode { case existing, booking }
    @State private var channel: Channel = .email
    @State private var email = ""
    @State private var phone = "+998"
    @State private var code = ""
    @State private var challenge: String?
    @State private var mode: Mode = .existing
    @State private var target: StoredBookingSession?
    @State private var verifiedSession: IumrahAccountAuthResponse?
    @State private var busy = false
    @State private var expanded = false
    @State private var message: String?
    @State private var restored = false
    private let service = IumrahAccountService()

    private var contact: String {
        channel == .email ? email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : "+" + phone.filter(\.isNumber)
    }
    private var valid: Bool {
        if channel == .email { return contact.range(of: "^[^\\s@]+@[^\\s@.]+(\\.[^\\s@.]+)+$", options: .regularExpression) != nil }
        return contact.range(of: "^\\+998[0-9]{9}$", options: .regularExpression) != nil
    }
    private var localBooking: StoredBookingSession? { bookingID.flatMap { bookings.booking(id: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                if expanded && challenge == nil && email.isEmpty && phone == "+998" { prefill() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: bookingID == nil ? "ticket" : "lock.shield")
                        .font(.title2).frame(width: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bookingID == nil ? tr("Find booking", "Найти бронирование", "Bronni topish", "Бронни топиш") : tr("Confirm access to your trip", "Подтвердить доступ к поездке", "Safarga kirishni tasdiqlash", "Сафарга киришни тасдиқлаш"))
                            .font(.headline)
                        Text(tr("Use the email or phone from your booking.", "Используйте почту или номер телефона из бронирования.", "Brondagi email yoki telefon raqamidan foydalaning.", "Брондаги email ёки телефон рақамидан фойдаланинг."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                }.foregroundStyle(.primary)
            }.buttonStyle(.plain)
            if expanded {
                if restored {
                    Label(tr("Access restored", "Доступ восстановлен", "Kirish tiklandi", "Кириш тикланди"), systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold))
                } else {
                    Picker(tr("Contact", "Контакт", "Aloqa", "Алоқа"), selection: $channel) {
                        Text("Email").tag(Channel.email)
                        Text("SMS").tag(Channel.sms)
                    }.pickerStyle(.segmented).disabled(challenge != nil || busy)
                    if channel == .email {
                        TextField("name@example.com", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(14).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 14)).disabled(challenge != nil || busy)
                    } else {
                        TextField("+998 90 123 45 67", text: $phone).textContentType(.telephoneNumber).keyboardType(.phonePad)
                            .padding(14).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 14)).disabled(challenge != nil || busy)
                    }
                    if challenge != nil {
                        Text(tr("Enter the six-digit code", "Введите шестизначный код", "Olti xonali kodni kiriting", "Олти хонали кодни киритинг")).font(.subheadline)
                        TextField("000000", text: $code).textContentType(.oneTimeCode).keyboardType(.numberPad)
                            .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(6)) }
                            .padding(14).background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 14)).disabled(busy || verifiedSession != nil)
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Button {
                        Task { await proceed() }
                    } label: {
                        HStack {
                            if busy { ProgressView().tint(.white) }
                            Text(challenge == nil ? tr("Send code", "Получить код", "Kod olish", "Код олиш") : tr("Confirm access", "Подтвердить доступ", "Kirishni tasdiqlash", "Киришни тасдиқлаш"))
                        }
                    }.buttonStyle(IumrahPrimaryButtonStyle()).disabled(busy || (challenge == nil ? !valid : code.count != 6))
                    if challenge != nil {
                        Button(tr("Change contact or resend code", "Изменить контакт или отправить код заново", "Aloqani o‘zgartirish yoki kodni qayta yuborish", "Алоқани ўзгартириш ёки кодни қайта юбориш")) {
                            challenge = nil; code = ""; message = nil; verifiedSession = nil; target = nil
                        }.font(.footnote).disabled(busy)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).iumrahCard()
    }

    private func prefill() {
        let local = localBooking ?? bookings.sessions.first
        if let value = local?.verifiedBookingEmail, !value.isEmpty { email = value; channel = .email }
        else if let value = local?.verifiedBookingPhone, !value.isEmpty { phone = value; channel = .sms }
    }

    private func matches(_ booking: StoredBookingSession) -> Bool {
        IumrahSeamlessBookingPolicy.matchesContact(email: booking.verifiedBookingEmail, phone: booking.verifiedBookingPhone, channel: channel.rawValue, contact: contact)
    }

    private func isMissingProfile(_ error: Error) -> Bool {
        if case APIError.server(let status, let reason) = error {
            return status == 404 && ["EMAIL_ACCOUNT_NOT_FOUND", "PHONE_ACCOUNT_NOT_FOUND"].contains(reason.uppercased())
        }
        return false
    }

    @MainActor private func proceed() async {
        guard !busy, valid else { return }
        busy = true; message = nil
        defer { busy = false }
        let locale = settings.language.rawValue
        do {
            if challenge == nil {
                let explicit = localBooking
                if let explicit, (explicit.verifiedBookingEmail != nil || explicit.verifiedBookingPhone != nil), !matches(explicit) {
                    message = tr("Use the contact you confirmed for this booking.", "Укажите контакт, подтверждённый для этого бронирования.", "Ushbu bron uchun tasdiqlangan aloqani kiriting.", "Ушбу брон учун тасдиқланган алоқани киритинг.")
                    return
                }
                target = explicit ?? bookings.sessions.first(where: { !$0.accessToken.isEmpty && matches($0) })
                do {
                    if channel == .email { challenge = try await service.startEmailLogin(email: contact, locale: locale).challengeID }
                    else { challenge = try await service.startPhoneLogin(phone: contact, locale: locale).challengeID }
                    mode = .existing
                } catch {
                    // Older server: only a locally held booking proof can establish
                    // the passwordless profile. Never create profiles on recovery alone.
                    guard isMissingProfile(error), let target, !target.accessToken.isEmpty else { throw error }
                    if channel == .email { challenge = try await service.startActivationEmail(bookingID: target.id, bookingToken: target.accessToken, email: contact, locale: locale).challengeID }
                    else { challenge = try await service.startActivationSMS(bookingID: target.id, bookingToken: target.accessToken, phone: contact, locale: locale).challengeID }
                    mode = .booking
                }
                return
            }
            guard let challenge, code.count == 6 else { return }
            let auth: IumrahAccountAuthResponse
            if let verifiedSession { auth = verifiedSession }
            else {
                switch (mode, channel) {
                case (.existing, .email): auth = try await service.confirmEmailLogin(challengeID: challenge, code: code, locale: locale)
                case (.existing, .sms): auth = try await service.confirmPhoneLogin(challengeID: challenge, code: code, locale: locale)
                case (.booking, .email):
                    guard let target else { throw APIError.missingBookingToken }
                    auth = try await service.confirmActivationEmail(bookingID: target.id, bookingToken: target.accessToken, challengeID: challenge, code: code, locale: locale)
                case (.booking, .sms):
                    guard let target else { throw APIError.missingBookingToken }
                    auth = try await service.confirmActivationSMS(bookingID: target.id, bookingToken: target.accessToken, challengeID: challenge, code: code, locale: locale)
                }
                verifiedSession = auth // retry linking without reusing a consumed OTP
            }
            var link: IumrahAccountLinkBookingResponse?
            if let target, !target.accessToken.isEmpty {
                let result = try await service.linkBooking(bookingID: target.id, bookingToken: target.accessToken, token: auth.session.token)
                guard IumrahSeamlessBookingPolicy.sameIdentity(result.pilgrimID, auth.account.iumrahID) else { throw APIError.invalidResponse }
                link = result
            } else if let bookingID {
                _ = try await service.tripDetail(bookingID: bookingID, token: auth.session.token)
            }
            _ = await account.acceptVerifiedSession(auth, locale: locale)
            bookings.setAccountToken(account.bearerToken, owner: account.iumrahID)
            if let target, let link { bookings.adoptVerifiedBooking(target, link: link) }
            await bookings.restoreAccountTrips(token: auth.session.token)
            if let bookingID { _ = try? await bookings.loadCheckout(id: bookingID, token: auth.session.token, force: true) }
            restored = true; verifiedSession = nil; code = ""; self.challenge = nil
            IumrahHaptics.success()
        } catch {
            message = isMissingProfile(error) ? tr("No accessible booking found for this contact. Check it or contact support.", "Не удалось найти поездку по этому контакту. Проверьте данные или обратитесь в поддержку.", "Bu aloqa bo‘yicha safar topilmadi. Ma’lumotni tekshiring yoki yordamga murojaat qiling.", "Бу алоқа бўйича сафар топилмади. Маълумотни текширинг ёки ёрдамга мурожаат қилинг.") : L10n.error(error, settings.language)
            IumrahHaptics.error()
        }
    }

    private func tr(_ en: String, _ ru: String, _ uz: String, _ cy: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        case .turkish: return TurkishLocalization.phrase(en)
        case .arabic: return ArabicLocalization.phrase(en)
        case .indonesian: return IndonesianLocalization.phrase(en)
        case .malay: return MalayLocalization.phrase(en)
        case .english: return en
        }
    }
}
