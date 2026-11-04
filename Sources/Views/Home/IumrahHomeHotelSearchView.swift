import SwiftUI

/// The Home search form routes into the real Nuitee catalog in the SECOND tab.
/// It intentionally exposes only city, dates and adults: Nuitee V1 supports
/// one room, and has no children/rooms parameters in its supplier request.
struct IumrahHomeHotelSearchView: View {
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore

    @State private var city = "makkah"
    @State private var checkin = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    )
    @State private var nights = 3
    @State private var adults = 2

    private var checkout: Date {
        Calendar.current.date(byAdding: .day, value: nights, to: checkin) ?? checkin
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(copy("Найдите отель для умры", "Umra uchun mehmonxona toping", "Find your Umrah hotel"))
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(copy("Выберите город, даты и гостей", "Shahar, sana va mehmonlarni tanlang", "Choose a city, dates and guests"))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                citySelector
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)

                Divider().padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(.system(size: 19, weight: .regular))
                        .frame(width: 25)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy("Дата заезда", "Kelish sanasi", "Check-in"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        DatePicker(
                            copy("Дата заезда", "Kelish sanasi", "Check-in"),
                            selection: $checkin,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(.black)
                        .accessibilityIdentifier("iumrah.home.hotels.checkin")
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(copy("Выезд", "Ketish", "Check-out"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(checkout.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider().padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Image(systemName: "moon")
                        .font(.system(size: 18))
                        .frame(width: 25)
                    Text(copy("Ночей", "Tun", "Nights"))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer(minLength: 0)
                    quantityControl(value: $nights, minimum: 1, maximum: 28)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Image(systemName: "person.2")
                        .font(.system(size: 18))
                        .frame(width: 25)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy("Взрослые", "Kattalar", "Adults"))
                            .font(.system(size: 15, weight: .semibold))
                        Text(copy("1 номер", "1 xona", "1 room"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    quantityControl(value: $adults, minimum: 1, maximum: 6)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Button {
                    chrome.findHotels(IumrahHotelTabSearch(
                        city: city,
                        checkin: checkin,
                        nights: nights,
                        adults: adults
                    ))
                } label: {
                    Label(copy("Найти отели", "Mehmonxonalarni topish", "Find hotels"), systemImage: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.white)
                        .background(Color.iumrahSignatureBlack, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("iumrah.home.hotels.find")
                .padding(12)
            }
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var citySelector: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 19))
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 8) {
                Text(copy("Город назначения", "Manzil shahri", "Destination"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    cityButton("makkah", title: copy("Мекка", "Makka", "Makkah"))
                    cityButton("madinah", title: copy("Медина", "Madina", "Madinah"))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func cityButton(_ value: String, title: String) -> some View {
        Button {
            city = value
            IumrahHaptics.selection()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .foregroundStyle(city == value ? Color.white : Color.primary)
                .padding(.horizontal, 15)
                .frame(height: 36)
                .background(city == value ? Color.iumrahSignatureBlack : Color.iumrahPageBackground, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(city == value ? .isSelected : [])
    }

    private func quantityControl(value: Binding<Int>, minimum: Int, maximum: Int) -> some View {
        HStack(spacing: 0) {
            Button {
                value.wrappedValue = max(minimum, value.wrappedValue - 1)
            } label: {
                Image(systemName: "minus").frame(width: 38, height: 40)
            }
            .disabled(value.wrappedValue <= minimum)
            Text("\(value.wrappedValue)")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 28)
            Button {
                value.wrappedValue = min(maximum, value.wrappedValue + 1)
            } label: {
                Image(systemName: "plus").frame(width: 38, height: 40)
            }
            .disabled(value.wrappedValue >= maximum)
        }
        .foregroundStyle(Color.primary)
        .background(Color.iumrahPageBackground, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
    }

    private func copy(_ ru: String, _ uz: String, _ en: String) -> String {
        switch settings.language {
        case .russian, .uzbekCyrillic: return ru
        case .uzbek: return uz
        default: return en
        }
    }
}
