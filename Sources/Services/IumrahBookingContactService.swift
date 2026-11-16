import Foundation

private struct BookingContactStartRequest: Encodable { let phone: String }
private struct BookingContactEmailStartRequest: Encodable { let email: String; let locale: String }
private struct BookingContactEmailAttachRequest: Encodable { let verificationToken: String; let locale: String }
private struct BookingContactConfirmRequest: Encodable { let challengeID: String; let code: String }
private struct BookingContactAttachRequest: Encodable { let verificationToken: String }

struct BookingContactStartResponse: Decodable { let challengeID: String; let expiresAt: String }
struct BookingContactEmailConfirmResponse: Decodable {
    let email: String
    let verificationToken: String
}
struct BookingContactConfirmResponse: Decodable {
    let phone: String
    let verificationToken: String
}

enum IumrahBookingContactError: LocalizedError {
    case invalidPhone
    case invalidEmail
    var errorDescription: String? {
        switch self {
        case .invalidPhone: return "The verification phone number changed. Please request a new code."
        case .invalidEmail: return "The verification email changed. Please request a new code."
        }
    }
}

/// Guest booking verification and exchange of a server-confirmed contact for a profile session.
private struct BookingProfileExchangeRequest: Encodable {
    let bookingID: String
    let verificationToken: String
    let channel: String
    let device: IumrahClientDevice
}

struct IumrahBookingContactService {
    private let api = APIClient.shared

    // A verified, booking-bound proof is exchanged for an ordinary server session.
    // No client-generated token, password or automatic account lookup is allowed.
    func exchangeProfile(bookingID: String, bookingToken: String, verificationToken: String, channel: String, locale: String) async throws -> IumrahAccountAuthResponse {
        try await api.post("/api/package/client/account/booking-session", body: BookingProfileExchangeRequest(
            bookingID: bookingID, verificationToken: verificationToken, channel: channel,
            device: IumrahAccountDeviceIdentity.current(locale: locale)), headers: ["x-booking-token": bookingToken])
    }

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

    func requestEmailCode(email: String, locale: String) async throws -> BookingContactStartResponse {
        try await api.post("/api/package/booking-contact/email/start", body: BookingContactEmailStartRequest(email: email, locale: locale))
    }

    func confirmEmailCode(challengeID: String, code: String) async throws -> BookingContactEmailConfirmResponse {
        try await api.post("/api/package/booking-contact/email/confirm", body: BookingContactConfirmRequest(challengeID: challengeID, code: code))
    }

    func attachVerifiedEmail(verificationToken: String, bookingID: String, bookingToken: String, locale: String) async throws {
        let _: IumrahSimpleResponse = try await api.post(
            "/api/package/booking/\(bookingID)/verified-email",
            body: BookingContactEmailAttachRequest(verificationToken: verificationToken, locale: locale),
            headers: ["x-booking-token": bookingToken]
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
