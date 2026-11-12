import SwiftUI

/// Same server-priced review and OTP checkout as Hotel First / Flight First.
struct LocalJourneyReviewView: View {
    var body: some View { LegacyFinalPackageView() }
}

/// Shared, localized stay summary for the hotel detail and package review.
struct IumrahHotelStaySummary: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let checkin: Date
    let checkout: Date
    let nights: Int
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar").font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(IumrahFlightCopy.text(settings.language, "Даты проживания", "Your stay", "Yashash sanalari", "Яшаш саналари"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(checkin.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: settings.language.localeIdentifier))) + " — " + checkout.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: settings.language.localeIdentifier))))
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 8)
            Text(L10n.format("booking_nights_count", settings.language, nights))
                .font(.subheadline.weight(.semibold))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct IumrahHotelMealsEditor: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Binding var selection: HotelMealChoices
    let stars: Int
    let city: String
    let included: HotelMealChoices
    private var madinah: Bool {
        let name = city.lowercased()
        return name.contains("madin") || name.contains("medin") || name.contains("медин") || name.contains("мадин")
    }
    private func tr(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        IumrahFlightCopy.text(settings.language, ru, en, uz, cy)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tr("Питание в отеле", "Hotel meals", "Mehmonxonada ovqatlanish", "Меҳмонхонада овқатланиш"), systemImage: "fork.knife")
                .font(.subheadline.weight(.semibold))
            mealRow(tr("Завтрак", "Breakfast", "Nonushta", "Нонушта"), key: \.breakfast,
                included: included.breakfast || stars >= 4, packageIncluded: !included.breakfast && stars >= 4)
            if !madinah {
                mealRow(tr("Обед", "Lunch", "Tushlik", "Тушлик"), key: \.lunch, included: included.lunch)
            }
            mealRow(tr("Ужин", "Dinner", "Kechki ovqat", "Кечки овқат"), key: \.dinner, included: included.dinner)
            Text(tr("Дополнительное питание учитывается в итоговой цене пакета для гостей этого номера на весь срок проживания.",
                "Extra meals are included in the package calculation for this room’s guests throughout the stay.",
                "Qo‘shimcha ovqatlanish ushbu xona mehmonlari uchun butun yashash muddatiga paket narxida hisoblanadi.",
                "Қўшимча овқатланиш ушбу хона меҳмонлари учун бутун яшаш муддатига пакет нархида ҳисобланади."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private func mealRow(_ title: String, key: WritableKeyPath<HotelMealChoices, Bool>, included: Bool, packageIncluded: Bool = false) -> some View {
        if included {
            HStack(alignment: .top) {
                Text(title)
                Spacer()
                Text(packageIncluded ? tr("Включён в пакет iumrah", "Included by iumrah", "iumrah paketiga kiritilgan", "iumrah пакетига киритилган") : tr("Включено в тариф", "Included in rate", "Tarifga kiritilgan", "Тарифга киритилган"))
                    .foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
            }.font(.subheadline).padding(.vertical, 5)
        } else {
            Toggle(title, isOn: Binding(get: { selection[keyPath: key] }, set: { selection[keyPath: key] = $0 }))
                .font(.subheadline).tint(Color.iumrahInk)
        }
    }
}
