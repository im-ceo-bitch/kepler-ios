import Foundation

/// Shared service-price presentation for existing package screens.
/// The new Nuitee journey computes its estimate on-device in
/// LocalJourneySelection.swift. Legacy signed quotes retain their server path.
enum PackagePricingPresentation {
    /// These two values are intentionally public because they are shown to the
    /// pilgrim as selectable meal-service add-ons in the UI.
    private static let comfortMealServiceUsd = Decimal(30)
    private static let luxuryMealServiceUsd = Decimal(50)

    static func optionalMealUnitPriceUsd(for tier: PackageTier) -> Decimal? {
        switch tier {
        case .economy, .standard:
            return nil
        case .comfort:
            return comfortMealServiceUsd
        case .luxury:
            return luxuryMealServiceUsd
        }
    }
}

/// User-facing errors for server-authoritative package pricing. The name is kept
/// for source compatibility with existing views; it no longer represents a local
/// pricing engine.
enum LocalPricingError: LocalizedError {
    case invalidFlightFare
    case missingHotelPrice(String)
    case invalidComponents

    var errorDescription: String? {
        switch self {
        case .invalidFlightFare:
            return "Не удалось получить текущую стоимость выбранного перелёта."
        case .missingHotelPrice(let city):
            return "Цена Primary Hotel в городе \(city) сейчас недоступна или устарела. Выберите другой доступный отель или повторите позже."
        case .invalidComponents:
            return "Компоненты пакета неполные. Повторите расчёт."
        }
    }
}
