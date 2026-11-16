import SwiftUI

/// Compatibility entry point. All packages use the same OTP booking flow.
struct LocalJourneyReviewView: View {
    var body: some View {
        LegacyFinalPackageView()
    }
}
