import SwiftUI

struct UmrahFlowPalette {
    let background: Color
    let backgroundSecondary: Color
    let textPrimary: Color
    let textSecondary: Color
    let glassTint: Color
    let glassStroke: Color
    let progressTrack: Color
    let progressStart: Color
    let progressEnd: Color
    let accent: Color
    let danger: Color

    static let dark = UmrahFlowPalette(
        background: Color(red: 0.025, green: 0.027, blue: 0.034),
        backgroundSecondary: Color(red: 0.050, green: 0.052, blue: 0.065),
        textPrimary: .white,
        textSecondary: .white.opacity(0.58),
        glassTint: .white.opacity(0.055),
        glassStroke: .white.opacity(0.14),
        progressTrack: .white.opacity(0.10),
        progressStart: .white,
        progressEnd: .white,
        accent: .white,
        danger: Color(red: 1.00, green: 0.27, blue: 0.23)
    )

    static let light = UmrahFlowPalette(
        background: Color(red: 0.975, green: 0.975, blue: 0.975),
        backgroundSecondary: .white,
        textPrimary: Color(red: 0.055, green: 0.058, blue: 0.070),
        textSecondary: Color(red: 0.055, green: 0.058, blue: 0.070).opacity(0.55),
        glassTint: .white.opacity(0.34),
        glassStroke: .black.opacity(0.075),
        progressTrack: .black.opacity(0.075),
        progressStart: .black,
        progressEnd: .black,
        accent: .black,
        danger: Color(red: 0.88, green: 0.18, blue: 0.17)
    )
}

struct UmrahFlowBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: UmrahFlowPalette {
        colorScheme == .dark ? .dark : .light
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 / 6.0 : 1.0 / 20.0)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let radius = max(proxy.size.width, proxy.size.height) * 0.95

                ZStack {
                    palette.background

                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color.black.opacity(0.66),
                                palette.backgroundSecondary.opacity(0.42),
                                Color.black.opacity(0.48)
                            ]
                            : [
                                palette.backgroundSecondary.opacity(0.92),
                                palette.background,
                                palette.backgroundSecondary.opacity(0.72)
                            ],
                        startPoint: UnitPoint(
                            x: 0.05 + sin(time * 0.045) * 0.04,
                            y: 0.02
                        ),
                        endPoint: UnitPoint(
                            x: 0.95 + cos(time * 0.040) * 0.04,
                            y: 0.98
                        )
                    )

                    // Brand-aligned monochrome atmosphere, with subdued movement.
                    RadialGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.042), .clear]
                            : [Color.black.opacity(0.035), .clear],
                        center: UnitPoint(
                            x: 0.50 + sin(time * 0.052) * 0.10,
                            y: 0.50 + cos(time * 0.047) * 0.08
                        ),
                        startRadius: 0,
                        endRadius: radius
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

enum UmrahFlowCopy {
    static let chooseStageLabel = "Umrah stages"
    static let closeFlowLabel = "Close Umrah Flow"

