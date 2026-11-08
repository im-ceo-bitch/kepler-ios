import SwiftUI

// Compatibility entry point for any older in-app navigation or deep links.
// Use the consolidated Nuitee journey, not the retired 16-file flow.
struct FlightFirstPackageFlowView: View {
    var body: some View {
        NuiteeJourneyHotelsView()
    }
}
