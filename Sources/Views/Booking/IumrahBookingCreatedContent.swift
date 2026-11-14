import SwiftUI
import AudioToolbox

/// Only verified and successfully attached contacts are supplied by guest checkout.
enum IumrahBookingNotificationContact {
    case sms(String)
    case email(String)

    var value: String {
        switch self { case .sms(let value), .email(let value): return value }
    }
    var isEmail: Bool {
        if case .email = self { return true }
        return false
    }
}

struct IumrahBookingCreatedContent: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    let session: StoredBookingSession
    var contact: IumrahBookingNotificationContact? = nil

    @State private var ringVisible = false
    @State private var tickVisible = false
    @State private var didPlay = false
    @State private var cardLift = false

    private var current: StoredBookingSession { bookings.booking(id: session.id) ?? session }

    var body: some View {
        VStack(spacing: 20) {
            bookingCard
            confirmation
            availability
            notificationChannels
            nextSteps
        }
        .frame(maxWidth: .infinity)
        .task { await animateConfirmation() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled && current.isCheckingAvailability {
                await bookings.refreshCreatedBookingStatus(id: session.id)
                guard current.isCheckingAvailability else { break }
                do { try await Task.sleep(for: .seconds(20)) } catch { break }
            }
        }
        .accessibilityIdentifier("iumrah.booking.created")
    }

    private var bookingCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("iumrah")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                Spacer(minLength: 8)
                if let number = current.bookingNumber, number > 0 {
                    Text("#" + String(format: "%04d", number))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)

            IumrahBookingDomeAnimation()
                .frame(height: 108)
                .clipped()
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(.package))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                        Text("\(current.booking.input.travelers.totalPeople) · \(t(.pilgrims))")
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(t(.total))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                        Text(current.booking.totalUsd, format: .currency(code: "USD"))
                            .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                HStack {
                    if let id = current.displayPilgrimID {
                        Text("iumrah ID · \(id)").monospacedDigit()
                    }
                    Spacer(minLength: 4)
                    Text(t(.perPerson) + " " + current.booking.perPilgrimUsd.formatted(.currency(code: "USD")))
                        .multilineTextAlignment(.trailing)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.70))
            }
            .padding(18)
        }
        .foregroundStyle(.white)
        .background(Color(red: 0.035, green: 0.035, blue: 0.04), in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.09), lineWidth: 1) }
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .offset(y: cardLift ? -3 : 0)
        .accessibilityElement(children: .combine)
    }

    private var confirmation: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .trim(from: 0, to: ringVisible ? 1 : 0)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Path { path in
                    path.move(to: CGPoint(x: 17, y: 32))
                    path.addLine(to: CGPoint(x: 28, y: 43))
                    path.addLine(to: CGPoint(x: 47, y: 22))
                }
                .trim(from: 0, to: tickVisible ? 1 : 0)
                .stroke(.primary, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            Text(t(.created))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(t(current.isCheckingAvailability ? .noPayment : .updatedBody))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var availability: some View {
        VStack(alignment: .leading, spacing: 10) {
            if current.isCheckingAvailability {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = current.availabilityEstimateDeadline.map {
                        IumrahBookingAvailabilityEstimate.remaining(until: $0, now: context.date)
                    }
                    let delayed = remaining == 0
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(delayed ? .delayed : .checking))
                                .font(.subheadline.weight(.semibold))
                            if let remaining, remaining > 0 {
                                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                                    .font(.system(size: 32, weight: .semibold, design: .rounded).monospacedDigit())
                                    .contentTransition(.numericText())
                                    .accessibilityLabel(t(.estimate))
                            } else if remaining == nil {
                                Text(t(.estimate)).font(.headline)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "clock")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    if let remaining, remaining > 0 {
                        ProgressView(value: Double(remaining), total: IumrahBookingAvailabilityEstimate.duration)
                            .tint(.primary)
                            .accessibilityHidden(true)
                    }
                    Text(t(delayed ? .delayedBody : .estimateBody))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label(t(.updated), systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                Text(t(.updatedBody))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private var notificationChannels: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t(.notifications)).font(.headline).accessibilityAddTraits(.isHeader)
            if let contact {
                HStack(spacing: 12) {
                    Image(systemName: contact.isEmail ? "envelope" : "message")
                        .font(.title3.weight(.medium))
                        .frame(width: 42, height: 42)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.isEmail ? t(.email) : "SMS").font(.subheadline.weight(.semibold))
                        Text(contact.value).font(.footnote).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .accessibilityLabel(t(.verified))
                }
                Text(t(.contactBody))
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
            }
            IumrahTelegramConnectCard(session: current, style: .confirmation)
            Text(t(.channelsBody))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private var nextSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t(.next)).font(.headline).accessibilityAddTraits(.isHeader)
            step("1", t(.checking), t(.checkBody))
            step("2", t(.payment), t(.paymentBody))
            step("3", t(.documents), t(.documentsBody))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }

    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.caption.weight(.semibold).monospacedDigit())
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor private func animateConfirmation() async {
        guard !didPlay else { return }
        if reduceMotion {
            ringVisible = true
            tickVisible = true
        } else {
            withAnimation(.easeOut(duration: 0.36)) { ringVisible = true }
            do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
            withAnimation(.easeOut(duration: 0.24)) { tickVisible = true; cardLift = true }
        }
        guard !Task.isCancelled else { return }
        didPlay = true
        IumrahHaptics.success()
        IumrahBookingCreatedSound.play()
        if !reduceMotion {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { cardLift = false }
        }
    }

    private enum Copy: Int {
        case package, pilgrims, total, perPerson, created, noPayment, checking, estimate, estimateBody, delayed, delayedBody, updated, updatedBody, notifications, email, verified, contactBody, channelsBody, next, checkBody, payment, paymentBody, documents, documentsBody
    }

    private func t(_ key: Copy) -> String {
        let values: [String]
        switch settings.language {
        case .russian:
            values = ["Индивидуальная умра", "паломники", "Стоимость пакета", "На человека:", "Бронирование создано", "Сейчас ничего оплачивать не нужно. Цена может измениться при проверке наличия.", "Проверяем доступность", "Около 30 минут", "Обычно подтверждаем наличие примерно за 30 минут. Иногда проверка занимает больше времени. Уведомим вас, когда она завершится.", "Проверка продолжается", "Проверка занимает больше времени, чем обычно. Бронирование сохранено. Мы сообщим о результате.", "Статус обновился", "Откройте бронирование, чтобы узнать актуальный статус и дальнейшие действия.", "Ваши уведомления", "Электронная почта", "Контакт подтверждён", "Этот контакт подключён к бронированию. Уведомление о создании и дальнейших изменениях отправляется по выбранному каналу.", "О каждом изменении статуса сообщим по подключённым каналам. Вы можете закрыть приложение.", "Что дальше?", "Проверяем отели, рейсы и остальные услуги.", "Оплата бронирования", "Сообщим, когда можно будет оплатить поездку.", "Подготовка документов", "После оплаты и подтверждения подготовим документы и информацию о поездке."]
        case .uzbek:
            values = ["Individual umra", "ziyoratchilar", "Paket narxi", "Bir kishi uchun:", "Bron yaratildi", "Hozir to‘lov talab qilinmaydi. Tekshiruvda narx o‘zgarishi mumkin.", "Mavjudlikni tekshiryapmiz", "Taxminan 30 daqiqa", "Odatda mavjudlik taxminan 30 daqiqada tasdiqlanadi. Ba’zan ko‘proq vaqt ketadi. Yakunlangach xabar beramiz.", "Tekshiruv davom etmoqda", "Tekshiruv odatdagidan uzoqroq davom etmoqda. Bron saqlandi. Natijani xabar qilamiz.", "Holat yangilandi", "Joriy holat va keyingi qadamlar uchun bronni oching.", "Bildirishnomalaringiz", "Elektron pochta", "Kontakt tasdiqlangan", "Bu kontakt bronga ulandi. Bron yaratilishi va keyingi o‘zgarishlar haqida tanlangan kanal orqali xabar yuboriladi.", "Har bir holat o‘zgarishi haqida ulangan kanallar orqali xabar beramiz. Ilovani yopishingiz mumkin.", "Keyin nima?", "Mehmonxonalar, reyslar va xizmatlarni tekshiramiz.", "Bron uchun to‘lov", "Safar uchun to‘lov ochilganda xabar beramiz.", "Hujjatlarni tayyorlash", "To‘lov va tasdiqdan keyin safar hujjatlari va ma’lumotlarini tayyorlaymiz."]
        case .uzbekCyrillic:
            values = ["Индивидуал умра", "зиёратчилар", "Пакет нархи", "Бир киши учун:", "Брон яратилди", "Ҳозир тўлов талаб қилинмайди. Текширувда нарх ўзгариши мумкин.", "Мавжудликни текширяпмиз", "Тахминан 30 дақиқа", "Одатда мавжудлик тахминан 30 дақиқада тасдиқланади. Баъзан кўпроқ вақт кетади. Якунлангач хабар берамиз.", "Текширув давом этмоқда", "Текширув одатдагидан узоқроқ давом этмоқда. Брон сақланди. Натижани хабар қиламиз.", "Ҳолат янгиланди", "Жорий ҳолат ва кейинги қадамлар учун бронни очинг.", "Билдиришномаларингиз", "Электрон почта", "Контакт тасдиқланган", "Бу контакт бронга уланди. Брон яратилиши ва кейинги ўзгаришлар ҳақида танланган канал орқали хабар юборилади.", "Ҳар бир ҳолат ўзгариши ҳақида уланган каналлар орқали хабар берамиз. Иловани ёпишингиз мумкин.", "Кейин нима?", "Меҳмонхоналар, рейслар ва хизматларни текширамиз.", "Брон учун тўлов", "Сафар учун тўлов очилганда хабар берамиз.", "Ҳужжатларни тайёрлаш", "Тўлов ва тасдиқдан кейин сафар ҳужжатлари ва маълумотларини тайёрлаймиз."]
        case .arabic:
            values = ["عمرة فردية", "معتمرون", "سعر الباقة", "لكل شخص:", "تم إنشاء الحجز", "لا يلزم الدفع الآن. قد يتغير السعر عند التحقق من التوفر.", "نتحقق من التوفر", "نحو 30 دقيقة", "يستغرق التحقق عادة نحو 30 دقيقة وقد يستغرق وقتًا أطول أحيانًا. سنخبرك عند اكتماله.", "التحقق مستمر", "يستغرق التحقق وقتًا أطول من المعتاد. حجزك محفوظ وسنخبرك بالنتيجة.", "تم تحديث الحالة", "افتح الحجز لمعرفة الحالة الحالية والخطوات التالية.", "إشعاراتك", "البريد الإلكتروني", "تم التحقق من جهة الاتصال", "تم ربط جهة الاتصال بالحجز. تُرسل تحديثات الإنشاء والحالة عبر القناة المختارة.", "سنبلغك بكل تغيير في الحالة عبر القنوات المرتبطة. يمكنك إغلاق التطبيق.", "ما التالي؟", "نتحقق من الفنادق والرحلات والخدمات.", "دفع الحجز", "سنخبرك عند إتاحة الدفع.", "إعداد الوثائق", "بعد الدفع والتأكيد سنجهز وثائق الرحلة ومعلوماتها."]
        case .turkish:
            values = ["Bireysel umre", "yolcu", "Paket fiyatı", "Kişi başı:", "Rezervasyon oluşturuldu", "Şimdi ödeme gerekmez. Müsaitlik kontrolünde fiyat değişebilir.", "Müsaitlik kontrol ediliyor", "Yaklaşık 30 dakika", "Kontrol genellikle yaklaşık 30 dakika sürer; bazen daha uzun sürebilir. Tamamlandığında haber vereceğiz.", "Kontrol devam ediyor", "Kontrol normalden uzun sürüyor. Rezervasyonunuz kayıtlı; sonucu bildireceğiz.", "Durum güncellendi", "Güncel durum ve sonraki adımlar için rezervasyonu açın.", "Bildirimleriniz", "E-posta", "İletişim bilgisi doğrulandı", "Bu iletişim bilgisi rezervasyona bağlandı. Oluşturma ve durum güncellemeleri seçilen kanaldan gönderilir.", "Her durum değişikliğini bağlı kanallardan bildireceğiz. Uygulamayı kapatabilirsiniz.", "Sırada ne var?", "Otelleri, uçuşları ve hizmetleri kontrol ediyoruz.", "Rezervasyon ödemesi", "Ödeme açıldığında haber vereceğiz.", "Belgelerin hazırlanması", "Ödeme ve onaydan sonra seyahat belgelerini hazırlayacağız."]
        case .indonesian:
            values = ["Umrah individu", "jemaah", "Harga paket", "Per orang:", "Pemesanan dibuat", "Belum perlu membayar. Harga dapat berubah saat pemeriksaan ketersediaan.", "Memeriksa ketersediaan", "Sekitar 30 menit", "Pemeriksaan biasanya sekitar 30 menit, terkadang lebih lama. Kami akan memberi tahu setelah selesai.", "Pemeriksaan berlanjut", "Pemeriksaan lebih lama dari biasanya. Pemesanan tersimpan; kami akan memberi tahu hasilnya.", "Status diperbarui", "Buka pemesanan untuk melihat status dan langkah berikutnya.", "Notifikasi Anda", "Email", "Kontak terverifikasi", "Kontak ini terhubung ke pemesanan. Pembaruan dikirim melalui kanal yang dipilih.", "Kami akan memberi tahu setiap perubahan status melalui kanal terhubung. Anda dapat menutup aplikasi.", "Apa selanjutnya?", "Kami memeriksa hotel, penerbangan, dan layanan.", "Pembayaran pemesanan", "Kami akan memberi tahu saat pembayaran tersedia.", "Persiapan dokumen", "Setelah pembayaran dan konfirmasi, kami menyiapkan dokumen perjalanan."]
        case .malay:
            values = ["Umrah individu", "jemaah", "Harga pakej", "Seorang:", "Tempahan dibuat", "Tiada bayaran diperlukan sekarang. Harga mungkin berubah semasa semakan ketersediaan.", "Menyemak ketersediaan", "Kira-kira 30 minit", "Semakan biasanya mengambil kira-kira 30 minit, kadangkala lebih lama. Kami akan memaklumkan apabila selesai.", "Semakan diteruskan", "Semakan mengambil masa lebih lama. Tempahan disimpan; kami akan memaklumkan hasilnya.", "Status dikemas kini", "Buka tempahan untuk melihat status dan langkah seterusnya.", "Pemberitahuan anda", "E-mel", "Hubungan disahkan", "Hubungan ini dipautkan kepada tempahan. Kemas kini dihantar melalui saluran yang dipilih.", "Kami akan memaklumkan setiap perubahan status melalui saluran yang dipautkan. Anda boleh menutup aplikasi.", "Apa seterusnya?", "Kami menyemak hotel, penerbangan dan perkhidmatan.", "Bayaran tempahan", "Kami akan memaklumkan apabila bayaran tersedia.", "Penyediaan dokumen", "Selepas bayaran dan pengesahan, kami menyediakan dokumen perjalanan."]
        case .english:
            values = ["Private Umrah", "pilgrims", "Package total", "Per person:", "Booking created", "No payment is required now. The price may change during the availability check.", "Checking availability", "About 30 minutes", "Availability is usually confirmed in about 30 minutes. Sometimes it takes longer. We will notify you when the check is complete.", "Still checking", "The check is taking longer than usual. Your booking is saved. We will notify you of the result.", "Status updated", "Open your booking to see the latest status and next steps.", "Your notifications", "Email", "Verified contact", "This contact is linked to your booking. Booking creation and status updates are sent through your selected channel.", "We will notify you of every status change through connected channels. You can close the app.", "What happens next?", "We check hotels, flights and other services.", "Booking payment", "We will notify you when payment is available.", "Preparing documents", "After payment and confirmation, we prepare your travel documents and information."]
        }
        return values[key.rawValue]
    }
}

/// An original, bundled two-tone success sound. System Sound Services respects
/// the device's silent-mode behavior and does not take over the audio session.
private enum IumrahBookingCreatedSound {
    @MainActor private static let soundID: SystemSoundID? = {
        guard let url = Bundle.main.url(forResource: "iumrah-booking-created", withExtension: "wav")
            ?? Bundle.main.url(forResource: "iumrah-booking-created", withExtension: "wav", subdirectory: "Animations") else { return nil }
        var id: SystemSoundID = 0
        return AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError ? id : nil
    }()
    @MainActor static func play() {
        if let soundID { AudioServicesPlaySystemSound(soundID) }
    }
}
