import SwiftUI

struct BookingCheckoutView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var bookings: BookingStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var isSubmitting = false
    @State private var createdSession: StoredBookingSession?
    @State private var errorMessage: String?
    @State private var showProfileSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                summaryHero
                IumrahManualPaymentNotice()
                IumrahRefundPolicyCard(component: .package, compact: false)
                nextStepsCard
                actions
            }
            .padding(.horizontal, IumrahDesign.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 42)
        }
        .background(Color.iumrahPageBackground)
        .iumrahInternalNavigation(progress: .ready)
        .navigationDestination(item: $createdSession) { session in
            BookingDetailView(bookingID: session.id)
        }
        .navigationDestination(isPresented: $showProfileSheet) {
            IumrahBookingConfirmationView(createBooking: { profile in
                try await submitBooking(profile: profile)
            })
        }
    }

    private var summaryHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("checkout_title", settings.language))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(L10n.text("checkout_subtitle", settings.language))
                .font(.body)
                .foregroundStyle(.secondary)
            if let hotel = journey.selectedHotel, let quote = journey.quote {
                VStack(alignment: .leading, spacing: 10) {
                    Text(hotel.name).font(.headline)
                    if let roomCategory = journey.selectedRoomCategory {
                        Label(L10n.text(roomCategory.category.titleKey, settings.language), systemImage: "bed.double")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let room = journey.selectedRoom {
                        Label(room.name, systemImage: "bed.double")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(journey.trip.originCode) → \(journey.trip.outboundDestinationCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PackagePriceView(amount: quote.totalPackagePrice, currency: quote.currency, showsPerPerson: false)
                }
                .padding(16)
                .background(Color.iumrahRaisedBackground)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iumrahMarketingCard()
    }

    private var nextStepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("next_title", settings.language))
                .font(.headline)
            stepRow("01", L10n.text("next_one", settings.language))
            stepRow("02", L10n.text("next_two", settings.language))
            stepRow("03", L10n.text("next_three", settings.language))
            stepRow("04", L10n.text("next_four", settings.language))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .iumrahCard()
    }

    private func stepRow(_ number: String, _ body: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 30, height: 30)
                .background(Color.iumrahRaisedBackground)
                .clipShape(Circle())
            Text(body)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        VStack(spacing: 14) {
            if let createdSession {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("success_title", settings.language))
                        .font(.headline)
                    Text(L10n.text("success_body", settings.language))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text(L10n.format("booking_number_short", settings.language, createdSession.displayBookingNumber))
                        if let pilgrimID = createdSession.displayPilgrimID {
                            Text("· iumrah ID \(pilgrimID)")
                        }
                    }
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .iumrahCard()

                IumrahTelegramConnectCard(
                    session: createdSession,
                    style: .standard
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            Button {
                // Open a full screen, passport-name + guest SMS confirmation flow.
                showProfileSheet = true
            } label: {
                if isSubmitting {
                    ProgressView().tint(Color.iumrahPrimaryButtonText)
                } else {
                    Text(L10n.text("checkout_cta", settings.language))
                }
            }
            .buttonStyle(IumrahPrimaryButtonStyle())
            .disabled(isSubmitting)

            if createdSession != nil {
                NavigationLink {
                    BookingDetailView(bookingID: createdSession?.id ?? "")
                } label: {
                    Text(L10n.text("open_booking", settings.language))
                }
                .buttonStyle(IumrahSecondaryButtonStyle())
            }
        }
    }

    @MainActor
    private func submitBooking(profile: BookingPilgrimProfile) async throws -> StoredBookingSession {
        guard let hotel = journey.selectedHotel,
              let outbound = journey.selectedOutbound,
              let quote = journey.quote else { throw BookingStoreError.authoritativeQuoteRequired }
        let inbound = journey.selectedInbound
        guard !journey.trip.isRoundTripFlight || inbound != nil else { throw BookingStoreError.authoritativeQuoteRequired }
        return try await bookings.create(
            trip: journey.trip,
            hotel: hotel,
            madinahHotel: journey.selectedMadinahHotel,
            room: journey.selectedRoom,
            roomCategory: journey.selectedRoomCategory,
            madinahRoom: journey.selectedMadinahRoom,
            madinahRoomCategory: journey.selectedMadinahRoomCategory,
            transferVehicle: journey.selectedTransferVehicle ?? journey.recommendedTransferVehicle(),
            outbound: outbound,
            inbound: inbound,
            quote: quote,
            language: settings.language,
            pilgrimProfile: profile
        )
    }

}

