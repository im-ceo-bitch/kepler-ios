import SwiftUI

func familyCopy(_ language: AppSettingsStore.Language, _ ru: String, _ en: String, _ uz: String, _ cy: String) -> String {
    switch language {
    case .russian: return ru
    case .uzbek: return uz
    case .uzbekCyrillic: return cy
    case .turkish: return TurkishLocalization.phrase(en)
    case .arabic: return ArabicLocalization.phrase(en)
    default: return en
    }
}

struct FamilyWelcome: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var second = false
    @State private var languages = false
    let finish: (Bool) -> Void

    var body: some View {
        let l = settings.language
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button { languages = true } label: { Image(systemName: "globe") }
                    .accessibilityLabel(settings.language.localeIdentifier)
                Spacer()
                Button(familyCopy(l,"Посмотреть цены","See prices","Narxlarni ko‘rish","Нархларни кўриш")) { finish(false) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(second ? "TransferMalibu" : "IumrahConfiguratorHero")
                        .resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: 205).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    Text(second ? "02 / 08" : "01 / 08").font(.caption.monospacedDigit())
                    Text(second
                         ? familyCopy(l,"Ваш гид рядом","Your own guide","Shaxsiy hamrohingiz","Шахсий ҳамроҳингиз")
                         : familyCopy(l,"Ваша семья. Ваша умра. Всё организовано.","Your family. Your Umrah. Everything arranged.","Oilangiz bilan Umra. Barchasi tayyor.","Оилангиз билан Умра. Барчаси тайёр."))
                        .font(.system(.largeTitle, design: .rounded).bold())
                    Text(second
                         ? familyCopy(l,"Гид встретит вас в аэропорту, поможет заселиться, проведёт по зияратам и будет рядом во время умры. В день отъезда проводит в аэропорт.","Your guide meets you at the airport, helps you check in, accompanies you on ziyarat and during Umrah, and sees you off at the airport.","Gid sizni aeroportda kutib oladi, mehmonxonaga joylashishda yordam beradi, ziyorat va Umrada hamroh bo‘ladi. Qaytishda aeroportgacha kuzatadi.","Гид сизни аэропортда кутиб олади, меҳмонхонага жойлашишда ёрдам беради, зиёрат ва Умрада ҳамроҳ бўлади. Қайтишда аэропортгача кузатади.")
                         : familyCopy(l,"Вы едете своей семьёй, без сборной группы. Мы организуем перелёт, визу, семейный номер, питание и отдельную машину.","Travel as a family with private transport. We arrange flights, visas, meals and your family room.","Katta guruhsiz, oilangiz bilan safar qiling. Parvoz, viza, oilaviy xona, ovqatlanish va alohida mashinani biz tashkil qilamiz.","Катта гуруҳсиз, оилангиз билан сафар қилинг. Парвоз, виза, оилавий хона, овқатланиш ва алоҳида машинани биз ташкил қиламиз."))
                        .font(.body).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if second {
                Button(familyCopy(l,"Назад","Back","Orqaga","Орқага")) { second = false }
            }
            Button(second ? familyCopy(l,"Подобрать поездку","Plan my trip","Safarni tanlash","Сафарни танлаш") : familyCopy(l,"Далее","Next","Keyingi","Кейинги")) {
                if second { finish(true) } else { second = true }
            }.buttonStyle(IumrahPrimaryButtonStyle())
        }.padding(20).sheet(isPresented: $languages) { IumrahLanguageSelectionSheet(currentLanguage: l) }
    }
}

struct FamilyQuoteOrbit: View {
    let still: Bool
    private let symbols = ["airplane", "bed.double.fill", "car.fill", "person.fill"]
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: still)) { tick in
            let phase = still ? 0 : tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) * .pi * 2 / 5
            ZStack {
                Circle().stroke(.secondary.opacity(0.22)).frame(width: 96, height: 96)
                Image(systemName: "suitcase.fill").font(.title)
                ForEach(symbols.indices, id: \.self) { i in
                    let angle = phase + Double(i) * .pi / 2
                    Image(systemName: symbols[i]).offset(x: 48 * cos(angle), y: 48 * sin(angle))
                }
            }.frame(width: 136, height: 136)
        }.accessibilityHidden(true)
    }
}

/// Save selections only. Availability and signed prices are requested afresh.
struct FamilyTripDraft: Codable, Equatable {
    static let key = "iumrah.family.draft.v1"
    var trip: TripDraft
    var outward: String?
    var inward: String?
    var complete: String?
    var hotel: HotelSummary?
    var madinah: HotelSummary?
    var room: HotelRoom?
    var madinahRoom: HotelRoom?
    var category: IumrahRoomCategoryOption?
    var madinahCategory: IumrahRoomCategoryOption?
    var vehicle: TransferVehicleKind?
    var train: Bool

    @MainActor init(_ journey: JourneyStore) {
        trip = journey.trip
        outward = journey.selectedPublishedOutboundID
        inward = journey.selectedPublishedReturnID
        complete = journey.selectedPublishedCompleteID
        hotel = journey.selectedHotel
        madinah = journey.selectedMadinahHotel
        room = journey.selectedRoom
        madinahRoom = journey.selectedMadinahRoom
        category = journey.selectedRoomCategory
        madinahCategory = journey.selectedMadinahRoomCategory
        vehicle = journey.selectedTransferVehicle
        train = journey.haramainTrainSelected
    }

    @MainActor func restore(_ journey: JourneyStore) {
        journey.resetAfterTripChange()
        journey.trip = trip
        journey.packageFlightPath = .publishedDirect
        journey.selectedPublishedOutboundID = outward
        journey.selectedPublishedReturnID = inward
        journey.selectedPublishedCompleteID = complete
        journey.selectedHotel = hotel
        journey.selectedMadinahHotel = madinah
        journey.selectedRoom = room
        journey.selectedMadinahRoom = madinahRoom
        journey.selectedRoomCategory = category
        journey.selectedMadinahRoomCategory = madinahCategory
        journey.selectedTransferVehicle = vehicle
        journey.haramainTrainSelected = train
    }
}
