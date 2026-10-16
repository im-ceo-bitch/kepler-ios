import SwiftUI

/// The same guest checkout is used by Hotel First, Flight First and Configurator.
/// It does not sign the visitor into an account or create an account.
struct IumrahBookingConfirmationView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let createBooking: @MainActor (BookingPilgrimProfile) async throws -> StoredBookingSession

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = "+998"
    @State private var verificationCode = ""
    @State private var challengeID: String?
    @State private var verificationProof: String?
    @State private var confirmedPhone: String?
    @State private var savedBooking: StoredBookingSession?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var isCodeStep = false
    @State private var isFinished = false
    @State private var successPulse = false
    @FocusState private var activeField: IdentityField?

    private let verificationService = IumrahBookingContactService()

    private enum IdentityField: Hashable { case firstName, lastName, phone, code }

    private var normalizedPhone: String {
        "+" + phone.filter(\.isNumber)
    }

    private var canRequestCode: Bool {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        lastName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 &&
        normalizedPhone.range(of: "^\\+998[0-9]{9}$", options: .regularExpression) != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if isFinished, let savedBooking {
                    completion(savedBooking)
                } else {
                    identityAnimation
                    introduction
                    passportWarning
                    noPaymentNotice
                    identityFields
                    if isCodeStep { verificationFields }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    nextButton
                }
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 42)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.iumrahPageBackground)
        .navigationTitle(copy("Подтверждение брони", "Booking confirmation", "Bronni tasdiqlash", "Бронни тасдиқлаш", "تأكيد الحجز"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if firstName.isEmpty { firstName = settings.firstName }
            if lastName.isEmpty { lastName = settings.lastName }
            if phone == "+998", !settings.phone.isEmpty { phone = settings.phone }
        }
        .onChange(of: phone) { _, _ in
            if isCodeStep && !isWorking && confirmedPhone == nil {
                // Changing the destination invalidates any previously requested code.
                challengeID = nil
                verificationProof = nil
                verificationCode = ""
                isCodeStep = false
            }
        }
    }

    private var identityAnimation: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.black)
            LoopingVideoView(resource: "iumrah-security-identity", gravity: .resizeAspect)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .frame(height: 208)
        .accessibilityHidden(true)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(copy("Подтвердите данные паломника", "Confirm the pilgrim's details", "Ziyoratchi ma’lumotlarini tasdiqlang", "Зиёратчи маълумотларини тасдиқланг", "تأكيد بيانات المعتمر"))
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text(copy("Это только заявка на бронирование, а не регистрация или вход в аккаунт.",
                      "This is a booking request, not account registration or sign-in.",
                      "Bu akkauntga kirish yoki ro‘yxatdan o‘tish emas, bron so‘rovidir.",
                      "Бу аккаунтга кириш ёки рўйхатдан ўтиш эмас, брон сўровидир.",
                      "هذا طلب حجز فقط، وليس تسجيل حساب أو تسجيل دخول."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var passportWarning: some View {
        Label {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("ВАЖНО: как в загранпаспорте", "IMPORTANT: match your passport", "MUHIM: pasportdagidek", "МУҲИМ: паспортдагидек", "مهم: كما في جواز السفر"))
                    .font(.subheadline.weight(.bold))
                Text(copy("Имя и фамилия должны точно совпадать с загранпаспортом. Ошибки могут повлиять на оформление билетов и документов.",
                          "Enter your first and last name exactly as in your passport. Errors may affect tickets and documents.",
                          "Ism va familiyani xorijga chiqish pasportidagi kabi aniq kiriting.",
                          "Исм ва фамилияни хорижга чиқиш паспортидаги каби аниқ киритинг.",
                          "أدخل الاسم الأول واسم العائلة كما يظهران تمامًا في جواز السفر."))
                    .font(.footnote)
            }
        } icon: {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title2)
        }
        .foregroundStyle(Color.red)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.red.opacity(0.24)))
    }

    private var noPaymentNotice: some View {
        Label {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("Сейчас вы ничего не платите", "No payment is required now", "Hozir hech narsa to‘lamaysiz", "Ҳозир ҳеч нарса тўламайсиз", "لا يلزم الدفع الآن"))
                    .font(.subheadline.weight(.bold))
                Text(copy("Мы создадим запрос и повторно проверим доступность каждого компонента. Оплата потребуется только после подтверждения наличия.",
                          "We will recheck availability of every component. Payment is requested only after availability is confirmed.",
                          "Har bir xizmat mavjudligi qayta tekshiriladi. To‘lov faqat tasdiqdan keyin so‘raladi.",
                          "Ҳар бир хизмат мавжудлиги қайта текширилади. Тўлов фақат тасдиқдан кейин сўралади.",
                          "سنتحقق مجددًا من توفر كل مكوّن. لن يُطلب الدفع إلا بعد تأكيد التوفر."))
                    .font(.footnote)
            }
        } icon: {
            Image(systemName: "creditcard.fill")
                .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .foregroundStyle(Color.primary)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    private var identityFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("01", copy("Имя", "First name", "Ism", "Исм", "الاسم الأول"))
            TextField(copy("Имя в паспорте", "Passport first name", "Pasportdagi ism", "Паспортдаги исм", "الاسم كما في الجواز"), text: $firstName)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($activeField, equals: .firstName)
                .onSubmit { activeField = .lastName }
                .bookingInputStyle()
                .disabled(isCodeStep)

            fieldLabel("02", copy("Фамилия", "Last name", "Familiya", "Фамилия", "اسم العائلة"))
            TextField(copy("Фамилия в паспорте", "Passport last name", "Pasportdagi familiya", "Паспортдаги фамилия", "اسم العائلة كما في الجواز"), text: $lastName)
                .textContentType(.familyName)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($activeField, equals: .lastName)
                .onSubmit { activeField = .phone }
                .bookingInputStyle()
                .disabled(isCodeStep || firstName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)

            fieldLabel("03", copy("Номер телефона", "Phone number", "Telefon raqami", "Телефон рақами", "رقم الهاتف"))
            TextField("+998 90 123 45 67", text: $phone)
                .textContentType(.telephoneNumber)
                .keyboardType(.phonePad)
                .focused($activeField, equals: .phone)
                .environment(\.layoutDirection, .leftToRight)
                .bookingInputStyle()
                .disabled(isCodeStep || lastName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
            Text(copy("SMS-подтверждение доступно для номеров Узбекистана (+998).", "SMS confirmation currently supports Uzbekistan numbers (+998).", "SMS tasdiqlash hozircha O‘zbekiston raqamlari (+998) uchun.", "SMS тасдиқлаш ҳозирча Ўзбекистон рақамлари (+998) учун.", "التحقق عبر الرسائل متاح حاليًا للأرقام الأوزبكية (+998)."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if isCodeStep {
                Button(copy("Изменить данные", "Edit details", "Ma’lumotlarni o‘zgartirish", "Маълумотларни ўзгартириш", "تعديل البيانات")) {
                    challengeID = nil
                    verificationCode = ""
                    isCodeStep = false
                    errorMessage = nil
                }
                .font(.footnote.weight(.semibold))
            }
        }
        .padding(18)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var verificationFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(copy("Введите код из SMS", "Enter your SMS code", "SMS kodini kiriting", "SMS кодини киритинг", "أدخل رمز الرسالة"), systemImage: "message.fill")
                .font(.headline)
            Text(copy("Шестизначный код отправлен на", "A six-digit code was sent to", "6 xonali kod yuborildi:", "6 хонали код юборилди:", "تم إرسال رمز مكوّن من 6 أرقام إلى") + " \(normalizedPhone)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("000000", text: $verificationCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($activeField, equals: .code)
                .environment(\.layoutDirection, .leftToRight)
                .onChange(of: verificationCode) { _, newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    if newValue != digits { verificationCode = digits }
                }
                .bookingInputStyle()
            Button(copy("Отправить код повторно", "Resend code", "Kodni qayta yuborish", "Кодни қайта юбориш", "إعادة إرسال الرمز")) {
                Task { await requestCode() }
            }
            .font(.footnote.weight(.semibold))
            .disabled(isWorking)
        }
        .padding(18)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 24))
    }

    private func fieldLabel(_ number: String, _ title: String) -> some View {
        HStack(spacing: 9) {
            Text(number).font(.caption.monospacedDigit().weight(.bold)).foregroundStyle(.secondary)
            Text(title).font(.subheadline.weight(.semibold))
        }
    }

    private var nextButton: some View {
        Button {
            Task { if isCodeStep { await confirmCodeAndBook() } else { await requestCode() } }
        } label: {
            HStack(spacing: 10) {
                if isWorking { ProgressView().tint(.white) }
                Text(isWorking
                     ? copy("Проверяем…", "Checking…", "Tekshirilmoqda…", "Текширилмоқда…", "جارٍ التحقق…")
                     : isCodeStep
                     ? copy("Подтвердить и забронировать", "Confirm and request booking", "Tasdiqlash va bron qilish", "Тасдиқлаш ва брон қилиш", "تأكيد وطلب الحجز")
                     : copy("Получить SMS-код", "Send SMS code", "SMS kodini olish", "SMS кодини олиш", "إرسال رمز التحقق"))
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 19))
        }
        .buttonStyle(.plain)
        .disabled(isWorking || (isCodeStep ? verificationCode.count != 6 : !canRequestCode))
        .opacity(isWorking || (isCodeStep ? verificationCode.count == 6 : canRequestCode) ? 1 : 0.5)
    }

    @MainActor
    private func requestCode() async {
        guard canRequestCode, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await verificationService.requestCode(phone: normalizedPhone)
            challengeID = result.challengeID
            verificationProof = nil
            confirmedPhone = nil
            verificationCode = ""
            isCodeStep = true
            activeField = .code
            IumrahHaptics.selection()
        } catch {
            errorMessage = error.localizedDescription
            IumrahHaptics.error()
        }
    }

    @MainActor
    private func confirmCodeAndBook() async {
        guard !isWorking, let challengeID, verificationCode.count == 6 else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            // Verify before any booking is created. This is a guest contact check,
            // not registration and not the account's SMS login flow.
            if verificationProof == nil {
                let verification = try await verificationService.confirmCode(challengeID: challengeID, code: verificationCode)
                guard verification.phone == normalizedPhone else { throw IumrahBookingContactError.invalidPhone }
                verificationProof = verification.verificationToken
                confirmedPhone = verification.phone
            }
            guard let verificationProof, confirmedPhone == normalizedPhone else { throw IumrahBookingContactError.invalidPhone }
            let profile = BookingPilgrimProfile(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                telegram: "",
                whatsapp: ""
            )
            let session: StoredBookingSession
            if let savedBooking { session = savedBooking }
            else {
                session = try await createBooking(profile)
                savedBooking = session // retries never create a duplicate booking
            }
            try await verificationService.attachVerifiedPhone(
                verificationToken: verificationProof,
                bookingID: session.id,
                bookingToken: session.accessToken
            )
            settings.firstName = profile.firstName
            settings.lastName = profile.lastName
            settings.phone = confirmedPhone ?? ""
            isFinished = true
            IumrahHaptics.success()
            successPulse = false
        } catch {
            errorMessage = error.localizedDescription
            IumrahHaptics.error()
        }
    }

    private func completion(_ session: StoredBookingSession) -> some View {
        VStack(spacing: 17) {
            ZStack {
                Circle().fill(Color.green.opacity(0.10)).frame(width: 168, height: 168)
                Image(systemName: "checkmark.seal.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.green)
                    .frame(width: 108, height: 108)
                    .scaleEffect(successPulse ? 1 : 0.8)
                    .symbolEffect(.bounce, value: successPulse)
            }
            .padding(.top, 48)
            Text(copy("Заявка на бронь создана!", "Booking request created!", "Bron so‘rovi yaratildi!", "Брон сўрови яратилди!", "تم إنشاء طلب الحجز!"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
            Text(copy("Мы перепроверяем отель, рейсы и услуги. После подтверждения доступности сообщим, как оплатить бронь. Сейчас платить ничего не нужно.",
                      "We are rechecking hotels, flights and services. We will provide payment instructions after availability is confirmed. Nothing is due now.",
                      "Mehmonxona, reyslar va xizmatlar tekshirilmoqda. Mavjudlik tasdiqlangach to‘lov haqida xabar beramiz. Hozir to‘lov yo‘q.",
                      "Меҳмонхона, рейслар ва хизматлар текширилмоқда. Мавжудлик тасдиқлангач тўлов ҳақида хабар берамиз. Ҳозир тўлов йўқ.",
                      "نعيد التحقق من توفر الفنادق والرحلات والخدمات. ستصلك تعليمات الدفع بعد تأكيد التوفر، ولا تدفع شيئًا الآن."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(session.displayBookingNumber)
                .font(.title3.monospacedDigit().weight(.bold))
            IumrahTelegramConnectCard(session: session, style: .standard)
            NavigationLink {
                BookingDetailView(bookingID: session.id)
            } label: {
                Label(copy("Открыть бронирование", "Open booking", "Bronni ochish", "Бронни очиш", "عرض الحجز"), systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .task {
            guard !reduceMotion, !successPulse else { return }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                successPulse = true
            }
        }
    }


    // Guest checkout has its own complete copy instead of relying on English fallbacks
    // from legacy per-screen translation switches.
    private static let turkish: [String: String] = [
        "Booking confirmation": "Rezervasyon onayı",
        "Confirm the pilgrim's details": "Umre yolcusunun bilgilerini doğrulayın",
        "This is a booking request, not account registration or sign-in.": "Bu, hesap açma veya giriş işlemi değil, rezervasyon talebidir.",
        "IMPORTANT: match your passport": "ÖNEMLİ: Pasaportunuzla aynı olmalı",
        "Enter your first and last name exactly as in your passport. Errors may affect tickets and documents.": "Adınızı ve soyadınızı pasaportunuzda yazdığı gibi girin. Hatalar biletleri ve belgeleri etkileyebilir.",
        "No payment is required now": "Şimdi ödeme yapmanız gerekmiyor",
        "We will recheck availability of every component. Payment is requested only after availability is confirmed.": "Tüm hizmetlerin müsaitliğini yeniden kontrol edeceğiz. Ödeme yalnızca müsaitlik onaylandıktan sonra istenir.",
        "First name": "Ad",
        "Passport first name": "Pasaporttaki adınız",
        "Last name": "Soyad",
        "Passport last name": "Pasaporttaki soyadınız",
        "Phone number": "Telefon numarası",
        "SMS confirmation currently supports Uzbekistan numbers (+998).": "SMS doğrulaması şu anda Özbekistan numaralarını (+998) destekliyor.",
        "Edit details": "Bilgileri düzenle",
        "Enter your SMS code": "SMS kodunu girin",
        "A six-digit code was sent to": "Altı haneli kod gönderildi:",
        "Resend code": "Kodu yeniden gönder",
        "Checking…": "Kontrol ediliyor…",
        "Confirm and request booking": "Onayla ve rezervasyon talep et",
        "Send SMS code": "SMS kodu gönder",
        "Booking request created!": "Rezervasyon talebi oluşturuldu!",
        "We are rechecking hotels, flights and services. We will provide payment instructions after availability is confirmed. Nothing is due now.": "Otel, uçuş ve hizmetlerin müsaitliğini yeniden kontrol ediyoruz. Onaylandıktan sonra ödeme bilgilerini ileteceğiz. Şimdi ödeme yapmanıza gerek yok.",
        "Open booking": "Rezervasyonu aç",
    ]
    private static let indonesian: [String: String] = [
        "Booking confirmation": "Konfirmasi pemesanan",
        "Confirm the pilgrim's details": "Konfirmasi data jemaah",
        "This is a booking request, not account registration or sign-in.": "Ini adalah permintaan pemesanan, bukan pendaftaran atau masuk akun.",
        "IMPORTANT: match your passport": "PENTING: sesuai paspor",
        "Enter your first and last name exactly as in your passport. Errors may affect tickets and documents.": "Masukkan nama depan dan belakang persis seperti di paspor. Kesalahan dapat memengaruhi tiket dan dokumen.",
        "No payment is required now": "Belum perlu membayar sekarang",
        "We will recheck availability of every component. Payment is requested only after availability is confirmed.": "Kami akan memeriksa kembali ketersediaan setiap komponen. Pembayaran hanya diminta setelah ketersediaan dikonfirmasi.",
        "First name": "Nama depan",
        "Passport first name": "Nama depan sesuai paspor",
        "Last name": "Nama belakang",
        "Passport last name": "Nama belakang sesuai paspor",
        "Phone number": "Nomor telepon",
        "SMS confirmation currently supports Uzbekistan numbers (+998).": "Konfirmasi SMS saat ini hanya tersedia untuk nomor Uzbekistan (+998).",
        "Edit details": "Ubah data",
        "Enter your SMS code": "Masukkan kode SMS",
        "A six-digit code was sent to": "Kode enam digit dikirim ke",
        "Resend code": "Kirim ulang kode",
        "Checking…": "Memeriksa…",
        "Confirm and request booking": "Konfirmasi dan ajukan pemesanan",
        "Send SMS code": "Kirim kode SMS",
        "Booking request created!": "Permintaan pemesanan berhasil dibuat!",
        "We are rechecking hotels, flights and services. We will provide payment instructions after availability is confirmed. Nothing is due now.": "Kami sedang memeriksa kembali hotel, penerbangan, dan layanan. Instruksi pembayaran akan diberikan setelah ketersediaan dikonfirmasi. Belum ada pembayaran sekarang.",
        "Open booking": "Buka pemesanan",
    ]
    private static let malay: [String: String] = [
        "Booking confirmation": "Pengesahan tempahan",
        "Confirm the pilgrim's details": "Sahkan maklumat jemaah",
        "This is a booking request, not account registration or sign-in.": "Ini permintaan tempahan, bukan pendaftaran atau log masuk akaun.",
        "IMPORTANT: match your passport": "PENTING: ikut pasport anda",
        "Enter your first and last name exactly as in your passport. Errors may affect tickets and documents.": "Masukkan nama pertama dan nama keluarga sama seperti dalam pasport. Kesilapan boleh menjejaskan tiket dan dokumen.",
        "No payment is required now": "Tiada bayaran diperlukan sekarang",
        "We will recheck availability of every component. Payment is requested only after availability is confirmed.": "Kami akan menyemak semula ketersediaan setiap komponen. Bayaran hanya diminta selepas ketersediaan disahkan.",
        "First name": "Nama pertama",
        "Passport first name": "Nama pertama dalam pasport",
        "Last name": "Nama keluarga",
        "Passport last name": "Nama keluarga dalam pasport",
        "Phone number": "Nombor telefon",
        "SMS confirmation currently supports Uzbekistan numbers (+998).": "Pengesahan SMS buat masa ini hanya menyokong nombor Uzbekistan (+998).",
        "Edit details": "Ubah maklumat",
        "Enter your SMS code": "Masukkan kod SMS",
        "A six-digit code was sent to": "Kod enam digit dihantar ke",
        "Resend code": "Hantar semula kod",
        "Checking…": "Menyemak…",
        "Confirm and request booking": "Sahkan dan mohon tempahan",
        "Send SMS code": "Hantar kod SMS",
        "Booking request created!": "Permintaan tempahan berjaya dibuat!",
        "We are rechecking hotels, flights and services. We will provide payment instructions after availability is confirmed. Nothing is due now.": "Kami sedang menyemak semula hotel, penerbangan dan perkhidmatan. Arahan bayaran diberikan selepas ketersediaan disahkan. Tiada bayaran diperlukan sekarang.",
        "Open booking": "Buka tempahan",
    ]
    private func copy(_ ru: String, _ en: String, _ uz: String, _ uzCy: String, _ ar: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .english: return en
        case .arabic: return ar
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCy
        case .turkish: return Self.turkish[en] ?? TurkishLocalization.phrase(en)
        case .indonesian: return Self.indonesian[en] ?? IndonesianLocalization.phrase(en)
        case .malay: return Self.malay[en] ?? MalayLocalization.phrase(en)
        }
    }
}

private struct IumrahBookingInputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 15)
            .frame(height: 54)
            .background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension View {
    func bookingInputStyle() -> some View { modifier(IumrahBookingInputStyle()) }
}
