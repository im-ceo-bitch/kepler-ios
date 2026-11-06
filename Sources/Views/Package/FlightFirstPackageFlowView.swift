import SwiftUI

/// Flight First starts in the Hotels tab after a traveler chooses flights there.
/// Navigation remains in that tab through hotels, transfer and package review.
/// It skips the generic TripBuilder and preserves the selected fare, dates, party,
/// and Makkah/Madinah scope in the existing JourneyStore.
struct FlightFirstPackageFlowView: View {
    var body: some View {
        PrimaryHotelView(entryMode: .flightFirst)
    }
}
