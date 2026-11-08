import SwiftUI

/// The travel search is editable in place without presenting a fake glass sheet.
/// A draft is committed atomically, so changing a field cannot silently retain
/// a previously selected fare for another route or travel date.
struct IumrahFlightSearchInlineEditor: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    let onSearch: () -> Void
    @State private var draft = TripDraft()
    @State private var selectedCabin: FlightCabinClass = .economy

    private var isValid: Bool {
        draft.canContinue && draft.departureDate >= Calendar.current.startOfDay(for: Date()) &&
            draft.infants <= draft.adults
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AirportSelectorButton(airport: $draft.originAirport,
                                  fallbackCode: $draft.origin,
                                  cornerRadius: 16, monochrome: true)
            Picker(label("Маршрут", "Route"), selection: $draft.scope) {
                Text(label("Только Мекка", "Makkah only")).tag(JourneyScope.makkahOnly)
                Text(label("Мекка и Медина", "Makkah & Madinah")).tag(JourneyScope.makkahAndMadinah)
            }
            .pickerStyle(.segmented)
            if draft.scope == .makkahAndMadinah {
                Picker(label("Прилёт", "Arrival"), selection: $draft.arrivalAirport) {
                    Text(label("Джидда", "Jeddah")).tag(SaudiArrivalAirport.jeddah)
                    Text(label("Медина", "Madinah")).tag(SaudiArrivalAirport.madinah)
                }
                .pickerStyle(.segmented)
            }
            DatePicker(label("Туда", "Outbound"), selection: $draft.departureDate,
                       in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                .onChange(of: draft.departureDate) { _, newDate in
                    if draft.returnDate <= newDate {
                        draft.returnDate = Calendar.current.date(byAdding: .day, value: 1, to: newDate) ?? newDate
                    }
                }
            DatePicker(label("Обратно", "Return"), selection: $draft.returnDate,
                       in: draft.departureDate..., displayedComponents: .date)
            VStack(spacing: 10) {
                Stepper(label("Взрослых", "Adults") + ": \(draft.adults)", value: $draft.adults, in: 1...9)
                Stepper(label("Детей", "Children") + ": \(draft.children)", value: $draft.children, in: 0...8)
            }
            .font(.subheadline)
            Stepper(label("Младенцев", "Infants") + ": \(draft.infants)", value: $draft.infants, in: 0...draft.adults)
                .font(.footnote)
            Picker(label("Класс перелёта", "Cabin"), selection: $selectedCabin) {
                Text(label("Эконом", "Economy")).tag(FlightCabinClass.economy)
                Text(label("Премиум", "Premium economy")).tag(FlightCabinClass.premiumEconomy)
                Text(label("Бизнес", "Business")).tag(FlightCabinClass.business)
                Text(label("Первый", "First")).tag(FlightCabinClass.first)
            }
            Button {
                guard isValid else { return }
                var committed = draft
                var filters = committed.effectiveFlightFilters
                filters.cabinClass = selectedCabin
                committed.flightFilters = filters
                committed.selectedReturnAirport = nil
                committed.saudiArrivalDate = nil
                journey.resetAfterTripChange()
                journey.clearStagedUmrahFlights()
                journey.trip = committed
                onSearch()
            } label: {
                Text(label("Обновить поиск", "Update results"))
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
            .disabled(!isValid)
        }
        .onAppear {
            draft = journey.trip
            selectedCabin = journey.trip.effectiveFlightFilters.cabinClass
        }
    }

    private func label(_ ru: String, _ en: String) -> String {
        switch settings.language {
        case .russian, .uzbekCyrillic: return ru
        default: return en
        }
    }
}
