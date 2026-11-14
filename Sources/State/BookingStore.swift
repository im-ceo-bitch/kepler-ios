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
        var session = booking(id: saved.id) ?? saved
        if session.hasServerIdentity { return session }
        let operational = try await bookingService.fetchOperationalTrip(
            id: session.id, headers: ["x-booking-token": session.accessToken]
        )
        guard operational.trip.bookingID == session.id else { throw BookingStoreError.identityPending }
        session.mergeOperationalTrip(operational.trip, statusHistory: operational.statusHistory)
        session.guide = operational.assignment?.guide ?? session.guide
        upsert(session)
        guard session.hasServerIdentity else { throw BookingStoreError.identityPending }
        return session
    }

    func refreshAll() async {
        var staleBookingIDs = Set<String>()

        for session in sessions {
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

        for id in staleBookingIDs { purgeLocalBooking(id: id) }
        persist()
    }

    func setAccountToken(_ token: String?) {
        let next = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if next != accountToken {
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
        accountToken = next
    }

    func restoreAccountTrips(token: String) async {
        setAccountToken(token)
        guard let trips = try? await accountService.trips(token: token) else { return }
        for trip in trips {
            guard let detail = try? await accountService.tripDetail(bookingID: trip.bookingID, token: token) else { continue }
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

    func loadItinerary(for bookingID: String, language: AppSettingsStore.Language) async throws -> [BookingItineraryItem] {
        guard let session = booking(id: bookingID) else { throw APIError.missingBookingToken }
        let (items, _) = try await performWithClientAuthorization(for: session) { headers in
            try await bookingService.fetchItinerary(id: bookingID, headers: headers, language: language)
        }
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
        if bookingID == "account", let token = accountToken, !token.isEmpty { return ["Authorization": "Bearer \(token)"] }
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
