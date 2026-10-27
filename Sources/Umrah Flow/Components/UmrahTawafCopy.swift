import Foundation

/// Interface chrome only. Ritual guidance remains in the reviewed catalog.
enum UmrahTawafCopy {
    static func local(
        _ language: UmrahGuideLanguage, ru: String, en: String, uz: String, ar: String,
        kk: String, id: String, tr: String, ms: String, bn: String, fr: String
    ) -> String {
        switch language {
        case .russian: return ru
        case .english: return en
        case .uzbek: return uz
        case .arabic: return ar
        case .kazakh: return kk
        case .indonesian: return id
        case .turkish: return tr
        case .malay: return ms
        case .bengali: return bn
        case .french: return fr
        }
    }

    static func routeStage(_ language: UmrahGuideLanguage, current: Int) -> String {
        let prefix = local(language, ru: "Этап", en: "Stage", uz: "Bosqich", ar: "المرحلة", kk: "Кезең", id: "Tahap", tr: "Aşama", ms: "Peringkat", bn: "ধাপ", fr: "Étape")
        return "\(prefix) \(max(0, min(5, current))) / 5"
    }
    static func routeProgress(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Прогресс маршрута", en: "Route progress", uz: "Yo‘l jarayoni", ar: "تقدم المسار", kk: "Жалпы ілгерілеу", id: "Progres tahapan", tr: "Genel ilerleme", ms: "Kemajuan perjalanan", bn: "সামগ্রিক অগ্রগতি", fr: "Progression globale")
    }
    static func completed(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Завершено", en: "Completed", uz: "Bajarildi", ar: "المكتمل", kk: "Аяқталды", id: "Selesai", tr: "Tamamlanan", ms: "Selesai", bn: "সম্পন্ন", fr: "Terminés")
    }
    static func currentRound(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Текущий круг", en: "Current circuit", uz: "Joriy aylanish", ar: "الشوط الحالي", kk: "Ағымдағы айналым", id: "Putaran saat ini", tr: "Mevcut tur", ms: "Pusingan semasa", bn: "বর্তমান চক্কর", fr: "Tour en cours")
    }
    static func round(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Круг", en: "Circuit", uz: "Aylanish", ar: "الشوط", kk: "Айналым", id: "Putaran", tr: "Tur", ms: "Pusingan", bn: "চক্কর", fr: "Tour")
    }
    static func page(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Страница", en: "Page", uz: "Sahifa", ar: "الصفحة", kk: "Бет", id: "Halaman", tr: "Sayfa", ms: "Halaman", bn: "পৃষ্ঠা", fr: "Page")
    }
    static func guidance(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Что делать сейчас", en: "Guidance for this circuit", uz: "Hozir nima qilish kerak", ar: "إرشادات هذا الشوط", kk: "Осы айналымдағы нұсқаулық", id: "Petunjuk putaran ini", tr: "Bu tur için rehber", ms: "Panduan pusingan ini", bn: "এই চক্করের নির্দেশনা", fr: "Conseils pour ce tour")
    }
    static func otherText(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Другой вариант текста", en: "Switch guidance text", uz: "Boshqa matn", ar: "تغيير النص", kk: "Басқа мәтінді көрсету", id: "Ganti teks panduan", tr: "Rehber metnini değiştir", ms: "Tukar teks panduan", bn: "নির্দেশনার লেখা বদলান", fr: "Changer le texte")
    }
    static func read(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Читать дуа", en: "Read supplications", uz: "Duolarni o‘qish", ar: "قراءة الأدعية", kk: "Дұғаларды оқу", id: "Baca doa", tr: "Duaları oku", ms: "Baca doa", bn: "দোয়া পড়ুন", fr: "Lire les invocations")
    }
    static func backToGuide(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "К инструкции", en: "Back to guidance", uz: "Yo‘riqnomaga qaytish", ar: "العودة للإرشادات", kk: "Нұсқаулыққа оралу", id: "Kembali ke panduan", tr: "Rehbere dön", ms: "Kembali ke panduan", bn: "নির্দেশনায় ফিরুন", fr: "Retour aux conseils")
    }
    static func swipe(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Проведите, чтобы завершить круг", en: "Slide to finish the circuit", uz: "Aylanishni yakunlash uchun suring", ar: "اسحب لإكمال الشوط", kk: "Айналымды аяқтау үшін сырғытыңыз", id: "Geser untuk selesaikan putaran", tr: "Turu bitirmek için kaydır", ms: "Leret untuk tamatkan pusingan", bn: "চক্কর শেষ করতে স্লাইড করুন", fr: "Glisser pour terminer le tour")
    }
    static func swipeHint(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Только после полного обхода Каабы", en: "Only after completing a full circuit", uz: "Faqat to‘liq aylanishdan so‘ng", ar: "فقط بعد إكمال الشوط بالكامل", kk: "Қағбаны толық айналып шыққаннан кейін ғана", id: "Hanya setelah satu putaran penuh", tr: "Yalnızca tam turu bitirdikten sonra", ms: "Hanya selepas satu pusingan penuh", bn: "সম্পূর্ণ চক্কর শেষ হলে তবেই", fr: "Après un tour complet uniquement")
    }
    static func done(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Все 7 кругов завершены", en: "All 7 circuits completed", uz: "7 ta aylanish yakunlandi", ar: "اكتملت الأشواط السبعة", kk: "7 айналым аяқталды", id: "Ketujuh putaran selesai", tr: "7 tur tamamlandı", ms: "Semua 7 pusingan selesai", bn: "৭টি চক্কর সম্পন্ন", fr: "Les 7 tours sont terminés")
    }
    static func next(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Продолжить Умру", en: "Continue Umrah", uz: "Umrani davom ettirish", ar: "متابعة العمرة", kk: "Ұмраны жалғастыру", id: "Lanjutkan Umrah", tr: "Umreye devam et", ms: "Teruskan Umrah", bn: "উমরাহ চালিয়ে যান", fr: "Poursuivre la Omra")
    }
    static func undo(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Отменить последний круг", en: "Undo last circuit", uz: "Oxirgi aylanishni bekor qilish", ar: "التراجع عن آخر شوط", kk: "Соңғы айналымды қайтару", id: "Batalkan putaran terakhir", tr: "Son turu geri al", ms: "Batalkan pusingan terakhir", bn: "শেষ চক্কর বাতিল করুন", fr: "Annuler le dernier tour")
    }
    static func play(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Слушать инструкцию", en: "Listen to guidance", uz: "Yo‘riqnomani tinglash", ar: "استمع للإرشادات", kk: "Нұсқаулықты тыңдау", id: "Dengarkan panduan", tr: "Rehberi dinle", ms: "Dengar panduan", bn: "নির্দেশনা শুনুন", fr: "Écouter les conseils")
    }
    static func pause(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Пауза", en: "Pause narration", uz: "To‘xtatish", ar: "إيقاف مؤقت", kk: "Кідірту", id: "Jeda", tr: "Duraklat", ms: "Jeda", bn: "বিরতি", fr: "Pause")
    }
    static func direction(_ language: UmrahGuideLanguage) -> String {
        local(language, ru: "Двигайтесь против часовой стрелки", en: "Move counterclockwise", uz: "Soat strelkasiga teskari yuring", ar: "طُف عكس اتجاه عقارب الساعة", kk: "Сағат тіліне қарсы жүріңіз", id: "Bergerak berlawanan arah jarum jam", tr: "Saat yönünün tersine ilerleyin", ms: "Bergerak melawan arah jam", bn: "ঘড়ির কাঁটার বিপরীতে চলুন", fr: "Avancez dans le sens antihoraire")
    }
}
