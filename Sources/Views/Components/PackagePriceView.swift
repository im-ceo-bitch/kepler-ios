import SwiftUI

struct PackagePriceView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let amount: Decimal
    let currency: String
    var showsPerPerson: Bool = true

    private var formatted: String {
        let number = NSDecimalNumber(decimal: amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = Locale(identifier: settings.language.localeIdentifier)
        formatter.maximumFractionDigits = 0
        return formatter.string(from: number) ?? "\(currency) \(number)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(formatted)
                .font(IumrahType.bold(24, relativeTo: .title2))
            if showsPerPerson {
                Text(L10n.text("price_per_person", settings.language))
                    .font(IumrahType.caption)
                    .foregroundStyle(Color.iumrahMuted)
            }
        }
    }
}
