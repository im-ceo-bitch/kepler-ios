import Foundation

private struct BookingContactStartRequest: Encodable { let phone: String }
private struct BookingContactConfirmRequest: Encodable { let challengeID: String; let code: String }
private struct BookingContactAttachRequest: Encodable { let verificationToken: String }

struct BookingContactStartResponse: Decodable { let challengeID: String; let expiresAt: String }
struct BookingContactConfirmResponse: Decodable {
    let phone: String
    let verificationToken: String
}

enum IumrahBookingContactError: LocalizedError {
    case invalidPhone
    var errorDescription: String? { "The verification phone number changed. Please request a new code." }
}

/// Guest booking verification. Does not authenticate or register an iumrah account.
struct IumrahBookingContactService {
    private let api = APIClient.shared

    func requestCode(phone: String) async throws -> BookingContactStartResponse {
        try await api.post(
            "/api/package/booking-contact/sms/start",
            body: BookingContactStartRequest(phone: phone)
        )
    }

    func confirmCode(challengeID: String, code: String) async throws -> BookingContactConfirmResponse {
        try await api.post(
            "/api/package/booking-contact/sms/confirm",
            body: BookingContactConfirmRequest(challengeID: challengeID, code: code)
        )
    }

    func attachVerifiedPhone(verificationToken: String, bookingID: String, bookingToken: String) async throws {
        let _: IumrahSimpleResponse = try await api.post(
            "/api/package/booking/\(bookingID)/verified-phone",
            body: BookingContactAttachRequest(verificationToken: verificationToken),
            headers: ["x-booking-token": bookingToken]
        )
    }
}