    static func playVoice(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Слушать аудиогид"
        case .english: return "Play voice guide"
        case .uzbek: return "Ovozli gidni tinglash"
        case .kazakh: return "Аудиогидті тыңдау"
        case .indonesian: return "Putar panduan suara"
        case .turkish: return "Sesli rehberi dinle"
        case .arabic: return "تشغيل الدليل الصوتي"
        case .malay: return "Mainkan panduan suara"
        case .bengali: return "ভয়েস গাইড শুনুন"
        case .french: return "Écouter le guide"
        }
    }

    static func systemVoice(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Системное озвучивание"
        case .english: return "iPhone reading aloud"
        case .uzbek: return "iPhone ovoz chiqarib o‘qiyapti"
        case .kazakh: return "iPhone дауыстап оқуда"
        case .indonesian: return "iPhone sedang membacakan"
        case .turkish: return "iPhone sesli okuyor"
        case .arabic: return "يقرأ iPhone بصوت عالٍ"
        case .malay: return "iPhone sedang membaca"
        case .bengali: return "iPhone পড়ে শোনাচ্ছে"
        case .french: return "Lecture vocale iPhone"
        }
    }

    static func resumeTitle(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Продолжить Умру?"
        case .english: return "Continue your Umrah?"
        case .uzbek: return "Umrani davom ettirasizmi?"
        case .kazakh: return "Умраны жалғастырасыз ба?"
        case .indonesian: return "Lanjutkan Umrah?"
        case .turkish: return "Umreye devam edilsin mi?"
        case .arabic: return "هل تريد متابعة العمرة؟"
        case .malay: return "Teruskan Umrah?"
        case .bengali: return "উমরাহ চালিয়ে যাবেন?"
        case .french: return "Reprendre votre Omra ?"
        }
    }

    static func resumeMessage(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Мы сохранили этап и счётчики обходов."
        case .english: return "Your stage and round counters were saved."
        case .uzbek: return "Bosqich va aylanishlar soni saqlangan."
        case .kazakh: return "Кезеңіңіз бен айналым санағыштары сақталды."
        case .indonesian: return "Tahap dan hitungan putaran tersimpan."
        case .turkish: return "Aşamanız ve tur sayaçlarınız kaydedildi."
        case .arabic: return "تم حفظ المرحلة وعدّاد الأشواط."
        case .malay: return "Peringkat dan kiraan pusingan anda disimpan."
        case .bengali: return "পর্যায় ও চক্করের সংখ্যা সংরক্ষিত আছে।"
        case .french: return "Votre étape et vos compteurs de tours ont été enregistrés."
        }
    }

    static func resumeAction(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Продолжить"
        case .english: return "Continue"
        case .uzbek: return "Davom etish"
        case .kazakh: return "Жалғастыру"
        case .indonesian: return "Lanjutkan"
        case .turkish: return "Devam et"
        case .arabic: return "متابعة"
        case .malay: return "Teruskan"
        case .bengali: return "চালিয়ে যান"
        case .french: return "Reprendre"
        }
    }

    static func restartAction(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Начать заново"
        case .english: return "Start over"
        case .uzbek: return "Qaytadan boshlash"
        case .kazakh: return "Қайта бастау"
        case .indonesian: return "Mulai ulang"
        case .turkish: return "Yeniden başla"
        case .arabic: return "البدء من جديد"
        case .malay: return "Mula semula"
        case .bengali: return "আবার শুরু করুন"
        case .french: return "Recommencer"
        }
    }

    static func advisorTitle(_ language: UmrahGuideLanguage) -> String {
        "iumrah Advisor"
    }

    static func advisorSubtitle(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Голосовой гид для Умры"
        case .english: return "Voice guide for Umrah"
        case .uzbek: return "Umra uchun ovozli gid"
        case .kazakh: return "Умраға арналған дауыстық гид"
        case .indonesian: return "Panduan suara untuk Umrah"
        case .turkish: return "Umre için sesli rehber"
        case .arabic: return "دليل صوتي للعمرة"
        case .malay: return "Panduan suara untuk Umrah"
        case .bengali: return "উমরাহর জন্য ভয়েস গাইড"
        case .french: return "Guide vocal pour la Omra"
        }
    }

    static func advisorSpeaking(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Advisor говорит"
        case .english: return "Advisor speaking"
        case .uzbek: return "Advisor gapiryapti"
        case .kazakh: return "Advisor сөйлеп тұр"
        case .indonesian: return "Advisor sedang berbicara"
        case .turkish: return "Advisor konuşuyor"
        case .arabic: return "Advisor يتحدث"
        case .malay: return "Advisor sedang bercakap"
        case .bengali: return "Advisor কথা বলছে"
        case .french: return "Advisor parle"
        }
    }

    static func tapToListen(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Коснитесь градиента, чтобы слушать"
        case .english: return "Tap the gradient to listen"
        case .uzbek: return "Tinglash uchun gradientga teging"
        case .kazakh: return "Тыңдау үшін градиентті түртіңіз"
        case .indonesian: return "Ketuk gradien untuk mendengarkan"
        case .turkish: return "Dinlemek için gradyana dokunun"
        case .arabic: return "المس التدرج للاستماع"
        case .malay: return "Sentuh gradien untuk mendengar"
        case .bengali: return "শুনতে গ্রেডিয়েন্টে ট্যাপ করুন"
        case .french: return "Touchez le dégradé pour écouter"
        }
    }

    static func loadingVoice(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Загружаем голос"
        case .english: return "Loading voice"
        case .uzbek: return "Ovoz yuklanmoqda"
        case .kazakh: return "Дауыс жүктелуде"
        case .indonesian: return "Memuat suara"
        case .turkish: return "Ses yükleniyor"
        case .arabic: return "جارٍ تحميل الصوت"
        case .malay: return "Memuatkan suara"
        case .bengali: return "ভয়েস লোড হচ্ছে"
        case .french: return "Chargement de la voix"
        }
    }

    static func audioUnavailable(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Аудио пока недоступно"
        case .english: return "Audio is not available yet"
        case .uzbek: return "Audio hozircha mavjud emas"
        case .kazakh: return "Аудио әзірге қолжетімсіз"
        case .indonesian: return "Audio belum tersedia"
        case .turkish: return "Ses henüz mevcut değil"
        case .arabic: return "الصوت غير متاح بعد"
        case .malay: return "Audio belum tersedia"
        case .bengali: return "অডিও এখনো উপলভ্য নয়"
        case .french: return "L’audio n’est pas encore disponible"
        }
    }

    static func tapToChange(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Коснитесь текста, чтобы изменить"
        case .english: return "Tap the text to change"
        case .uzbek: return "Matnni o‘zgartirish uchun teging"
        case .kazakh: return "Мәтінді өзгерту үшін түртіңіз"
        case .indonesian: return "Ketuk teks untuk mengganti"
        case .turkish: return "Metni değiştirmek için dokunun"
        case .arabic: return "المس النص للتغيير"
        case .malay: return "Sentuh teks untuk menukar"
        case .bengali: return "লেখা বদলাতে ট্যাপ করুন"
        case .french: return "Touchez le texte pour changer"
        }
    }

    static func listening(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Слушать"
        case .english: return "Listen"
        case .uzbek: return "Tinglash"
        case .kazakh: return "Тыңдау"
        case .indonesian: return "Dengarkan"
        case .turkish: return "Dinle"
        case .arabic: return "استماع"
        case .malay: return "Dengar"
        case .bengali: return "শুনুন"
        case .french: return "Écouter"
        }
    }

    static func reading(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Читать"
        case .english: return "Read"
        case .uzbek: return "O‘qish"
        case .kazakh: return "Оқу"
        case .indonesian: return "Baca"
        case .turkish: return "Oku"
        case .arabic: return "قراءة"
        case .malay: return "Baca"
        case .bengali: return "পড়ুন"
        case .french: return "Lire"
        }
    }

    static func previous(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Назад"
        case .english: return "Previous"
        case .uzbek: return "Orqaga"
        case .kazakh: return "Артқа"
        case .indonesian: return "Kembali"
        case .turkish: return "Geri"
        case .arabic: return "السابق"
        case .malay: return "Kembali"
        case .bengali: return "আগেরটি"
        case .french: return "Précédent"
        }
    }

    static func next(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Далее"
        case .english: return "Next"
        case .uzbek: return "Keyingi"
        case .kazakh: return "Келесі"
        case .indonesian: return "Berikutnya"
        case .turkish: return "İleri"
        case .arabic: return "التالي"
        case .malay: return "Seterusnya"
        case .bengali: return "পরবর্তী"
        case .french: return "Suivant"
        }
    }

    static func done(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Готово"
        case .english: return "Done"
        case .uzbek: return "Tayyor"
        case .kazakh: return "Дайын"
        case .indonesian: return "Selesai"
        case .turkish: return "Tamam"
        case .arabic: return "تم"
        case .malay: return "Selesai"
        case .bengali: return "সম্পন্ন"
        case .french: return "Terminé"
        }
    }

    static func guidance(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Подсказка"
        case .english: return "Guidance"
        case .uzbek: return "Yo‘riqnoma"
        case .kazakh: return "Нұсқаулық"
        case .indonesian: return "Panduan"
        case .turkish: return "Rehberlik"
        case .arabic: return "إرشاد"
        case .malay: return "Panduan"
        case .bengali: return "নির্দেশনা"
        case .french: return "Guide"
        }
    }

    static func dua(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Дуа"
        case .english: return "Dua"
        case .uzbek: return "Duo"
        case .kazakh: return "Дұға"
        case .indonesian: return "Doa"
        case .turkish: return "Dua"
        case .arabic: return "دعاء"
        case .malay: return "Doa"
        case .bengali: return "দোয়া"
        case .french: return "Doua"
        }
    }

    static func meaning(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Смысл"
        case .english: return "Meaning"
        case .uzbek: return "Ma’nosi"
        case .kazakh: return "Мағынасы"
        case .indonesian: return "Arti"
        case .turkish: return "Anlamı"
        case .arabic: return "المعنى"
        case .malay: return "Maksud"
        case .bengali: return "অর্থ"
        case .french: return "Sens"
        }
    }

    static func dhikr(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Зикр"
        case .english: return "Dhikr"
        case .uzbek: return "Zikr"
        case .kazakh: return "Зікір"
        case .indonesian: return "Dzikir"
        case .turkish: return "Zikir"
        case .arabic: return "ذكر"
        case .malay: return "Zikir"
        case .bengali: return "যিকর"
        case .french: return "Dhikr"
        }
    }

    static func chooseStage(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Перейти к этапу"
        case .english: return "Go to a stage"
        case .uzbek: return "Bosqichga o‘tish"
        case .kazakh: return "Кезеңге өту"
        case .indonesian: return "Pilih tahap"
        case .turkish: return "Aşamaya git"
        case .arabic: return "الانتقال إلى مرحلة"
        case .malay: return "Pergi ke peringkat"
        case .bengali: return "ধাপে যান"
        case .french: return "Aller à une étape"
        }
    }

    static func leaveUmrah(_ language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian: return "Выйти из Умры"
        case .english: return "Exit Umrah"
        case .uzbek: return "Umradan chiqish"
        case .kazakh: return "Умрадан шығу"
        case .indonesian: return "Keluar dari Umrah"
        case .turkish: return "Umre’den çık"
        case .arabic: return "الخروج من العمرة"
        case .malay: return "Keluar daripada Umrah"
        case .bengali: return "উমরাহ থেকে বের হন"
        case .french: return "Quitter la Omra"
        }
    }

    static func stageTitle(_ stage: UmrahFlowState.Stage, language: UmrahGuideLanguage) -> String {
        switch language {
        case .russian:
            switch stage {
            case .inUmrah: return "Умра"
            case .start: return "Начало Умры"
            case .tawaf: return "Таваф"
            case .postTawaf: return "После Тавафа"
            case .safa: return "Сафа и Марва"
            case .end: return "Завершение"
            case .afterUmrah: return "После Умры"
            }
        case .english:
            switch stage {
            case .inUmrah: return "Umrah"
            case .start: return "Start Umrah"
            case .tawaf: return "Tawaf"
            case .postTawaf: return "After Tawaf"
            case .safa: return "Safa & Marwa"
            case .end: return "Complete Umrah"
            case .afterUmrah: return "After Umrah"
            }
        case .uzbek:
            switch stage {
            case .inUmrah: return "Umra"
            case .start: return "Umrani boshlash"
            case .tawaf: return "Tavof"
            case .postTawaf: return "Tavofdan keyin"
            case .safa: return "Safo va Marva"
            case .end: return "Umrani yakunlash"
            case .afterUmrah: return "Umradan keyin"
            }
        case .kazakh:
            switch stage {
            case .inUmrah: return "Умра"
            case .start: return "Умраны бастау"
            case .tawaf: return "Тауап"
            case .postTawaf: return "Тауаптан кейін"
            case .safa: return "Сафа және Маруа"
            case .end: return "Умраны аяқтау"
            case .afterUmrah: return "Умрадан кейін"
            }
        case .indonesian:
            switch stage {
            case .inUmrah: return "Umrah"
            case .start: return "Mulai Umrah"
            case .tawaf: return "Tawaf"
            case .postTawaf: return "Setelah Tawaf"
            case .safa: return "Safa & Marwah"
            case .end: return "Selesaikan Umrah"
            case .afterUmrah: return "Setelah Umrah"
            }
        case .turkish:
            switch stage {
            case .inUmrah: return "Umre"
            case .start: return "Umreye Başla"
            case .tawaf: return "Tavaf"
            case .postTawaf: return "Tavaftan Sonra"
            case .safa: return "Safa ve Merve"
            case .end: return "Umreyi Tamamla"
            case .afterUmrah: return "Umreden Sonra"
            }
        case .arabic:
            switch stage {
            case .inUmrah: return "العمرة"
            case .start: return "بدء العمرة"
            case .tawaf: return "الطواف"
            case .postTawaf: return "بعد الطواف"
            case .safa: return "الصفا والمروة"
            case .end: return "إتمام العمرة"
            case .afterUmrah: return "بعد العمرة"
            }
        case .malay:
            switch stage {
            case .inUmrah: return "Umrah"
            case .start: return "Mulakan Umrah"
            case .tawaf: return "Tawaf"
            case .postTawaf: return "Selepas Tawaf"
            case .safa: return "Safa & Marwah"
            case .end: return "Selesaikan Umrah"
            case .afterUmrah: return "Selepas Umrah"
            }
        case .bengali:
            switch stage {
            case .inUmrah: return "উমরাহ"
            case .start: return "উমরাহ শুরু"
            case .tawaf: return "তাওয়াফ"
            case .postTawaf: return "তাওয়াফের পর"
            case .safa: return "সাফা ও মারওয়া"
            case .end: return "উমরাহ সম্পন্ন"
            case .afterUmrah: return "উমরাহর পর"
            }
        case .french:
            switch stage {
            case .inUmrah: return "Omra"
            case .start: return "Commencer la Omra"
            case .tawaf: return "Tawaf"
            case .postTawaf: return "Après le Tawaf"
            case .safa: return "Safa & Marwa"
            case .end: return "Terminer la Omra"
            case .afterUmrah: return "Après la Omra"
            }
        }
    }
}
