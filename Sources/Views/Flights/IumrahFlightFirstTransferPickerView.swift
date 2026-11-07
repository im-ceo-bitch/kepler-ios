import SwiftUI

/// Flight First step 2. Captures transfer preference before hotel selection;
/// the quote is intentionally deferred until real hotels have been selected.
struct IumrahFlightFirstTransferPickerView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var selected: TransferVehicleKind = .carnival
    @State private var showHotels = false

    private func tr(_ ru: String, _ en: String, _ uz: String, _ uzCyrl: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzCyrl
        default: return en
        }
    }

    private var isValid: Bool { journey.trip.travelerCount <= selected.passengerCapacity }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(tr("Выберите трансфер", "Choose a transfer", "Transfer tanlang", "Трансфер танланг"))
                        .font(IumrahType.bold(30, relativeTo: .largeTitle))
                    Text(tr("Встреча в аэропорту и поездка с семьёй. Окончательную стоимость пакета рассчитаем после выбора отелей.",
                            "Airport pickup for your family. The final package quote comes after hotel selection.",
                            "Oila uchun aeroport transferi. Yakuniy narx mehmonxona tanlangach hisoblanadi.",
                            "Оила учун аэропорт трансфери. Якуний нарх меҳмонхона танлангач ҳисобланади."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 10)

                ForEach(TransferVehicleKind.allCases) { vehicle in
                    Button {
                        selected = vehicle
                        IumrahHaptics.selection()
                    } label: {
                        HStack(spacing: 15) {
                            Image(vehicle.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 105, height: 82)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(vehicle.modelName)
                                    .font(.headline.weight(.bold))
                                Label("\(vehicle.passengerCapacity)", systemImage: "person.2")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                let addOn = vehicle.publicUpgradeUsd(for: journey.trip.scope)
                                if addOn > 0 {
                                    Text("+\(NSDecimalNumber(decimal: addOn).intValue) USD")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(tr("Без доплаты", "No extra charge", "Qo‘shimcha to‘lovsiz", "Қўшимча тўловсиз"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: selected == vehicle ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selected == vehicle ? Color.iumrahInk : Color.iumrahMuted)
                        }
                        .foregroundStyle(Color.iumrahInk)
                        .padding(17)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 28))
                        .overlay {
                            RoundedRectangle(cornerRadius: 28)
                                .strokeBorder(selected == vehicle ? Color.iumrahInk : Color.primary.opacity(0.06),
                                              lineWidth: selected == vehicle ? 1.4 : 0.7)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .background(Color.iumrahPageBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if !isValid {
                    Text(tr("Выбранная машина не вмещает всех паломников.", "Not enough seats for your travelers.",
                            "Mashina barcha ziyoratchilar uchun mos emas.", "Машина барча зиёратчилар учун мос эмас."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    journey.chooseTransferVehicle(selected)
                    journey.confirmTransferSelection()
                    showHotels = true
                } label: {
                    HStack {
                        Text(tr("Далее: выбрать отели", "Next: choose hotels", "Keyingi: mehmonxonalar", "Кейинги: меҳмонхоналар"))
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .frame(height: 56)
                }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .disabled(!isValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .navigationDestination(isPresented: $showHotels) {
            PrimaryHotelView(entryMode: .flightFirst, transferAlreadySelected: true)
        }
        .onAppear { selected = journey.selectedTransferVehicle ?? journey.recommendedTransferVehicle() }
        .navigationTitle(tr("Трансфер", "Transfer", "Transfer", "Трансфер"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
