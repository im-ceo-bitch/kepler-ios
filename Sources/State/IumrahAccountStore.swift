import Foundation
import Security
import Combine

@MainActor
final class IumrahAccountStore: ObservableObject {
    @Published private(set) var account: IumrahAccountProfile?
    @Published private(set) var isRestoring = false
    @Published private(set) var lastError: String?

    private let service = IumrahAccountService()
    @Published private(set) var dashboardRewards: IumrahFriendsDashboard?
    @Published private(set) var dashboardRewardsLoading = false
    @Published private(set) var dashboardRewardsStale = false
    private var dashboardRewardsLoadedAt: Date?
    private var dashboardRequest: Task<IumrahFriendsDashboard, Error>?
    private var dashboardRequestID: UUID?
    private var token: String? {
        didSet {
            guard oldValue != token else { return }
            dashboardRequest?.cancel()
            dashboardRequest = nil
            dashboardRequestID = nil
            dashboardRewards = nil
            dashboardRewardsLoadedAt = nil
            dashboardRewardsLoading = false
            dashboardRewardsStale = false
        }
    }

    init() {
        LegacyClientIdentityCleanup.purge()
        if let saved = IumrahAccountVault.load() {
            token = saved.token
            account = saved.account
        }
    }

    var isAuthenticated: Bool { token != nil && account != nil }
    var iumrahID: String? { account?.iumrahID }
    var bearerToken: String? { token }

