import SwiftUI

private struct BusinessOfferPayload: Decodable {
    struct Package: Decodable {
        let totalUsd: Double
        let input: BookingInputRecord
        let hotelNames: BookingHotelNames
        let flight: String
        let includedServices: [String]
    }
    let packageID: String
    let status: String
    let expiresAt: String
    let package: Package
}
private struct BusinessOfferAccept: Encodable {
    let firstName: String
    let lastName: String
    let channel: String
    let verificationToken: String
    let requestSecret: String
}
struct BusinessOfferView: View {
    let token: String
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var chrome: AppChromeStore
    @Environment(\.dismiss) private var dismiss
    @State private var offer: BusinessOfferPayload?
    @State private var errorMessage: String?
    @State private var loading = true
    @State private var requestSecret = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
    private var path: String { "/api/bookings/offers/" + token }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("iumrah").font(.largeTitle.bold())
                    Text(copy("Ваше предложение", "Your offer", "Sizning taklifingiz", "Сизнинг таклифингиз")).font(.title2.bold())
                    if let offer { Text("Package ID · " + offer.packageID).font(.caption.monospaced()).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(24).foregroundStyle(.white).background(.black, in: RoundedRectangle(cornerRadius: 24))
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let offer {
                    let p = offer.package
                    Text(p.totalUsd, format: .currency(code: "USD")).font(.largeTitle.bold())
                    Text("\(p.input.travelers.totalPeople) " + copy("паломников", "pilgrims", "ziyoratchi", "зиёратчи")).font(.subheadline).foregroundStyle(.secondary)
                    Label(p.input.startDate + " — " + p.input.endDate, systemImage: "calendar")
                    Label(p.flight, systemImage: "airplane")
                    Label(p.hotelNames.makkah, systemImage: "building.2")
                    if !p.hotelNames.madinah.isEmpty { Label(p.hotelNames.madinah, systemImage: "building.2") }
                    Text(copy("Наличие и цена требуют подтверждения. Оплата пока не требуется.", "Availability and price require confirmation. No payment yet.", "Mavjudlik va narx tasdiqlanishi kerak. Hozircha to‘lov yo‘q.", "Мавжудлик ва нарх тасдиқланиши керак. Ҳозирча тўлов йўқ.")).font(.footnote).foregroundStyle(.secondary)
                    if offer.status == "available" {
                        NavigationLink {
                            IumrahBookingConfirmationView(createVerifiedBooking: { profile, channel, proof in
                                let response: BookingCreateResponse = try await APIClient.shared.post(path + "/accept", body: BusinessOfferAccept(firstName: profile.firstName, lastName: profile.lastName, channel: channel, verificationToken: proof, requestSecret: requestSecret))
                                return try bookings.adoptOfferBooking(response)
                            }, createBooking: { _ in throw APIError.invalidResponse })
                        } label: { Text(copy("Забронировать умру", "Book Umrah", "Umrani bron qilish", "Умрани брон қилиш")).font(.headline).frame(maxWidth: .infinity).padding(16).foregroundStyle(.white).background(.black, in: Capsule()) }.buttonStyle(.plain)
                    } else if let session = bookings.sessions.first(where: { $0.booking.offerPackageID == offer.packageID }) {
                        Button(copy("Открыть бронирование", "Open booking", "Bronni ochish", "Бронни очиш")) { dismiss(); chrome.openBooking(id: session.id) }.buttonStyle(.borderedProminent)
                    } else { Text(copy("Предложение больше недоступно", "Offer no longer available", "Taklif endi mavjud emas", "Таклиф энди мавжуд эмас")).foregroundStyle(.secondary) }
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red); Button(copy("Повторить", "Retry", "Qayta urinish", "Қайта уриниш")) { Task { await load() } } }
            }.padding(20)
        }.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy("Закрыть", "Close", "Yopish", "Ёпиш")) { dismiss() } } }.task { await load() }
    }
    @MainActor private func load() async {
        loading = true; errorMessage = nil; defer { loading = false }
        do { offer = try await APIClient.shared.get(path) } catch { errorMessage = error.localizedDescription }
    }
    private func copy(_ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
        switch settings.language { case .russian: return ru; case .uzbek: return uz; case .uzbekCyrillic: return cy; default: return en }
    }
}
