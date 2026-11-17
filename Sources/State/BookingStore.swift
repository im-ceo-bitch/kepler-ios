import Foundation
import CryptoKit
import SwiftUI

enum BookingStoreError: LocalizedError {
    case permanentDeleteUnavailable
    case authoritativeQuoteRequired
    case identityPending

    var errorDescription: String? {
        switch self {
        case .permanentDeleteUnavailable:
            return "Permanent booking deletion is not available on the server."
        case .identityPending:
            return "Booking saved. Waiting for server booking number and iumrah ID. Retry without creating another booking."
        case .authoritativeQuoteRequired:
            return "The package price must be confirmed by the secure iumrah PackageEngine before booking."
        }
    }
}

@MainActor
final class BookingStore: ObservableObject {
    @Published private(set) var sessions: [StoredBookingSession] = []
    @Published private(set) var chats: [String: [ChatMessage]] = [:]
    @Published private var travelESIMs: [String: (proof: String, profiles: [ClientESIMProfile])] = [:]
    @Published private(set) var itineraries: [String: [BookingItineraryItem]] = [:]
    @Published private(set) var pushRegistrationReady: Bool?
    @Published private(set) var pushRegistrationError: String?

    private let bookingService = BookingService()
    private let packageEngine = RemotePackageEngineClient()
    private let hotelCatalogService = HotelCatalogService()
    private let chatService = ChatService()
    private let clientPushService = ClientPushService()
    private let accountService = IumrahAccountService()
    private let legacyStorageKey = "iumrah.booking.sessions.v1"
    @Published private var accountToken: String?
    private var chatCacheKeys: [String: String] = [:]
    private var chatCursors: [String: String] = [:]
    private var chatScopeVersions: [String: String] = [:]
    var hasCareAccount: Bool { accountToken?.isEmpty == false }
    // Home must never expose a cached booking from a different session while
    // account restoration is still in progress.
    func homeSessions(accountToken token: String?) -> [StoredBookingSession] {
        guard accountToken == token else { return [] }
        if token == nil { return sessions.filter { !$0.accessToken.isEmpty } }
        return sessions
    }
    var canUseCareChat: Bool {
        hasCareAccount && sessions.contains { !["COMPLETED", "CANCELLED"].contains($0.effectiveStatus.uppercased()) }
    }
    func canUseBookingCare(_ bookingID: String) -> Bool {
        if hasCareAccount { return canUseCareChat }
        guard bookingID != "account", let session = booking(id: bookingID), !session.accessToken.isEmpty else { return false }
        return !["COMPLETED", "CANCELLED"].contains(session.effectiveStatus.uppercased())
    }
    private var bookingScopeGeneration = UUID()
    private struct CheckoutCacheEntry {
        let value: IumrahCheckoutResponse
        let status: String
        let accessToken: String
        let date: Date
    }
    @Published private var checkoutCache: [String: CheckoutCacheEntry] = [:]
    private struct CheckoutRequest {
        let id: UUID
        let status: String
        let accessToken: String
        let task: Task<IumrahCheckoutResponse, Error>
    }
    private var checkoutRequests: [String: CheckoutRequest] = [:]
    private struct FriendsCacheEntry {
        let value: IumrahFriendsBookingSummary
        let accessToken: String
        let date: Date
    }
    @Published private var checkoutFriendsCache: [String: FriendsCacheEntry] = [:]

    // Private in-memory cache only. Every read is scoped to the current session.
    func cachedCheckout(id: String, token: String?) -> IumrahCheckoutResponse? {
        guard token == accountToken, let session = booking(id: id),
              let entry = checkoutCache[id], entry.accessToken == session.accessToken else { return nil }
        return entry.value
    }

    func loadCheckout(id: String, token: String?, force: Bool = false) async throws -> IumrahCheckoutResponse {
        guard token == accountToken, let session = booking(id: id) else { throw APIError.missingBookingToken }
        let status = session.effectiveStatus
        let access = session.accessToken
        let generation = bookingScopeGeneration
        if !force, let entry = checkoutCache[id], entry.accessToken == access,
           entry.status == status, Date().timeIntervalSince(entry.date) < 60 { return entry.value }
        if let running = checkoutRequests[id], running.status == status, running.accessToken == access {
            return try await running.task.value
        }
        checkoutRequests[id]?.task.cancel()
        let requestID = UUID()
        let service = accountService
        let task = Task { @MainActor [weak self] () throws -> IumrahCheckoutResponse in
            guard let self else { throw CancellationError() }
            defer {
                if self.checkoutRequests[id]?.id == requestID { self.checkoutRequests[id] = nil }
            }
            do {
                let value = try await service.checkout(bookingID: id, bookingToken: access, accountToken: token)
                guard !Task.isCancelled, self.bookingScopeGeneration == generation, self.accountToken == token,
                      self.booking(id: id)?.accessToken == access, self.checkoutRequests[id]?.id == requestID else { throw CancellationError() }
                BookingOfflineDocuments.reconcile(bookingID: id, proof: access, published: value.documents)
                self.checkoutCache[id] = CheckoutCacheEntry(value: value, status: status, accessToken: access, date: Date())
                return value
            } catch {
                // Never retain a protected snapshot after authorization is rejected.
                if self.bookingScopeGeneration == generation, self.checkoutRequests[id]?.id == requestID {
                    switch error {
                    case APIError.status(let code) where [401, 403, 404].contains(code): self.checkoutCache[id] = nil; self.checkoutFriendsCache[id] = nil; BookingOfflineDocuments.purge(bookingID: id, proof: access)
                    case APIError.server(let code, _) where [401, 403, 404].contains(code): self.checkoutCache[id] = nil; self.checkoutFriendsCache[id] = nil; BookingOfflineDocuments.purge(bookingID: id, proof: access)
                    default: break
                    }
                }
                throw error
            }
        }
        checkoutRequests[id] = CheckoutRequest(id: requestID, status: status, accessToken: access, task: task)
        return try await task.value
    }

    func cachedCheckoutFriends(id: String, token: String?) -> IumrahFriendsBookingSummary? {
        guard token != nil, token == accountToken, let session = booking(id: id),
              let entry = checkoutFriendsCache[id], entry.accessToken == session.accessToken else { return nil }
        return entry.value
    }

    func loadCheckoutFriends(id: String, token: String, force: Bool = false) async throws -> IumrahFriendsBookingSummary {
        guard token == accountToken, let session = booking(id: id) else { throw APIError.missingBookingToken }
        if !force, let entry = checkoutFriendsCache[id], entry.accessToken == session.accessToken,
           Date().timeIntervalSince(entry.date) < 60 { return entry.value }
        let generation = bookingScopeGeneration
        var headers = ["Authorization": "Bearer \(token)"]
        if !session.accessToken.isEmpty { headers["x-booking-token"] = session.accessToken }
        let value = try await bookingService.friendsSummary(id: id, headers: headers)
        guard !Task.isCancelled, generation == bookingScopeGeneration, token == accountToken,
              booking(id: id)?.accessToken == session.accessToken else { throw CancellationError() }
        checkoutFriendsCache[id] = FriendsCacheEntry(value: value, accessToken: session.accessToken, date: Date())
        return value
    }

