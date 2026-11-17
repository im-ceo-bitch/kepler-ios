import Foundation

extension ClientTripResponse {
    /// Source-compatible initializer for call sites created before `esims`
    /// became part of ClientTripResponse.
    init(ok: Bool?, trip: ClientTripSnapshot, assignment: ClientBookingAssignment?) {
        self.init(
            ok: ok,
            trip: trip,
            assignment: assignment,
            esims: nil,
            statusHistory: nil
        )
    }
}

extension BookingStore {
    func loadESIMs(for bookingID: String) async throws { try await loadTravelESIMs(for: bookingID) }
    func esimProfiles(for bookingID: String) -> [ClientESIMProfile] { travelESIMProfiles(for: bookingID) }
    func primaryESIM(for bookingID: String) -> ClientESIMProfile? { esimProfiles(for: bookingID).first }
}