    func authorizationHeaders(bookingToken: String? = nil) -> [String: String] {
        var headers: [String: String] = [:]
        if let token, !token.isEmpty { headers["Authorization"] = "Bearer \(token)" }
        if let bookingToken, !bookingToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headers["x-booking-token"] = bookingToken
        }
        return headers
    }

    func restore() async {
        guard let token else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let profile = try await service.session(token: token)
            guard self.token == token else { return }
            account = profile
            IumrahAccountVault.save(.init(token: token, account: profile))
            _ = try? await service.registerCurrentSession(token: token, locale: Locale.current.identifier)
            lastError = nil
        } catch {
            guard self.token == token else { return }
            // A transient network error must not erase the saved trip profile.
            // Protected server requests still require a valid bearer session.
            let rejected: Bool
            switch error {
            case APIError.status(let status): rejected = status == 401 || status == 403
            case APIError.server(let status, _): rejected = status == 401 || status == 403
            default: rejected = false
            }
            if rejected {
                self.token = nil
                account = nil
                IumrahAccountVault.clear()
            }
            lastError = rejected ? nil : error.localizedDescription
        }
    }

    @discardableResult
    func activate(bookingID: String, bookingToken: String, password: String, locale: String = Locale.current.identifier) async throws -> IumrahAccountProfile {
        let response = try await service.activate(
            bookingID: bookingID,
            bookingToken: bookingToken,
            password: password,
            locale: locale
        )
        setSession(response)
        return response.account
    }

    func startActivationEmail(bookingID: String, bookingToken: String, email: String, locale: String) async throws -> IumrahEmailChallengeStartResponse {
        try await service.startActivationEmail(
            bookingID: bookingID,
            bookingToken: bookingToken,
            email: email,
            locale: locale
        )
    }

    @discardableResult
    func confirmActivationEmail(
        bookingID: String,
        bookingToken: String,
        challengeID: String,
        code: String,
        locale: String
    ) async throws -> IumrahAccountProfile {
        let response = try await service.confirmActivationEmail(
            bookingID: bookingID,
            bookingToken: bookingToken,
            challengeID: challengeID,
            code: code,
            locale: locale
        )
        setSession(response)
        return response.account
    }

    func startActivationSMS(bookingID: String, bookingToken: String, phone: String, locale: String) async throws -> IumrahPhoneChallengeStartResponse {
        try await service.startActivationSMS(
            bookingID: bookingID,
            bookingToken: bookingToken,
            phone: phone,
            locale: locale
        )
    }

    @discardableResult
    func confirmActivationSMS(
        bookingID: String,
        bookingToken: String,
        challengeID: String,
        code: String,
        locale: String
    ) async throws -> IumrahAccountProfile {
        let response = try await service.confirmActivationSMS(
            bookingID: bookingID,
            bookingToken: bookingToken,
            challengeID: challengeID,
            code: code,
            locale: locale
        )
        setSession(response)
        return response.account
    }

    @discardableResult
    func login(identifier: String, password: String, locale: String = Locale.current.identifier) async throws -> IumrahAccountProfile {
        let response = try await service.login(identifier: identifier, password: password, locale: locale)
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }

    func startEmailLogin(email: String, locale: String = Locale.current.identifier) async throws -> IumrahEmailChallengeStartResponse {
        try await service.startEmailLogin(email: email, locale: locale)
    }

    @discardableResult
    func confirmEmailLogin(challengeID: String, code: String, locale: String = Locale.current.identifier) async throws -> IumrahAccountProfile {
        let response = try await service.confirmEmailLogin(challengeID: challengeID, code: code, locale: locale)
        return await acceptVerifiedSession(response, locale: locale)
    }

    /// Used only for successful server-side OTP verification (registration and booking activation).
    /// Persists the SAME issued session instead of attempting a second password login.
    @discardableResult
    func acceptVerifiedSession(_ response: IumrahAccountAuthResponse, locale: String) async -> IumrahAccountProfile {
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }

    func startPhoneLogin(phone: String, locale: String = Locale.current.identifier) async throws -> IumrahPhoneLoginStartResponse {
        try await service.startPhoneLogin(phone: phone, locale: locale)
    }

    @discardableResult
    func confirmPhoneLogin(challengeID: String, code: String, locale: String = Locale.current.identifier) async throws -> IumrahAccountProfile {
        let response = try await service.confirmPhoneLogin(challengeID: challengeID, code: code, locale: locale)
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }


    func startPhoneRegistration(
        phone: String,
        firstName: String,
        lastName: String,
        locale: String = Locale.current.identifier
    ) async throws -> IumrahPhoneLoginStartResponse {
        try await service.startPhoneRegistration(
            phone: phone,
            firstName: firstName,
            lastName: lastName,
            locale: locale
        )
    }

    @discardableResult
    func confirmPhoneRegistration(
        challengeID: String,
        code: String,
        locale: String = Locale.current.identifier
    ) async throws -> IumrahAccountProfile {
        let response = try await service.confirmPhoneRegistration(
            challengeID: challengeID,
            code: code,
            locale: locale
        )
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }

    @discardableResult
    func signInWithApple(_ credential: IumrahAppleCredential, locale: String) async throws -> IumrahAccountProfile {
        let response = try await service.signInWithApple(credential, locale: locale)
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }

    @discardableResult
    func signInWithGoogle(_ credential: IumrahGoogleCredential, locale: String) async throws -> IumrahAccountProfile {
        let response = try await service.signInWithGoogle(credential, locale: locale)
        setSession(response)
        _ = try? await service.registerCurrentSession(token: response.session.token, locale: locale)
        return response.account
    }

    @discardableResult
    func updateProfile(firstName: String, lastName: String, phone: String, email: String, telegram: String, whatsapp: String) async throws -> IumrahAccountProfile {
        guard let token else { throw APIError.status(401) }
        let profile = try await service.updateProfile(
            .init(firstName: firstName, lastName: lastName, phone: phone, email: email, telegram: telegram, whatsapp: whatsapp),
            token: token
        )
        account = profile
        lastError = nil
        IumrahAccountVault.save(.init(token: token, account: profile))
        return profile
    }

    func deleteAccount() async throws {
        guard let token else { throw APIError.status(401) }
        try await service.deleteAccount(token: token)
        guard self.token == token else { return }
        await logout()
    }

    func logout() async {
        let previousToken = token
        IumrahGoogleSignInSupport.signOutProviderSession()
        token = nil
        account = nil
        lastError = nil
        IumrahAccountVault.clear()
        if let previousToken { await service.logout(token: previousToken) }
    }

    func walletPassData() async throws -> Data {
        guard let token else { throw APIError.status(401) }
        return try await service.walletPass(token: token)
    }

    func publicIdentityLink() async throws -> IumrahPublicIdentityLinkResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.publicIdentityLink(token: token)
    }

    func securityOverview(locale: String) async throws -> IumrahSecurityOverview {
        guard let token else { throw APIError.status(401) }
        _ = try await service.registerCurrentSession(token: token, locale: locale)
        return try await service.securityOverview(token: token)
    }

    func refreshDashboardRewards(force: Bool = false) async {
        guard isAuthenticated else { return }
        if !force, let loaded = dashboardRewardsLoadedAt, Date().timeIntervalSince(loaded) < 55 { return }
        _ = try? await rewardsDashboard()
    }

    func rewardsDashboard() async throws -> IumrahFriendsDashboard {
        guard let token, isAuthenticated else { throw APIError.status(401) }
        if let request = dashboardRequest {
            let data = try await request.value
            guard self.token == token, isAuthenticated else { throw APIError.status(401) }
            return data
        }
        let requestID = UUID()
        dashboardRequestID = requestID
        dashboardRewardsLoading = true
        let request = Task<IumrahFriendsDashboard, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                let data: IumrahFriendsDashboard
                do { data = try await self.service.friendsDashboard(token: token) }
                catch {
                    try Task.checkCancellation()
                    guard self.token == token else { throw APIError.status(401) }
                    _ = try await self.service.registerCurrentSession(token: token, locale: Locale.current.identifier)
                    data = try await self.service.friendsDashboard(token: token)
                }
                try Task.checkCancellation()
                guard self.token == token, self.isAuthenticated else { throw APIError.status(401) }
                self.dashboardRewards = data
                self.dashboardRewardsStale = false
                self.dashboardRewardsLoadedAt = Date()
                return data
            } catch {
                if self.token == token, self.dashboardRequestID == requestID {
                    switch error {
                    case APIError.status(let code) where code == 401 || code == 403:
                        self.dashboardRewards = nil; self.dashboardRewardsLoadedAt = nil
                    case APIError.server(let code, _) where code == 401 || code == 403:
                        self.dashboardRewards = nil; self.dashboardRewardsLoadedAt = nil
                    default: break
                    }
                    self.dashboardRewardsStale = self.dashboardRewards != nil
                }
                throw error
            }
        }
        dashboardRequest = request
        defer {
            if dashboardRequestID == requestID {
                dashboardRequest = nil
                dashboardRequestID = nil
                dashboardRewardsLoading = false
            }
        }
        let data = try await request.value
        guard self.token == token, isAuthenticated else { throw APIError.status(401) }
        return data
    }

    func friendsDashboard() async throws -> IumrahFriendsDashboard {
        try await rewardsDashboard()
    }

    func claimPrimaryDevice(password: String) async throws -> IumrahSecurityOverview {
        guard let token else { throw APIError.status(401) }
        return try await service.claimPrimaryDevice(password: password, token: token)
    }


    func authorizeSensitiveAction(password: String) async throws -> IumrahSensitiveAuthorizationResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.authorizeSensitiveAction(password: password, token: token)
    }


    func authorizeSensitiveActionWithApple(_ credential: IumrahAppleCredential) async throws -> IumrahSensitiveAuthorizationResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.authorizeSensitiveActionWithApple(credential, token: token)
    }

    func authorizeSensitiveActionWithGoogle(_ credential: IumrahGoogleCredential) async throws -> IumrahSensitiveAuthorizationResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.authorizeSensitiveActionWithGoogle(credential, token: token)
    }

    func startPrimaryRecovery(method: String, locale: String) async throws -> IumrahPrimaryRecoveryStartResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.startPrimaryRecovery(method: method, locale: locale, token: token)
    }

    func confirmPrimaryRecovery(method: String, challengeID: String, code: String) async throws -> IumrahSensitiveAuthorizationResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.confirmPrimaryRecovery(method: method, challengeID: challengeID, code: code, token: token)
    }

    func terminateSecuritySession(id: String) async throws -> Bool {
        guard let token else { throw APIError.status(401) }
        let response = try await service.terminateSession(id: id, token: token)
        if response.signedOut { clearLocalSession() }
        return response.signedOut
    }

    func linkApple(_ credential: IumrahAppleCredential) async throws -> IumrahAppleLinkResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.linkApple(credential, token: token)
    }

    func unlinkApple() async throws {
        guard let token else { throw APIError.status(401) }
        _ = try await service.unlinkApple(token: token)
    }

    func linkGoogle(_ credential: IumrahGoogleCredential) async throws -> IumrahGoogleLinkResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.linkGoogle(credential, token: token)
    }

    func unlinkGoogle() async throws {
        guard let token else { throw APIError.status(401) }
        _ = try await service.unlinkGoogle(token: token)
    }

    func startPhoneVerification(phone: String, locale: String, securityProof: String) async throws -> IumrahPhoneChallengeStartResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.startPhoneVerification(phone: phone, locale: locale, securityProof: securityProof, token: token)
    }

    func confirmPhoneVerification(challengeID: String, code: String, securityProof: String) async throws -> IumrahPhoneVerificationResponse {
        guard let token else { throw APIError.status(401) }
        let response = try await service.confirmPhoneVerification(challengeID: challengeID, code: code, securityProof: securityProof, token: token)
        if let profile = account {
            let updated = IumrahAccountProfile(
                iumrahID: profile.iumrahID,
                displayName: profile.displayName,
                firstName: profile.firstName,
                lastName: profile.lastName,
                phone: response.phone,
                email: profile.email,
                telegram: profile.telegram,
                whatsapp: profile.whatsapp
            )
            account = updated
            IumrahAccountVault.save(.init(token: token, account: updated))
        }
        return response
    }

    func startEmailVerification(email: String, locale: String, securityProof: String) async throws -> IumrahEmailChallengeStartResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.startEmailVerification(email: email, locale: locale, securityProof: securityProof, token: token)
    }

    func confirmEmailVerification(challengeID: String, code: String, securityProof: String) async throws -> IumrahEmailChallengeConfirmResponse {
        guard let token else { throw APIError.status(401) }
        let response = try await service.confirmEmailVerification(challengeID: challengeID, code: code, securityProof: securityProof, token: token)
        if let profile = account {
            let updated = IumrahAccountProfile(
                iumrahID: profile.iumrahID,
                displayName: profile.displayName,
                firstName: profile.firstName,
                lastName: profile.lastName,
                phone: profile.phone,
                email: response.email,
                telegram: profile.telegram,
                whatsapp: profile.whatsapp
            )
            account = updated
            IumrahAccountVault.save(.init(token: token, account: updated))
        }
        return response
    }

    func changePassword(currentPassword: String, newPassword: String) async throws -> IumrahPasswordChangeResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.changePassword(currentPassword: currentPassword, newPassword: newPassword, token: token)
    }

    func startPasswordRecovery(email: String, locale: String) async throws -> IumrahEmailChallengeStartResponse {
        try await service.startPasswordRecovery(email: email, locale: locale)
    }

    func confirmPasswordRecovery(challengeID: String, code: String, newPassword: String) async throws -> IumrahPasswordRecoveryResponse {
        try await service.confirmPasswordRecovery(challengeID: challengeID, code: code, newPassword: newPassword)
    }

    func linkBooking(bookingID: String, bookingToken: String) async throws -> IumrahAccountLinkBookingResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.linkBooking(bookingID: bookingID, bookingToken: bookingToken, token: token)
    }

    func accountTrips() async throws -> [ClientTripSnapshot] {
        guard let token else { throw APIError.status(401) }
        return try await service.trips(token: token)
    }

    func tripDetail(bookingID: String) async throws -> IumrahAccountTripDetailResponse {
        guard let token else { throw APIError.status(401) }
        return try await service.tripDetail(bookingID: bookingID, token: token)
    }

    private func setSession(_ response: IumrahAccountAuthResponse) {
        IumrahReferralLink.clear()
        token = response.session.token
        account = response.account
        lastError = nil
        IumrahAccountVault.save(.init(token: response.session.token, account: response.account))
    }

    private func clearLocalSession() {
        IumrahGoogleSignInSupport.signOutProviderSession()
        token = nil
        account = nil
        lastError = nil
        IumrahAccountVault.clear()
    }
}

private struct StoredIumrahAccountSession: Codable {
    let token: String
    let account: IumrahAccountProfile
}

private enum IumrahAccountVault {
    private static let service = "com.iumrah.app.iumrah-account"
    private static let account = "session"

    static func load() -> StoredIumrahAccountSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredIumrahAccountSession.self, from: data)
    }

    static func save(_ value: StoredIumrahAccountSession) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(base as CFDictionary, update as CFDictionary) == errSecSuccess { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