    func careChatKey(for bookingID: String) -> String { hasCareAccount ? "account" : bookingID }
    private var chatLoads: [String: Task<[ChatMessage], Error>] = [:]
    private var chatAuthGeneration = UUID()


    init() {
        loadFromStorage()
    }

    func create(
        trip: TripDraft,
        hotel: HotelSummary,
        madinahHotel: HotelSummary? = nil,
        room: HotelRoom?,
        roomCategory: IumrahRoomCategoryOption? = nil,
        madinahRoom: HotelRoom? = nil,
        madinahRoomCategory: IumrahRoomCategoryOption? = nil,
        authoritativeMakkahRoomId: String? = nil,
        authoritativeMadinahRoomId: String? = nil,
        intercityTransport: ServerIntercityTransport? = nil,
        transferVehicle: TransferVehicleKind? = nil,
        outbound: FlightOffer,
        inbound: FlightOffer?,
        quote: PackageQuote,
        language: AppSettingsStore.Language,
        pilgrimProfile: BookingPilgrimProfile?,
        nuiteeRooms: [BookingNuiteeRoomSelection]? = nil
    ) async throws -> StoredBookingSession {
        guard quote.bookingAllowed != false, let quoteID = quote.quoteId,
              quoteID.hasPrefix("server-"),
              let quoteProof = quote.quoteProof,
              !quoteProof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookingStoreError.authoritativeQuoteRequired
        }

