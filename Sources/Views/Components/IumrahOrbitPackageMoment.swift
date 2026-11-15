import SwiftUI

/// Uses the same real component selection as the legacy package review.
struct IumrahClientPackageMoment: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let services: [IumrahOrbitV5Service]

    var body: some View {
        if !services.isEmpty {
            VStack(spacing: 4) {
                IumrahOrbitAssemblyMoment(services: services, logo: Image("HeaderWordmarkLight"),
                                          maxDiameter: 220, accessibilityTitle: "iumrah")
                Text(copy("Ваши услуги в одном пакете", "Your services in one package", "Xizmatlaringiz bitta paketda", "Хизматларингиз битта пакетда"))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(copy("Бронирование ещё не создано", "Booking has not been created yet", "Bron hali yaratilmagan", "Брон ҳали яратилмаган"))
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .iumrahCard()
            .accessibilityIdentifier("iumrah.orbit.package.v5")
        }
    }

    private func copy(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return cy
        default: return en
        }
    }
}

extension IumrahOrbitV5Service {
    @MainActor static func selectedForJourney(_ journey: JourneyStore) -> [Self] {
        IumrahOrbitService.selectedForJourney(journey).map { .init(id: $0.id, symbol: $0.symbol) }
    }
}
