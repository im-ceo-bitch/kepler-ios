import SwiftUI

struct LocalJourneyReviewView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var showContact = false
    @State private var info: StorefrontPackageInfoSheet?
    private var total: String {
        journey.quote.map { NuiteeHotelService.usd(NSDecimalNumber(decimal: $0.totalPackagePrice).doubleValue) } ?? "Цена уточняется"
    }
    private var rooms: [LocalJourneyRoom] { journey.localJourneyRooms.values.sorted { $0.id < $1.id } }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                IumrahJourneyHeader(showsNotifications: true) {
                    IumrahJourneyDisclosureCard(title: "Ваша поездка", total: total,
                        subtitle: "\(journey.trip.travelerCount) чел. · \(journey.trip.rooms) ном.", priceCaption: "Расчёт за всех") {
                        if let lines = journey.localPriceLines {
                            ForEach(lines) { line in
                                HStack(alignment: .top) {
                                    Text(line.title)
                                    Spacer()
                                    Text(NuiteeHotelService.usd(NSDecimalNumber(decimal: line.amount).doubleValue))
                                }.font(.caption)
                            }
                        } else { Text("Стоимость выбранного опубликованного рейса уточним в заявке.").font(.footnote) }
                        IumrahTransferRouteDetails()
                    }
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("Авиабилеты").font(.title2.bold())
                    ForEach(Array(journey.localJourneyFlights.enumerated()), id: \.element.id) { index, flight in
                        PackageFlightLegDetailCard(leg: StorefrontFlightLeg(airline: flight.airline,
                            flightNumber: flight.flightNumber, airlineCode: flight.airlineCode,
                            origin: flight.origin, destination: flight.destination, departureAt: flight.departureAt,
                            arrivalAt: flight.arrivalAt ?? "", durationMinutes: flight.durationMinutes,
                            stops: flight.stops, cabinClass: journey.trip.effectiveFlightFilters.cabinClass.rawValue),
                            direction: index == 0 ? "Туда" : "Обратно", language: settings.language)
                    }
                    Text("Отели и номера").font(.title2.bold())
                    ForEach(rooms) { room in
                        VStack(alignment: .leading, spacing: 8) {
                            PackageHotelDetailCard(hotel: StorefrontPackageHotel(id: room.hotel.id, name: room.hotel.name,
                                city: room.city == "madinah" ? "Madinah" : "Makkah", stars: room.hotel.roundedStars,
                                coverImageURL: room.hotel.coverImageURL,
                                nights: TripStayWindow(checkIn: room.checkin, checkOut: room.checkout).nights),
                                selectedRoomName: room.rate.roomName, chooseRoomText: room.rate.roomName,
                                language: settings.language, onOpen: {})
                            Text("\(room.checkin.formatted(date: .abbreviated, time: .omitted)) — \(room.checkout.formatted(date: .abbreviated, time: .omitted)) · \(NuiteeHotelService.usd(room.rate.price))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(room.rate.mealPlan).font(.caption)
                            Text(room.rate.cancellationDescription.isEmpty ? room.rate.cancellationTag : room.rate.cancellationDescription)
                                .font(.footnote).foregroundStyle(.secondary)
                            ForEach(Array(room.rate.chargeOnArrival.enumerated()), id: \.offset) { _, charge in
                                Text("Оплата в отеле: \(charge.amount.map { String($0) } ?? "уточняется") \(charge.currency)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        service("Гид", "person.fill", .guide)
                        service("Care", "heart.fill", .care)
                        VStack(spacing: 8) { Image(systemName: "car.fill"); Text("Трансфер").font(.caption) }
                            .frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
                    }
                    IumrahTransferRouteDetails().padding(16)
                        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 22))
                    Label("Визы · сопровождение · зияраты", systemImage: "checkmark.circle").font(.subheadline)
                    IumrahRefundPolicyCard(component: .package, compact: false)
                    PackagePurchaseTrustCard(language: settings.language) { info = .trust }
                    Text("Проверим наличие и подтвердим стоимость перед оплатой. Тарифы авиакомпаний и отелей могут измениться.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }
        }
        .background(Color.iumrahPageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .modifier(IumrahJourneyRefresh { await journey.refreshLocalJourneyRoomRates() })
        .task { journey.rebuildLocalJourneyQuote() }
        .safeAreaInset(edge: .bottom) {
            Button("Отправить заявку · \(total)") { showContact = true }
                .buttonStyle(IumrahPrimaryButtonStyle()).padding(.horizontal, 18).padding(.vertical, 8)
                .disabled(!journey.localRoomsComplete || !journey.transferSelectionConfirmed)
        }
        .sheet(isPresented: $showContact) { NavigationStack { LocalJourneyRequestView() }.modifier(IumrahJourneySheetStyle()) }
        .sheet(item: $info) { value in
            StorefrontPackageInformationSheet(kind: value, language: settings.language)
                .modifier(IumrahJourneySheetStyle())
        }
    }
    private func service(_ title: String, _ symbol: String, _ kind: StorefrontPackageInfoSheet) -> some View {
        Button { info = kind } label: {
            VStack(spacing: 8) { Image(systemName: symbol); Text(title).font(.caption) }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}

private struct LocalJourneyRequestView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var account: IumrahAccountStore
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var sending = false
    @State private var response: IumrahCarePackageRequestResponse?
    @State private var error: String?
    var body: some View {
        Form {
            if let response {
                Section("Заявка отправлена") {
                    Text(response.requestID)
                    Text("Свяжемся с вами после проверки наличия. Оплата ещё не требуется.")
                }
            } else {
                Section("Контактные данные") {
                    TextField("Имя", text: $firstName).textContentType(.givenName)
                    TextField("Фамилия", text: $lastName).textContentType(.familyName)
                    TextField("Телефон", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button { Task { await submit() } } label: {
                    if sending { ProgressView() } else { Text("Отправить заявку") }
                }.buttonStyle(IumrahPrimaryButtonStyle())
                    .disabled(sending || firstName.trimmingCharacters(in: .whitespaces).isEmpty || phone.filter(\.isNumber).count < 7)
            }
        }
        .navigationTitle("Заявка на поездку")
        .onAppear {
            if let profile = account.account {
                firstName = profile.firstName; lastName = profile.lastName
            }
        }
    }
    @MainActor private func submit() async {
        guard !sending else { return }
        sending = true; error = nil
        defer { sending = false }
        let trip = journey.trip
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
        let snapshot = LocalJourneyRequestSnapshot(version: 1, trip: trip, flights: journey.localJourneyFlights,
            rooms: Array(journey.localJourneyRooms.values), transfer: journey.selectedTransferVehicle?.rawValue ?? "carnival",
            trainTickets: journey.haramainTrainSelected ? journey.haramainTicketCount : 0,
            trainClass: journey.haramainFareClass.rawValue, estimatedTotalUSD: journey.quote?.totalPackagePrice)
        var request = IumrahCarePackageRequest(locale: settings.language.rawValue, firstName: firstName, lastName: lastName,
            phone: phone, telegram: "", accountID: account.iumrahID, originCode: trip.originCode, timingMode: .exactDates,
            preferredMonth: nil, flexibleWindowDays: nil, exactStartDate: formatter.string(from: trip.departureDate),
            exactEndDate: formatter.string(from: trip.returnDate), adults: trip.adults, children: trip.children,
            infants: trip.infants, rooms: trip.rooms, scope: trip.scope.rawValue, firstSaudiCity: trip.arrivalAirport.rawValue,
            priority: .balanced, hotelClass: trip.hotelStars, transferPreference: journey.selectedTransferVehicle == .yukon ? .vip : .comfortable,
            directFlightsPreferred: journey.localJourneyFlights.allSatisfy { $0.stops == 0 }, checkedBaggagePreferred: true,
            includeZiyarat: true, includeESIM: false, guidePreference: .live, budgetUSD: nil,
            notes: "Конфигуратор: выбранные рейсы и номера Nuitee в configuration. Локальная оценка, требуется подтверждение наличия и цены.")
        request.configuration = snapshot
        do {
            let result = try await IumrahCareRequestService().submit(request, accountToken: account.bearerToken)
            guard result.ok else { throw LocalPricingError.invalidComponents }
            response = result
        } catch { self.error = error.localizedDescription }
    }
}
