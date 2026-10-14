import SwiftUI

/// Prices in this row are never inferred from nightly hotel prices. When a
/// verified flight and selected package quote exist, compare two independent
/// server quotes for exactly the same itinerary and traveller configuration.
/// Without a verifiable quote the UI deliberately shows no invented delta.
struct HotelPackageDeltaText: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore

    let hotel: HotelSummary
    let city: HotelSelectionRole
    let isSelected: Bool
    let emptyLabel: String

    @State private var alternativeQuote: PackageQuote?
    @State private var loading = false

    private var referenceQuote: PackageQuote? {
        journey.hasFinalGeneratorQuote ? journey.quote : nil
    }

    private var comparisonKey: String {
        [hotel.id, city.rawValue, referenceQuote?.quoteId ?? "",
         journey.selectedHotel?.id ?? "", journey.selectedMadinahHotel?.id ?? "",
         journey.selectedRoom?.id ?? "", journey.selectedMadinahRoom?.id ?? ""].joined(separator: "|")
    }

    var body: some View {
        HStack(spacing: 4) {
            if let base = referenceQuote, isSelected {
                Text(money(0, currency: base.currency))
                    .foregroundStyle(.secondary)
            } else if let base = referenceQuote, let candidate = alternativeQuote,
                      base.currency == candidate.currency {
                let delta = candidate.totalPackagePrice - base.totalPackagePrice
                let signed = delta > 0 ? "+" : (delta < 0 ? "−" : "")
                let amount = delta < 0 ? -delta : delta
                Text("\(candidate.isEstimated || base.isEstimated ? "≈ " : "")\(signed)\(money(amount, currency: candidate.currency))")
                    .foregroundStyle(delta > 0 ? Color.orange : (delta < 0 ? Color.green : Color.secondary))
            } else if loading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Text(emptyLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.monospacedDigit().weight(.bold))
        .task(id: comparisonKey) {
            await loadAlternativeQuote()
        }
    }

    @MainActor
    private func loadAlternativeQuote() async {
        alternativeQuote = nil
        guard !isSelected, referenceQuote != nil,
              let outbound = journey.selectedOutbound, outbound.isVerifiedForBooking else { return }
        let inbound = journey.selectedInbound
        if journey.trip.isRoundTripFlight && (inbound == nil || inbound?.isVerifiedForBooking != true) {
            return
        }

        loading = true
        defer { loading = false }

        // Small stagger on appearance avoids a burst of simultaneous requests.
        try? await Task.sleep(for: .milliseconds(170))
        guard !Task.isCancelled else { return }

        let makkahID = city == .makkah ? hotel.id : journey.selectedHotel?.id
        let madinahID = city == .madinah ? hotel.id : journey.selectedMadinahHotel?.id
        guard let makkahID else { return }
        let roomID = city == .makkah ? nil : (journey.selectedRoom?.id ?? journey.selectedRoomCategory?.id)
        let madinahRoomID = city == .madinah ? nil : (journey.selectedMadinahRoom?.id ?? journey.selectedMadinahRoomCategory?.id)

        do {
            let preview = try await RemotePackageEngineClient().packageQuote(
                trip: journey.trip,
                pricingOffer: inbound ?? outbound,
                outboundOffer: outbound,
                inboundOffer: inbound,
                makkahHotelID: makkahID,
                makkahRoomID: roomID,
                madinahHotelID: madinahID,
                madinahRoomID: madinahRoomID,
                includeHaramainTrain: journey.haramainTrainSelected,
                transferVehicle: journey.selectedTransferVehicle,
                haramainFareClass: journey.haramainFareClass,
                haramainTicketCount: journey.haramainTicketCount
            )
            guard !Task.isCancelled else { return }
            alternativeQuote = preview
        } catch {
            // Network error or a hotel without a confirmed catalogue rate:
            // no delta is shown until the server can price that alternative.
            alternativeQuote = nil
        }
    }

    private func money(_ amount: Decimal, currency: String) -> String {
        NSDecimalNumber(decimal: amount).doubleValue
            .formatted(.currency(code: currency).precision(.fractionLength(0)))
    }
}