        let generation = bookingScopeGeneration
        let payload = BookingDraftBuilder.make(
            trip: trip,
            hotel: hotel,
            madinahHotel: madinahHotel,
            room: room,
            roomCategory: roomCategory,
            madinahRoom: madinahRoom,
            madinahRoomCategory: madinahRoomCategory,
            authoritativeMakkahRoomId: authoritativeMakkahRoomId,
            authoritativeMadinahRoomId: authoritativeMadinahRoomId,
            intercityTransport: intercityTransport,
            outbound: outbound,
            inbound: inbound,
            quote: quote,
            language: language,
            pilgrimProfile: pilgrimProfile,
            nuiteeRooms: nuiteeRooms
        )
        let response = try await bookingService.createBooking(payload)
        guard let token = response.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
            throw APIError.missingBookingToken
        }
        let serverProfile = response.booking.pilgrimProfile ?? pilgrimProfile
        var session = StoredBookingSession(
            id: response.booking.id,
            accessToken: token,
            booking: response.booking,
            travelerName: serverProfile?.displayName,
            telegram: serverProfile?.telegram,
            whatsapp: serverProfile?.whatsapp,
            outboundFlight: outbound,
            inboundFlight: inbound,
            hotelSelection: BookingHotelSelectionSnapshot(hotel: hotel, room: room, roomCategory: roomCategory, authoritativeRoomId: authoritativeMakkahRoomId),
            madinahHotelSelection: madinahHotel.map { BookingHotelSelectionSnapshot(hotel: $0, room: madinahRoom, roomCategory: madinahRoomCategory, authoritativeRoomId: authoritativeMadinahRoomId) }
        )
        if let trip = response.trip, trip.bookingID == session.id {
            session.mergeOperationalTrip(trip)
        }
        session.transferVehicle = transferVehicle ?? .carnival
        // Keep only the opaque proof until PackageEngine accepts responsibility for
        // the server-owned cost report. Persist immediately after the canonical booking
        // response so an app termination during Business/profile synchronization cannot
        // lose the reconciliation job. No supplier pricing is readable here.
        session.pendingGeneratorQuoteProof = quote.quoteProof
        guard generation == bookingScopeGeneration else { throw CancellationError() }
        upsert(session)

        // Hand the confidential report to PackageEngine immediately after the
        // canonical booking exists. PackageEngine either commits it to an existing
        // Business trip or durably queues it server-side until that trip is created.
        // This closes the crash window before account/profile synchronization.
        var pricingReportCommitted = false
        if let proof = session.pendingGeneratorQuoteProof, !proof.isEmpty {
            pricingReportCommitted = await commitPricingReportWithRetry(
                id: session.id,
                accessToken: session.accessToken,
                quoteProof: proof
            )
            if pricingReportCommitted {
                session.pendingGeneratorQuoteProof = nil
                guard generation == bookingScopeGeneration else { throw CancellationError() }
                upsert(session)
            }
        }

        if let accountToken, !accountToken.isEmpty,
           let linked = try? await accountService.linkBooking(bookingID: session.id, bookingToken: session.accessToken, token: accountToken) {
            session.pilgrimID = linked.pilgrimID
            session.bookingNumber = linked.bookingNumber
            session.bookingDisplayNumber = linked.bookingDisplayNumber
        }
        // First synchronize only the public generator trace. The confidential
        // supplier-cost report is never accepted from the client anymore.
        let generatorReportResult = await syncGeneratorReportWithRetry(
            id: session.id,
            accessToken: session.accessToken,
            generatorTrace: payload.booking.generatorTrace
        )
        if let operational = generatorReportResult {
            session.mergeOperationalTrip(operational.trip, statusHistory: operational.statusHistory)
            session.guide = operational.assignment?.guide
        }

        if let profile = serverProfile, !profile.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !profile.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let response = try? await bookingService.syncBookingProfile(
                id: session.id,
                accessToken: session.accessToken,
                profile: profile,
                generatorTrace: generatorReportResult == nil ? payload.booking.generatorTrace : nil
            ) {
                session.mergeOperationalTrip(response.trip, statusHistory: response.statusHistory)
                session.guide = response.assignment?.guide
            }
        }

        // Profile sync may have created the Business trip after the first commit
        // attempt. Give the server-owned report one final immediate chance here; a
        // pending proof is also retried by refreshAll if a transient race remains.
        if !pricingReportCommitted,
           let proof = session.pendingGeneratorQuoteProof, !proof.isEmpty {
            pricingReportCommitted = await commitPricingReportWithRetry(
                id: session.id,
                accessToken: session.accessToken,
                quoteProof: proof
            )
        }
        if pricingReportCommitted {
            session.pendingGeneratorQuoteProof = nil
        }
        guard generation == bookingScopeGeneration else { throw CancellationError() }
        upsert(session)
        if let makkahSelection = session.hotelSelection {
            _ = try? await bookingService.updateHotelSelection(
                id: session.id,
                accessToken: session.accessToken,
                role: .makkah,
                snapshot: makkahSelection
            )
        }
        if let madinahSelection = session.madinahHotelSelection {
            _ = try? await bookingService.updateHotelSelection(
                id: session.id,
                accessToken: session.accessToken,
                role: .madinah,
                snapshot: madinahSelection
            )
        }
        guard generation == bookingScopeGeneration else { throw CancellationError() }
        return session
    }

    private func syncGeneratorReportWithRetry(
        id: String,
        accessToken: String,
        generatorTrace: BookingGeneratorTrace?
    ) async -> ClientTripResponse? {
        guard generatorTrace != nil else { return nil }
        let retryDelaysMilliseconds = [0, 350, 900, 1_800]
        for (index, delayMilliseconds) in retryDelaysMilliseconds.enumerated() {
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
            do {
                return try await bookingService.syncGeneratorReport(
                    id: id,
                    accessToken: accessToken,
                    generatorTrace: generatorTrace
                )
            } catch {
                if index == retryDelaysMilliseconds.count - 1 {
                    #if DEBUG
                    print("[BookingStore] generator trace sync failed after retries: \(error)")
                    #endif
                }
            }
        }
        return nil
    }

    private func commitPricingReportWithRetry(
        id: String,
        accessToken: String,
        quoteProof: String
    ) async -> Bool {
        let retryDelaysMilliseconds = [0, 350, 900, 1_800]
        for (index, delayMilliseconds) in retryDelaysMilliseconds.enumerated() {
            if delayMilliseconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delayMilliseconds) * 1_000_000)
            }
            do {
                try await packageEngine.commitPricingReport(
                    bookingID: id,
                    bookingToken: accessToken,
                    quoteProof: quoteProof
                )
                return true
            } catch {
                if index == retryDelaysMilliseconds.count - 1 {
                    #if DEBUG
                    print("[BookingStore] server pricing report commit failed after retries: \(error)")
                    #endif
                }
            }
        }
        return false
    }

    /// Reconcile a committed booking without issuing another create request.
    func resolveBookingIdentity(_ saved: StoredBookingSession) async throws -> StoredBookingSession {
        guard var session = booking(id: saved.id) else { throw APIError.missingBookingToken }
        let generation = bookingScopeGeneration
        if session.hasServerIdentity { return session }
        let operational = try await bookingService.fetchOperationalTrip(
            id: session.id, headers: ["x-booking-token": session.accessToken]
        )
        guard generation == bookingScopeGeneration else { throw CancellationError() }
        guard operational.trip.bookingID == session.id else { throw BookingStoreError.identityPending }
        session.mergeOperationalTrip(operational.trip, statusHistory: operational.statusHistory)
        session.guide = operational.assignment?.guide ?? session.guide
        upsert(session)
        guard session.hasServerIdentity else { throw BookingStoreError.identityPending }
        return session
    }

    /// Refresh only the booking visible on the creation screen, without creating or syncing profiles.
    func refreshCreatedBookingStatus(id: String) async {
        guard let initial = booking(id: id), !initial.accessToken.isEmpty else { return }
        guard let response = try? await bookingService.fetchOperationalTrip(
            id: id, headers: ["x-booking-token": initial.accessToken]
        ), !Task.isCancelled, response.trip.bookingID == id,
            var current = booking(id: id), current.accessToken == initial.accessToken,
            current.operationStatus == initial.operationStatus else { return }
        current.mergeOperationalTrip(response.trip, statusHistory: response.statusHistory)
        current.guide = response.assignment?.guide ?? current.guide
        if current != booking(id: id) { upsert(current) }
    }

    func refreshAll() async {
        let generation = bookingScopeGeneration
        var staleBookingIDs = Set<String>()

        for session in sessions {
            guard generation == bookingScopeGeneration else { return }
            let bookingToken = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            do {
                if !bookingToken.isEmpty {
                    do {
                        let booking = try await bookingService.fetchBooking(id: session.id, accessToken: bookingToken)
                        var operational: ClientTripResponse?
                        if let profile = identityProfile(remote: booking.pilgrimProfile, session: session) {
                            operational = try? await bookingService.syncBookingProfile(
                                id: session.id,
                                accessToken: bookingToken,
                                profile: profile
                            )
                        }
                        if operational == nil {
                            operational = try? await bookingService.fetchOperationalTrip(
                                id: session.id,
                                headers: ["x-booking-token": bookingToken]
                            )
                        }
                        mergeRemoteBooking(booking, operational: operational, bookingID: session.id)
                    } catch {
                        // Booking proofs are intentionally short-lived. A stale proof must not
                        // freeze the status page when the same booking already belongs to the
                        // authenticated permanent iumrah account. Fall back only for auth
                        // failures; real missing-booking responses still go through cleanup.
                        guard let accountToken, !accountToken.isEmpty, isAuthorizationFailure(error) else { throw error }
                        let detail = try await accountService.tripDetail(bookingID: session.id, token: accountToken)
                        mergeRemoteBooking(
                            detail.booking,
                            operational: ClientTripResponse(ok: true, trip: detail.trip, assignment: detail.assignment, esims: detail.esims, statusHistory: detail.statusHistory),
                            bookingID: session.id
                        )
                    }
                } else if let accountToken, !accountToken.isEmpty {
                    let detail = try await accountService.tripDetail(bookingID: session.id, token: accountToken)
                    mergeRemoteBooking(
                        detail.booking,
                        operational: ClientTripResponse(ok: true, trip: detail.trip, assignment: detail.assignment, esims: detail.esims, statusHistory: detail.statusHistory),
                        bookingID: session.id
                    )
                }

                if !bookingToken.isEmpty,
                   let pendingProof = session.pendingGeneratorQuoteProof,
                   !pendingProof.isEmpty,
                   await commitPricingReportWithRetry(id: session.id, accessToken: bookingToken, quoteProof: pendingProof),
                   let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index].pendingGeneratorQuoteProof = nil
                }

                if let current = booking(id: session.id) {
                    await hydrateHotelSelectionIfNeeded(bookingID: session.id, role: .makkah)
                    if current.booking.input.includeMadinah {
                        await hydrateHotelSelectionIfNeeded(bookingID: session.id, role: .madinah)
                    }
                }
            } catch APIError.status(let code) where code == 404 || code == 410 {
                staleBookingIDs.insert(session.id)
            } catch APIError.server(let code, let message) where isRemoteMissing(code: code, message: message) {
                staleBookingIDs.insert(session.id)
            } catch {
                continue
            }
        }

        guard generation == bookingScopeGeneration else { return }
        for id in staleBookingIDs { purgeLocalBooking(id: id) }
        persist()
    }

    func setAccountToken(_ token: String?) {
        let next = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if next != accountToken {
            bookingScopeGeneration = UUID()
            for request in checkoutRequests.values { request.task.cancel() }
            checkoutRequests.removeAll()
            checkoutCache.removeAll()
            checkoutFriendsCache.removeAll()
            travelESIMs.removeAll()
            itineraries.removeAll()
            if accountToken != nil {
                BookingOfflineDocuments.purgeAll()
                sessions.removeAll()
                itineraries.removeAll()
                pushRegistrationReady = nil
                pushRegistrationError = nil
                UserDefaults.standard.removeObject(forKey: legacyStorageKey)
                persist()
            }
            chatAuthGeneration = UUID()
            for task in chatLoads.values { task.cancel() }
            chatLoads.removeAll()
            chats.removeAll()
            chatCursors.removeAll()
            chatScopeVersions.removeAll()
            chatCacheKeys.removeAll()
            // Disk caches are credential-scoped; remove on account transition to avoid retaining private chat history.
            if accountToken != nil { try? FileManager.default.removeItem(at: chatCacheDirectory) }
        }
        if accountToken != next { accountToken = next }
    }

    func restoreAccountTrips(token: String) async {
        guard accountToken == token else { return }
        let generation = bookingScopeGeneration
        guard let trips = try? await accountService.trips(token: token), generation == bookingScopeGeneration else { return }
        for trip in trips {
            guard let detail = try? await accountService.tripDetail(bookingID: trip.bookingID, token: token) else { continue }
            guard generation == bookingScopeGeneration, accountToken == token else { return }
            if let index = sessions.firstIndex(where: { $0.id == trip.bookingID }) {
                sessions[index].booking = detail.booking
                sessions[index].mergeOperationalTrip(detail.trip, statusHistory: detail.statusHistory)
                sessions[index].guide = detail.assignment?.guide ?? sessions[index].guide
                mergeRemoteHotelSelection(detail.booking.hotelSelection, into: &sessions[index].hotelSelection)
                mergeRemoteHotelSelection(detail.booking.madinahHotelSelection, into: &sessions[index].madinahHotelSelection)
            } else {
                let profile = detail.booking.pilgrimProfile
                var restored = StoredBookingSession(
                    id: trip.bookingID,
                    accessToken: "",
                    booking: detail.booking,
                    travelerName: profile?.displayName,
                    telegram: profile?.telegram,
                    whatsapp: profile?.whatsapp,
                    outboundFlight: nil,
                    inboundFlight: nil,
                    hotelSelection: detail.booking.hotelSelection,
                    madinahHotelSelection: detail.booking.madinahHotelSelection,
                    guide: detail.assignment?.guide
                )
                restored.mergeOperationalTrip(detail.trip, statusHistory: detail.statusHistory)
                sessions.append(restored)
            }
        }
        sessions.sort { $0.booking.createdAt > $1.booking.createdAt }
        persist()
    }

    func adoptOfferBooking(_ response: BookingCreateResponse) throws -> StoredBookingSession {
        guard let token = response.accessToken, !token.isEmpty else { throw APIError.missingBookingToken }
        let booking = response.booking
        if let existing = self.booking(id: booking.id) { return existing }
        var session = StoredBookingSession(id: booking.id, accessToken: token, booking: booking,
            travelerName: booking.pilgrimProfile?.displayName, telegram: booking.pilgrimProfile?.telegram,
            whatsapp: booking.pilgrimProfile?.whatsapp, outboundFlight: nil, inboundFlight: nil,
            hotelSelection: booking.hotelSelection, madinahHotelSelection: booking.madinahHotelSelection)
        if let trip = response.trip { session.mergeOperationalTrip(trip) }
        upsert(session)
        return session
    }

    func adoptRecoveredBooking(_ response: BookingCreateResponse, email: String?, phone: String?) throws -> StoredBookingSession {
        guard let token = response.accessToken, !token.isEmpty else { throw APIError.missingBookingToken }
        let booking = response.booking
        if let existing = self.booking(id: booking.id) {
            // The user explicitly recovered access; replace only this device's credential.
            BookingOfflineDocuments.purge(bookingID: booking.id, proof: existing.accessToken)
            checkoutRequests[booking.id]?.task.cancel(); checkoutRequests[booking.id] = nil
            checkoutCache[booking.id] = nil; checkoutFriendsCache[booking.id] = nil
            travelESIMs[booking.id] = nil; itineraries[booking.id] = nil
            chatAuthGeneration = UUID(); for task in chatLoads.values { task.cancel() }; chatLoads.removeAll()
            chats[booking.id] = nil; chatCacheKeys[booking.id] = nil; chatCursors[booking.id] = nil; chatScopeVersions[booking.id] = nil
        }
        var session = StoredBookingSession(id: booking.id, accessToken: token, booking: booking,
            travelerName: booking.pilgrimProfile?.displayName, telegram: booking.pilgrimProfile?.telegram,
            whatsapp: booking.pilgrimProfile?.whatsapp, outboundFlight: nil, inboundFlight: nil,
            hotelSelection: booking.hotelSelection, madinahHotelSelection: booking.madinahHotelSelection)
        if let trip = response.trip { session.mergeOperationalTrip(trip) }
        session.verifiedBookingEmail = email; session.verifiedBookingPhone = phone
        upsert(session)
        return session
    }

    func recordVerifiedContact(id: String, email: String?, phone: String?) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        if let email { sessions[index].verifiedBookingEmail = email }
        if let phone { sessions[index].verifiedBookingPhone = phone }
        persist()
    }

    // Only called after the server has authorized the link using BOTH proofs.
    func adoptVerifiedBooking(_ original: StoredBookingSession, link: IumrahAccountLinkBookingResponse) {
        var session = booking(id: original.id) ?? original
        session.pilgrimID = link.pilgrimID
        session.bookingNumber = link.bookingNumber ?? session.bookingNumber
        session.bookingDisplayNumber = link.bookingDisplayNumber ?? session.bookingDisplayNumber
        upsert(session)
    }

    func applyCanonicalLink(_ value: IumrahAccountLinkBookingResponse, to bookingID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].pilgrimID = value.pilgrimID
        sessions[index].bookingNumber = value.bookingNumber ?? sessions[index].bookingNumber
        sessions[index].bookingDisplayNumber = value.bookingDisplayNumber ?? sessions[index].bookingDisplayNumber
        persist()
    }

    private func mergeRemoteBooking(_ booking: RemoteBooking, operational: ClientTripResponse?, bookingID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].booking = booking
        if let trip = operational?.trip { sessions[index].mergeOperationalTrip(trip, statusHistory: operational?.statusHistory) }
        mergeOperationalStatusHistory(operational?.statusHistory, into: &sessions[index])
        sessions[index].guide = operational?.assignment?.guide ?? sessions[index].guide
        if let profile = booking.pilgrimProfile {
            sessions[index].travelerName = profile.displayName
            sessions[index].telegram = profile.telegram
            sessions[index].whatsapp = profile.whatsapp
        }
        mergeRemoteHotelSelection(booking.hotelSelection, into: &sessions[index].hotelSelection)
        mergeRemoteHotelSelection(booking.madinahHotelSelection, into: &sessions[index].madinahHotelSelection)
        if let customization = booking.customization {
            sessions[index].ziyaratMakkahOverride = customization.ziyaratMakkah
            sessions[index].ziyaratMadinahOverride = customization.ziyaratMadinah
            sessions[index].esimOverride = customization.esim
        }
    }

    private func mergeOperationalStatusHistory(_ history: [BookingStatusHistoryEntry]?, into session: inout StoredBookingSession) {
        guard let history else { return }
        session.statusHistory = history
    }

    func booking(id: String) -> StoredBookingSession? {
        sessions.first(where: { $0.id == id })
    }

    private func hydrateHotelSelectionIfNeeded(bookingID: String, role: HotelSelectionRole) async {
        guard let current = booking(id: bookingID) else { return }
        let existing = role == .madinah ? current.madinahHotelSelection : current.hotelSelection
        guard existing == nil else { return }

        let rawName = role == .madinah ? current.booking.hotelNames.madinah : current.booking.hotelNames.makkah
        let targetName = normalizedHotelName(rawName)
        guard !targetName.isEmpty else { return }

        let city = role == .madinah ? "Madinah" : "Makkah"
        guard let hotels = try? await hotelCatalogService.listHotels(city: city),
              let hotel = hotels.first(where: { normalizedHotelName($0.name) == targetName }),
              let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }

        let snapshot = BookingHotelSelectionSnapshot(hotel: hotel, room: nil, roomCategory: nil)
        if role == .madinah {
            sessions[index].madinahHotelSelection = snapshot
        } else {
            sessions[index].hotelSelection = snapshot
        }
    }

    private func normalizedHotelName(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadTravelESIMs(for bookingID: String) async throws {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let generation = bookingScopeGeneration
        do {
            let (result, _) = try await performWithClientAuthorization(for: session) { headers in
                try await bookingService.fetchOperationalTrip(id: bookingID, headers: headers)
            }
            guard !Task.isCancelled, generation == bookingScopeGeneration, booking(id: bookingID)?.accessToken == session.accessToken else { throw CancellationError() }
            travelESIMs[bookingID] = (session.accessToken, result.esims ?? [])
        } catch {
            if generation == bookingScopeGeneration && isAuthorizationFailure(error) { travelESIMs[bookingID] = nil }
            throw error
        }
    }
    func travelESIMProfiles(for bookingID: String) -> [ClientESIMProfile] {
        guard let session = booking(id: bookingID), let entry = travelESIMs[bookingID], entry.proof == session.accessToken else { return [] }
        return entry.profiles
    }
    func loadItinerary(for bookingID: String, language: AppSettingsStore.Language) async throws -> [BookingItineraryItem] {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let generation = bookingScopeGeneration
        let (items, _) = try await performWithClientAuthorization(for: session) { headers in
            try await bookingService.fetchItinerary(id: bookingID, headers: headers, language: language)
        }
        guard !Task.isCancelled, generation == bookingScopeGeneration, booking(id: bookingID)?.accessToken == session.accessToken else { throw CancellationError() }
        itineraries[bookingID] = items
        return items
    }

    private struct ChatCacheSnapshot: Codable {
        let cursor: String
        let messages: [ChatMessage]
        let scopeVersion: String?
    }

    private var chatCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iumrah-care-private-v1", isDirectory: true)
    }

    private func careHeaders(for bookingID: String) -> [String: String]? {
        if bookingID == "account", canUseCareChat, let token = accountToken, !token.isEmpty { return ["Authorization": "Bearer \(token)"] }
        guard canUseBookingCare(bookingID) else { return nil }
        guard bookingID != "account", let session = booking(id: bookingID), !session.accessToken.isEmpty else { return nil }
        return ["x-booking-token": session.accessToken]
    }

    private func chatCacheKey(for bookingID: String) -> String? {
        guard let headers = careHeaders(for: bookingID), let credential = headers["Authorization"] ?? headers["x-booking-token"] else { return nil }
        return SHA256.hash(data: Data("v28|\(bookingID)|\(credential)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func cachedChat(for bookingID: String) -> [ChatMessage] {
        guard let key = chatCacheKey(for: bookingID) else { return [] }
        if chatCacheKeys[bookingID] == key { return chats[bookingID] ?? [] }
        chatCacheKeys[bookingID] = key
        let url = chatCacheDirectory.appendingPathComponent(key + ".json")
        let snapshot = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ChatCacheSnapshot.self, from: $0) }
        chatCursors[bookingID] = snapshot?.cursor ?? "0"
        chatScopeVersions[bookingID] = snapshot?.scopeVersion
        chats[bookingID] = snapshot?.messages ?? []
        return snapshot?.messages ?? []
    }

    private func persistChat(_ bookingID: String) {
        guard let key = chatCacheKey(for: bookingID), chatCacheKeys[bookingID] == key,
              let data = try? JSONEncoder().encode(ChatCacheSnapshot(cursor: chatCursors[bookingID] ?? "0", messages: chats[bookingID] ?? [], scopeVersion: chatScopeVersions[bookingID])) else { return }
        do {
            try FileManager.default.createDirectory(at: chatCacheDirectory, withIntermediateDirectories: true)
            try data.write(to: chatCacheDirectory.appendingPathComponent(key + ".json"), options: [.atomic, .completeFileProtection])
        } catch { /* Cache is disposable; authoritative messages remain on the server. */ }
    }

    private func mergeChat(_ incoming: [ChatMessage], for bookingID: String, readIDs: [String] = []) -> [ChatMessage] {
        var byID: [String: ChatMessage] = [:]
        for message in chats[bookingID] ?? [] { byID[message.id] = message }
        for var message in incoming {
            if byID[message.id]?.readByStaff == true { message.readByStaff = true }
            byID[message.id] = message
        }
        for id in readIDs { byID[id]?.readByStaff = true }
        return byID.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    func loadChat(for bookingID: String) async throws -> [ChatMessage] {
        if let running = chatLoads[bookingID] { return try await running.value }
        guard let headers = careHeaders(for: bookingID), let key = chatCacheKey(for: bookingID) else { throw APIError.missingBookingToken }
        _ = cachedChat(for: bookingID)
        let generation = chatAuthGeneration
        let task = Task { @MainActor in
            // A bounded page loop catches up on large histories without downloading old messages on each open.
            for _ in 0..<20 {
                try Task.checkCancellation()
                let cursor = chatCursors[bookingID] ?? "0"
                let unread = (chats[bookingID] ?? []).filter { $0.senderType == "client" && $0.readByStaff != true }.suffix(80).map(\.id)
                let response = try await chatService.loadChat(bookingID: bookingID, after: cursor, scope: chatScopeVersions[bookingID], unread: unread, headers: headers)
                try Task.checkCancellation()
                guard generation == chatAuthGeneration, chatCacheKeys[bookingID] == key else { throw CancellationError() }
                if response.reset == true {
                    chats[bookingID] = []
                    let files = (try? FileManager.default.contentsOfDirectory(at: chatCacheDirectory, includingPropertiesForKeys: nil)) ?? []
                    for file in files where file.lastPathComponent.hasPrefix(key + "-") { try? FileManager.default.removeItem(at: file) }
                }
                chatScopeVersions[bookingID] = response.scopeVersion
                if !response.messages.isEmpty || !(response.staffReadMessageIDs ?? []).isEmpty {
                    let merged = mergeChat(response.messages, for: bookingID, readIDs: response.staffReadMessageIDs ?? [])
                    if chats[bookingID] != merged { chats[bookingID] = merged }
                }
                chatCursors[bookingID] = response.nextCursor ?? "0"
                if response.reset == true || !response.messages.isEmpty || !(response.staffReadMessageIDs ?? []).isEmpty || cursor != chatCursors[bookingID] { persistChat(bookingID) }
                guard response.hasMore == true, let next = response.nextCursor, next != cursor || response.reset == true else { break }
            }
            return chats[bookingID] ?? []
        }
        chatLoads[bookingID] = task
        defer { if generation == chatAuthGeneration { chatLoads[bookingID] = nil } }
        return try await task.value
    }

    func send(message: String, for bookingID: String, clientMessageID: String = UUID().uuidString) async throws -> ChatMessage {
        guard let headers = careHeaders(for: bookingID) else { throw APIError.missingBookingToken }
        _ = cachedChat(for: bookingID)
        let generation = chatAuthGeneration
        let created = try await chatService.send(message: message, bookingID: bookingID, clientMessageID: clientMessageID, headers: headers)
        guard generation == chatAuthGeneration else { throw CancellationError() }
        chats[bookingID] = mergeChat([created], for: bookingID)
        persistChat(bookingID)
        return created
    }

    func sendPhoto(data: Data, for bookingID: String) async throws -> ChatMessage {
        guard let headers = careHeaders(for: bookingID) else { throw APIError.missingBookingToken }
        _ = cachedChat(for: bookingID)
        let generation = chatAuthGeneration
        let created = try await chatService.sendPhoto(data: data, bookingID: bookingID, headers: headers)
        guard generation == chatAuthGeneration else { throw CancellationError() }
        chats[bookingID] = mergeChat([created], for: bookingID)
        persistChat(bookingID)
        return created
    }

    func chatAttachmentData(path: String, bookingID: String) async throws -> Data {
        guard let headers = careHeaders(for: bookingID), let key = chatCacheKey(for: bookingID) else { throw APIError.missingBookingToken }
        let generation = chatAuthGeneration
        let pathHash = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        let url = chatCacheDirectory.appendingPathComponent(key + "-" + pathHash + ".media")
        if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        let data = try await chatService.loadAttachment(path: path, headers: headers)
        guard generation == chatAuthGeneration else { throw CancellationError() }
        if data.count <= 5_000_000 {
            try? FileManager.default.createDirectory(at: chatCacheDirectory, withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
        return data
    }

    func syncPushSubscriptions(deviceToken: String, locale: String) async {
        guard !hasCareAccount else { return }
        let token = deviceToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        var registeredAny = false
        var observedReady: Bool?
        var firstError: String?

        for session in sessions {
            let candidates = pushHeaderCandidates(for: session)
            guard !candidates.isEmpty else { continue }

            var lastError: Error?
            var registered = false

            for headers in candidates {
                do {
                    let ready = try await clientPushService.register(
                        deviceToken: token,
                        bookingID: session.id,
                        headers: headers,
                        locale: locale
                    )
                    registeredAny = true
                    registered = true
                    if let ready {
                        observedReady = (observedReady ?? true) && ready
                    }
                    break
                } catch {
                    lastError = error
                }
            }

            if !registered, firstError == nil, let lastError {
                // Prefer the permanent account session for push registration, but retry
                // the legacy booking token so older bookings keep receiving pushes.
                firstError = lastError.localizedDescription
            }
        }

        if registeredAny {
            pushRegistrationReady = observedReady
        }
        pushRegistrationError = firstError
    }

    func syncHotelSelectionIfNeeded(bookingID: String) async {
        guard let session = booking(id: bookingID) else { return }
        let headers = clientHeaders(for: session)
        guard !headers.isEmpty else { return }

        await syncHotelSelectionIfNeeded(
            bookingID: bookingID,
            role: .makkah,
            local: session.hotelSelection,
            remote: session.booking.hotelSelection,
            headers: headers
        )
        await syncHotelSelectionIfNeeded(
            bookingID: bookingID,
            role: .madinah,
            local: session.madinahHotelSelection,
            remote: session.booking.madinahHotelSelection,
            headers: headers
        )
    }

    func updateHotelSelection(
        bookingID: String,
        role: HotelSelectionRole = .makkah,
        hotel: HotelSummary,
        room: HotelRoom?,
        roomCategory: IumrahRoomCategoryOption? = nil
    ) async throws {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let headers = clientHeaders(for: session)
        guard !headers.isEmpty else { throw APIError.missingBookingToken }
        _ = try await bookingService.updateHotelSelection(
            id: bookingID,
            headers: headers,
            role: role,
            hotel: hotel,
            room: room,
            roomCategory: roomCategory
        )
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        let snapshot = BookingHotelSelectionSnapshot(hotel: hotel, room: room, roomCategory: roomCategory)
        if role == .madinah {
            sessions[index].madinahHotelSelection = snapshot
        } else {
            sessions[index].hotelSelection = snapshot
        }
        sessions[index].pendingChangeConfirmation = true
        persist()
    }

    func updateContacts(bookingID: String, telegram: String, whatsapp: String) async throws {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let headers = clientHeaders(for: session)
        guard !headers.isEmpty else { throw APIError.missingBookingToken }
        let cleanTelegram = telegram.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWhatsApp = whatsapp.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await bookingService.updateContacts(
            id: bookingID,
            headers: headers,
            telegram: cleanTelegram,
            whatsapp: cleanWhatsApp
        )

        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].telegram = cleanTelegram
        sessions[index].whatsapp = cleanWhatsApp
        sessions[index].pendingChangeConfirmation = true
        if let profile = identityProfile(remote: sessions[index].booking.pilgrimProfile, session: sessions[index]) {
            let updatedProfile = BookingPilgrimProfile(
                firstName: profile.firstName,
                lastName: profile.lastName,
                telegram: cleanTelegram,
                whatsapp: cleanWhatsApp
            )
            if !session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let response = try? await bookingService.syncBookingProfile(
                id: bookingID,
                accessToken: session.accessToken,
                profile: updatedProfile
            ) {
                sessions[index].mergeOperationalTrip(response.trip, statusHistory: response.statusHistory)
                sessions[index].guide = response.assignment?.guide ?? sessions[index].guide
            }
        }
        persist()
    }

    func updateZiyarat(bookingID: String, makkah: Bool, madinah: Bool) async throws {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let headers = clientHeaders(for: session)
        guard !headers.isEmpty else { throw APIError.missingBookingToken }
        _ = try await bookingService.updateZiyarat(
            id: bookingID,
            headers: headers,
            makkah: makkah,
            madinah: madinah
        )
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].ziyaratMakkahOverride = makkah
        sessions[index].ziyaratMadinahOverride = madinah
        sessions[index].pendingChangeConfirmation = true
        persist()
    }


    func updateESIM(bookingID: String, enabled: Bool) async throws {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let headers = clientHeaders(for: session)
        guard !headers.isEmpty else { throw APIError.missingBookingToken }
        _ = try await bookingService.updateESIM(id: bookingID, headers: headers, enabled: enabled)
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].esimOverride = enabled
        sessions[index].pendingChangeConfirmation = true
        persist()
    }

    func requestChangeConfirmation(bookingID: String, message: String) async throws {
        _ = try await send(message: message, for: bookingID)
        guard let index = sessions.firstIndex(where: { $0.id == bookingID }) else { return }
        sessions[index].pendingChangeConfirmation = false
        persist()
    }

    private func syncHotelSelectionIfNeeded(
        bookingID: String,
        role: HotelSelectionRole,
        local: BookingHotelSelectionSnapshot?,
        remote: BookingHotelSelectionSnapshot?,
        headers: [String: String]
    ) async {
        guard let local else { return }
        let differs = remote?.hotelId != local.hotelId ||
            remote?.roomId != local.roomId ||
            remote?.roomCategory != local.roomCategory
        guard differs else { return }
        do {
            _ = try await bookingService.updateHotelSelection(
                id: bookingID,
                headers: headers,
                role: role,
                snapshot: local
            )
        } catch {
            // Keep the local selection and retry on a later booking-detail refresh.
        }
    }

    func submitTravelFeedback(id: String, rating: Int, comment: String) async throws -> IumrahTravelFeedback {
        guard let session = booking(id: id) else { throw APIError.missingBookingToken }
        let generation = bookingScopeGeneration
        let (result, _) = try await performWithClientAuthorization(for: session) { headers in
            try await bookingService.submitTravelFeedback(id: id, rating: rating, comment: comment, headers: headers)
        }
        guard generation == bookingScopeGeneration, booking(id: id)?.accessToken == session.accessToken else { throw CancellationError() }
        _ = try? await loadCheckout(id: id, token: accountToken, force: true)
        return result.feedback
    }

    func requestCancellation(id: String) async throws {
        guard let session = booking(id: id) else { throw APIError.status(404) }
        _ = try await performWithClientAuthorization(for: session) { headers in
            try await bookingService.requestCancellation(id: id, headers: headers)
        }
    }

    func deleteBooking(id: String) async throws {
        guard let session = booking(id: id) else {
            purgeLocalBooking(id: id)
            persist()
            return
        }

        do {
            _ = try await performWithClientAuthorization(for: session) { headers in
                try await bookingService.deleteBooking(id: id, headers: headers)
            }
        } catch APIError.status(let code) where code == 404 || code == 410 {
            // Idempotent delete: the canonical server copy is already gone.
        } catch APIError.server(let code, let message) where isRemoteMissing(code: code, message: message) {
            // Same as a successful delete from the client's point of view.
        } catch APIError.status(let code) where code == 405 {
            throw BookingStoreError.permanentDeleteUnavailable
        } catch APIError.server(let code, let message) where code == 405 || message.uppercased().contains("METHOD_NOT_ALLOWED") {
            throw BookingStoreError.permanentDeleteUnavailable
        } catch {
            // A stale booking proof used to surface UNAUTHORIZED here even for a
            // valid signed-in iumrah account. performWithClientAuthorization has
            // already retried the permanent account session. Only reconcile the
            // old booking proof after both authorization candidates are exhausted.
            let token = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty, await remoteBookingIsMissing(id: id, accessToken: token) else { throw error }
        }

        purgeLocalBooking(id: id)
        persist()
    }

    private func clientHeaderCandidates(for session: StoredBookingSession) -> [[String: String]] {
        var candidates: [[String: String]] = []

        if let accountToken {
            let permanentToken = accountToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !permanentToken.isEmpty {
                candidates.append(["Authorization": "Bearer \(permanentToken)"])
            }
        }

        let bookingToken = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookingToken.isEmpty {
            candidates.append(["x-booking-token": bookingToken])
        }

        return candidates
    }

    private func clientHeaders(for session: StoredBookingSession) -> [String: String] {
        let bookingToken = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookingToken.isEmpty { return ["x-booking-token": bookingToken] }
        if let accountToken {
            let permanentToken = accountToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !permanentToken.isEmpty { return ["Authorization": "Bearer \(permanentToken)"] }
        }
        return [:]
    }

    private func performWithClientAuthorization<T>(
        for session: StoredBookingSession,
        operation: ([String: String]) async throws -> T
    ) async throws -> (T, [String: String]) {
        let candidates = clientHeaderCandidates(for: session)
        guard !candidates.isEmpty else { throw APIError.missingBookingToken }

        var lastAuthorizationError: Error?
        for headers in candidates {
            do {
                return (try await operation(headers), headers)
            } catch {
                guard isAuthorizationFailure(error) else { throw error }
                lastAuthorizationError = error
            }
        }

        throw lastAuthorizationError ?? APIError.missingBookingToken
    }

    private func isAuthorizationFailure(_ error: Error) -> Bool {
        switch error {
        case APIError.status(let code):
            return code == 401 || code == 403
        case APIError.server(let code, let message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return code == 401 || code == 403
                || normalized.contains("UNAUTHORIZED")
                || normalized.contains("BOOKING_PROOF_INVALID")
                || normalized.contains("TOKEN_EXPIRED")
        default:
            return false
        }
    }

    private func pushHeaderCandidates(for session: StoredBookingSession) -> [[String: String]] {
        var candidates: [[String: String]] = []

        if let accountToken {
            let permanentToken = accountToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !permanentToken.isEmpty {
                candidates.append(["Authorization": "Bearer \(permanentToken)"])
            }
        }

        let bookingToken = session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bookingToken.isEmpty {
            candidates.append(["x-booking-token": bookingToken])
        }

        return candidates
    }

    private func remoteBookingIsMissing(id: String, accessToken: String) async -> Bool {
        do {
            _ = try await bookingService.fetchBooking(id: id, accessToken: accessToken)
            return false
        } catch APIError.status(let code) where code == 404 || code == 410 {
            return true
        } catch APIError.server(let code, let message) where isRemoteMissing(code: code, message: message) {
            return true
        } catch {
            return false
        }
    }
    private func purgeLocalBooking(id: String) {
        if let session = booking(id: id) { BookingOfflineDocuments.purge(bookingID: id, proof: session.accessToken) }
        checkoutRequests[id]?.task.cancel()
        checkoutRequests[id] = nil
        checkoutCache[id] = nil
        checkoutFriendsCache[id] = nil
        sessions.removeAll(where: { $0.id == id })
        chatLoads[id]?.cancel()
        chatLoads[id] = nil
        if let key = chatCacheKeys.removeValue(forKey: id) {
            let files = (try? FileManager.default.contentsOfDirectory(at: chatCacheDirectory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent == key + ".json" || file.lastPathComponent.hasPrefix(key + "-") { try? FileManager.default.removeItem(at: file) }
        }
        chatCursors[id] = nil
        chats[id] = nil
        itineraries[id] = nil
        travelESIMs[id] = nil
    }

    private func isRemoteMissing(code: Int, message: String) -> Bool {
        let normalized = message.uppercased()
        return code == 404 || code == 410 || normalized.contains("NOT_FOUND") || normalized.contains("NOT FOUND")
    }

    private func mergeRemoteHotelSelection(_ remote: BookingHotelSelectionSnapshot?, into local: inout BookingHotelSelectionSnapshot?) {
        guard let remote else { return }
        if remote.roomCategory == nil,
           remote.roomId == nil,
           let current = local,
           current.hotelId == remote.hotelId,
           current.roomCategory != nil {
            return
        }
        local = remote
    }

    private func identityProfile(remote: BookingPilgrimProfile?, session: StoredBookingSession) -> BookingPilgrimProfile? {
        if let remote,
           !remote.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !remote.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return remote
        }
        let parts = (session.travelerName ?? "")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard parts.count >= 2 else { return nil }
        return BookingPilgrimProfile(
            firstName: parts[0],
            lastName: parts.dropFirst().joined(separator: " "),
            telegram: session.telegram ?? "",
            whatsapp: session.whatsapp ?? ""
        )
    }

    private func upsert(_ session: StoredBookingSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persist()
    }

    private func persist() {
        _ = BookingSessionVault.save(sessions)
    }

    private func loadFromStorage() {
        let secureSessions = BookingSessionVault.load()
        if !secureSessions.isEmpty {
            sessions = migrateLegacyPrimaryRooms(in: secureSessions)
            _ = BookingSessionVault.save(sessions)
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            return
        }

        guard let data = UserDefaults.standard.data(forKey: legacyStorageKey),
              let decoded = try? JSONDecoder().decode([StoredBookingSession].self, from: data) else {
            return
        }

        sessions = migrateLegacyPrimaryRooms(in: decoded)
        if BookingSessionVault.save(sessions) {
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        }
    }

    private func migrateLegacyPrimaryRooms(in values: [StoredBookingSession]) -> [StoredBookingSession] {
        values.map { value in
            var migrated = value
            if let selection = migrated.hotelSelection {
                migrated.hotelSelection = selection.migratedLegacyPrimaryRoom
            }
            return migrated
        }
    }
}


/// Explicitly downloaded copies only. Scoped to booking proof; no proof is written to disk.
/// iOS data protection, excluded from backups, no access on a rejected authorization.
@MainActor enum BookingOfflineDocuments {
    private static let fm = FileManager.default
    private static var root: URL { fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("IumrahOfflineTravelDocuments-v1", isDirectory: true) }
    private static var previews: URL { fm.temporaryDirectory.appendingPathComponent("IumrahTravelPreviews-v1", isDirectory: true) }
    private static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
    private static func folder(_ id: String, _ proof: String) -> URL { root.appendingPathComponent(digest(id + "\u{0}" + proof), isDirectory: true) }
    private static func file(_ doc: IumrahTravelDocument, in directory: URL) -> URL { directory.appendingPathComponent(digest(doc.id)).appendingPathExtension(ext(doc)) }
    private static func ext(_ doc: IumrahTravelDocument) -> String { doc.contentType == "application/pdf" ? "pdf" : doc.contentType.contains("png") ? "png" : "jpg" }
    private static func prepare(_ directory: URL) throws {
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true; try url.setResourceValues(values)
    }
    static func list(bookingID: String, proof: String) -> [IumrahTravelDocument] {
        guard !proof.isEmpty else { return [] }
        let dir = folder(bookingID, proof)
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("index.json")), let docs = try? JSONDecoder().decode([IumrahTravelDocument].self, from: data) else { return [] }
        return docs.filter { fm.fileExists(atPath: file($0, in: dir).path) }
    }
    private static func writeIndex(_ docs: [IumrahTravelDocument], _ dir: URL) throws { try JSONEncoder().encode(docs).write(to: dir.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtection]) }
    static func save(_ data: Data, document: IumrahTravelDocument, bookingID: String, proof: String) throws {
        guard !proof.isEmpty, !data.isEmpty, document.publicationStatus != "revoked" else { throw URLError(.cannotWriteToFile) }
        let dir = folder(bookingID, proof); try prepare(root); try prepare(dir)
        try data.write(to: file(document, in: dir), options: [.atomic, .completeFileProtection])
        var docs = list(bookingID: bookingID, proof: proof).filter { $0.id != document.id }; docs.append(document)
        try writeIndex(docs, dir)
    }
    static func data(_ document: IumrahTravelDocument, bookingID: String, proof: String) -> Data? {
        guard list(bookingID: bookingID, proof: proof).contains(where: { $0.id == document.id }) else { return nil }
        return try? Data(contentsOf: file(document, in: folder(bookingID, proof)))
    }
    static func reconcile(bookingID: String, proof: String, published: [IumrahTravelDocument]) {
        guard !proof.isEmpty else { return }
        let dir = folder(bookingID, proof)
        let saved = list(bookingID: bookingID, proof: proof)
        guard !saved.isEmpty else { return }
        let current = published.filter { $0.publicationStatus != "revoked" }
        var keep: [IumrahTravelDocument] = []
        for old in saved {
            if let new = current.first(where: { $0.id == old.id && $0.createdAt == old.createdAt && $0.contentType == old.contentType }) { keep.append(new) }
            else { try? fm.removeItem(at: file(old, in: dir)) }
        }
        if keep.isEmpty { purge(bookingID: bookingID, proof: proof) } else { try? writeIndex(keep, dir) }
    }
    static func purge(bookingID: String, proof: String) { guard !proof.isEmpty else { return }; try? fm.removeItem(at: folder(bookingID, proof)); removePreviews() }
    static func purgeAll() { try? fm.removeItem(at: root); removePreviews() }
    static func preview(_ data: Data, document: IumrahTravelDocument) throws -> URL {
        try prepare(previews)
        let url = previews.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext(document)); try data.write(to: url, options: [.atomic, .completeFileProtection]); return url
    }
    static func removePreviews() { try? fm.removeItem(at: previews) }
    static func isNetworkError(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed].contains(e.code)
    }
    static func isAccessError(_ error: Error) -> Bool {
        switch error {
        case APIError.status(let code), APIError.server(let code, _): return [401,403,404,410].contains(code)
        case APIError.missingBookingToken: return true
        default: return false
        }
    }
}
