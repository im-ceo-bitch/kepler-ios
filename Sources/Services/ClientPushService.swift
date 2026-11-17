import Foundation

struct ClientPushService {
    private let api = APIClient.shared

    func register(
        deviceToken: String,
        bookingID: String,
        headers: [String: String],
        locale: String,
        environment: String = "production"
    ) async throws -> Bool? {
        let response: ClientPushRegistrationResponse = try await api.post(
            "/api/catalog/hotels/client/push/devices",
            body: ClientPushRegistrationRequest(
                deviceToken: deviceToken,
                bookingID: bookingID,
                environment: environment,
                appBundleID: AppIdentity.runtimeBundleID,
                locale: locale, notifyCreated: false
            ),
            headers: headers
        )
        return response.ready
    }
    func notifyCreated(deviceToken: String, bookingID: String, bookingToken: String, locale: String) async throws -> Bool {
        let response: ClientPushRegistrationResponse = try await api.post("/api/catalog/hotels/client/push/devices",
            body: ClientPushRegistrationRequest(deviceToken: deviceToken, bookingID: bookingID, environment: "production", appBundleID: AppIdentity.runtimeBundleID, locale: locale, notifyCreated: true),
            headers: ["x-booking-token": bookingToken], timeoutInterval: 12)
        return response.initialPushAccepted == true
    }
}

private struct ClientPushRegistrationRequest: Encodable {
    let deviceToken: String
    let bookingID: String
    let environment: String
    let appBundleID: String
    let locale: String
    let notifyCreated: Bool
}

private struct ClientPushRegistrationResponse: Decodable {
    let ok: Bool
    let ready: Bool?
    let bookingID: String?
    let initialPushAccepted: Bool?
}
