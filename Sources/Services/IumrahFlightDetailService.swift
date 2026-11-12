import Foundation

struct IumrahFlightOperationalDetail: Decodable {
    struct Position: Decodable {
        let latitude: Double
        let longitude: Double
        let reportedAt: String?
        let altitudeFeet: Double?
        let speedKmh: Double?
    }
    let status: String?
    let updatedAt: String?
    let departureTerminal: String?
    let departureGate: String?
    let arrivalTerminal: String?
    let arrivalGate: String?
    let baggageBelt: String?
    let departureScheduled: String?
    let arrivalScheduled: String?
    let departureRevised: String?
    let arrivalRevised: String?
    let departureActual: String?
    let arrivalActual: String?
    let arrivalEstimatedUTC: String?
    let aircraft: String?
    let registration: String?
    let position: Position?
}

/// Read-only enrichment; no fare, booking, passenger or identity mutations.
actor IumrahFlightDetailService {
    static let shared = IumrahFlightDetailService()
    private struct Envelope: Decodable { let detail: IumrahFlightOperationalDetail? }
    private var inFlight: [String: Task<IumrahFlightOperationalDetail?, Never>] = [:]

    func detail(number: String, day: String, time: String, origin: String, destination: String) async -> IumrahFlightOperationalDetail? {
        guard let number = FlightReferenceCatalog.normalizedVerifiedFlightNumber(number), day.count == 10 else { return nil }
        let key = [number, day, time, origin, destination].joined(separator: "|")
        if let request = inFlight[key] { return await request.value }
        let request = Task<IumrahFlightOperationalDetail?, Never> {
            let query = [URLQueryItem(name: "number", value: number), .init(name: "date", value: day), .init(name: "time", value: time), .init(name: "origin", value: origin), .init(name: "destination", value: destination)]
            let envelope: Envelope? = try? await APIClient.shared.get("/api/package/flights/detail", query: query, timeoutInterval: 12)
            return envelope?.detail
        }
        inFlight[key] = request
        let result = await request.value
        inFlight[key] = nil
        return result
    }
}
