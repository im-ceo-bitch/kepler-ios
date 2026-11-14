import SwiftUI

/// Legacy entry point shares the same creation UI. A contact is not inferred
/// here: only guest checkout has the verified notification destination.
struct IumrahBookingCelebrationView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let session: StoredBookingSession
    let onOpenBooking: () -> Void
    let onHome: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                IumrahBookingCreatedContent(session: session)
                Button(action: onOpenBooking) { Text(L10n.text("open_booking", settings.language)) }
                    .buttonStyle(IumrahPrimaryButtonStyle())
                Button(action: onHome) { Text(homeTitle) }
                    .buttonStyle(IumrahSecondaryButtonStyle())
            }
            .padding(IumrahDesign.pagePadding)
        }
        .background(Color(uiColor: .systemBackground))
        .statusBarHidden(false)
        .accessibilityIdentifier("iumrah.booking.celebration")
    }

    private var homeTitle: String {
        switch settings.language {
        case .russian: return "На главную"
        case .uzbek: return "Bosh sahifaga"
        case .uzbekCyrillic: return "Бош саҳифага"
        case .arabic: return "الصفحة الرئيسية"
        case .turkish: return "Ana sayfa"
        case .indonesian: return "Beranda"
        case .malay: return "Laman utama"
        case .english: return "Home"
        }
    }
}
