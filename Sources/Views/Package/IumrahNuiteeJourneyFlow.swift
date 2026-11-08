import SwiftUI

// COMPATIBILITY BRIDGE — the old Flight First Nuitee journey from the
// 16-file patch is retired. It used the former one-room, adult-only flow.
//
// The merged 32+16 patch's source of truth is NuiteeJourneyHotelsView,
// followed by TransferSelectionView and LocalJourneyReviewView.
// Keeping only this lightweight bridge prevents an old SwiftUI ViewBuilder
// from being compiled alongside the replacement journey and preserves any
// historic navigation that still instantiates the old Hotels view.
// Do not restore the old price-estimate or supplier-refresh implementations:
// JourneyStore and LocalPackagePricingEngine own the current calculation.
struct IumrahNuiteeJourneyHotelsView: View {
    var body: some View {
        NuiteeJourneyHotelsView()
    }
}
