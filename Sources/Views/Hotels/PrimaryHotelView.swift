import SwiftUI

enum PrimaryHotelEntryMode { case standard, flightFirst }

/// Compatibility entry point. Published and manual flights use the very same
/// supplier catalogue, rates and room selection as Smart. No legacy hotel fetch.
struct PrimaryHotelView: View {
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var settings: AppSettingsStore
    @State private var ready = false
    @State private var needsFlights = false
    @State private var error: String?
    @State private var loading = false
    var familyFlow = false
    var entryMode: PrimaryHotelEntryMode = .standard
    var transferAlreadySelected = false

    var body: some View {
        Group {
            if ready {
                NuiteeJourneyHotelsView(transferAlreadySelected: transferAlreadySelected, familyFlow: familyFlow)
            } else if needsFlights {
                IumrahGuidedFlightSelectionView()
            } else {
                VStack(spacing: 16) {
                    if let error {
                        Text(ConfiguratorBookingCopy.message(error, language: settings.language)).font(.subheadline).multilineTextAlignment(.center)
                        Button(IumrahFlightCopy.text(settings.language, "Повторить", "Retry", "Qayta urinish", "Қайта уриниш")) { Task { await prepare() } }
                            .buttonStyle(IumrahPrimaryButtonStyle())
                    } else { ProgressView() }
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.iumrahPageBackground)
        .task { if !ready && !needsFlights { await prepare() } }
    }

    @MainActor private func prepare() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        if journey.usesLocalJourney && journey.localJourneyFlights.count == 2 { ready = true; return }
        if journey.packageFlightPath != .publishedDirect && journey.packageFlightPath != .aviasalesSelected {
            needsFlights = true; return
        }
        if journey.packageFlightPath == .publishedDirect && !journey.hasCompletePublishedFlightSelection {
            needsFlights = true; return
        }
        if journey.packageFlightPath == .aviasalesSelected && !journey.hasCompleteStagedFlightSelection {
            needsFlights = true; return
        }
        do {
            try await journey.prepareUnifiedHotelSelection()
            guard !Task.isCancelled else { return }
            ready = true
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
    }
}
