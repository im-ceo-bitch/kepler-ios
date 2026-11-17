#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/main.swift" <<'PY'
from pathlib import Path
import sys
models = Path('Sources/Models/BookingModels.swift').read_text()
store = Path('Sources/State/BookingStore.swift').read_text()
def extract(source, start):
    i = source.index(start)
    first = source.index('{', i)
    depth = 1
    end = first + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[i:end]
# Actual production declarations, with lightweight stand-ins only for unrelated
# app-specific dependencies. Actual store method is compiled, not reimplemented.
parts = [extract(models, 'struct '+n+':') for n in [
    'BookingCreateResponse', 'RemoteBooking', 'BookingPilgrimProfile',
    'BookingInputRecord', 'BookingTravelers', 'BookingRoute', 'BookingStay',
    'BookingHotelNames', 'BookingCustomization', 'ClientTripSnapshot',
    'StoredBookingSession', 'BookingStatusHistoryEntry', 'BookingGuideSnapshot']]
method = extract(store, 'func adoptOfferBooking(')
actual_upsert = extract(store, 'private func upsert(')
actual_booking = extract(store, 'func booking(id:')
Path(sys.argv[1]).write_text('''import Foundation
struct BookingGeneratorTrace: Codable, Hashable {}
struct BookingHotelSelectionSnapshot: Codable, Hashable { let hotelId: String }
struct FlightOffer: Codable, Hashable { let id: String }
enum TransferVehicleKind: String, Codable, Hashable { case carnival }
enum APIError: Error { case missingBookingToken, invalidResponse }
'''+'\n'.join(parts)+'''\n@MainActor final class BookingStore {
    var sessions: [StoredBookingSession] = []
    var writes = 0
    private func persist() { writes += 1 }
'''+method+'\n'+actual_upsert+'\n'+actual_booking+'''\n}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
func receipt(_ id: String = "B1", _ token: String? = "secret", _ tripID: String? = "B1") throws -> BookingCreateResponse {
    var json: [String: Any] = ["booking": [
        "id": id, "status": "AVAILABILITY_CHECK", "planId": "standard",
        "offerPackageID": "offer-123",
        "totalUsd": 2500, "perPilgrimUsd": 1250,
        "input": ["startDate": "2026-11-24", "endDate": "2026-11-30", "from": "Tashkent", "originCode": "TAS", "arrivalAirportCode": "MED", "includeMadinah": true, "travelers": ["adults": 2, "children": 0, "infants": 0, "rooms": 1]],
        "route": ["originCode": "TAS", "outboundDestination": "MED", "returnOrigin": "JED"],
        "stay": ["totalDays": 7, "totalNights": 6, "makkahCheckIn": "2026-11-27", "makkahCheckOut": "2026-11-30", "makkahNights": 3],
        "hotelNames": ["makkah": "Hotel A", "madinah": "Hotel B"], "flight": "Flight A",
        "createdAt": "2026-11-17T00:00:00Z", "updatedAt": "2026-11-17T00:00:00Z",
        "pilgrimProfile": ["firstName": "Test", "lastName": "Person", "telegram": "", "whatsapp": ""],
        "hotelSelection": ["hotelId": "H1"]
    ]]
    if let token { json["accessToken"] = token }
    if let tripID { json["trip"] = ["tripID": "T1", "bookingID": tripID, "status": "availability_check", "bookingNumber": 5, "bookingDisplayNumber": "#0005", "pilgrimID": "90"] }
    return try JSONDecoder().decode(BookingCreateResponse.self, from: JSONSerialization.data(withJSONObject: json))
}
@MainActor func run() throws {
    let store = BookingStore()
    let initial = try store.adoptOfferBooking(receipt())
    require(initial.id == "B1" && initial.accessToken == "secret", "canonical credentials")
    require(initial.travelerName == "Test Person" && initial.hotelSelection?.hotelId == "H1", "canonical profile/hotel")
    require(initial.hasServerIdentity && initial.displayBookingNumber == "#0005" && initial.displayPilgrimID == "00000090", "canonical identity")
    require(store.sessions.count == 1 && store.writes == 1, "first persistence")
    // Exact expression from BusinessOfferView.swift:61 in the archive failure.
    let offer = (packageID: "offer-123", title: "Example")
    let session = store.sessions.first(where: { $0.booking.offerPackageID == offer.packageID })
    require(session?.id == initial.id, "native offer lookup compiles and finds the booking")
    let encoded = try JSONEncoder().encode(initial.booking)
    let roundTrip = try JSONDecoder().decode(RemoteBooking.self, from: encoded)
    require(roundTrip.offerPackageID == "offer-123", "offer survives persistence")
    var oldBooking = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
    oldBooking.removeValue(forKey: "offerPackageID")
    let old = try JSONDecoder().decode(RemoteBooking.self, from: JSONSerialization.data(withJSONObject: oldBooking))
    require(old.offerPackageID == nil, "old bookings without offer ID still decode")
    oldBooking["offerPackageID"] = NSNull()
    let null = try JSONDecoder().decode(RemoteBooking.self, from: JSONSerialization.data(withJSONObject: oldBooking))
    require(null.offerPackageID == nil, "null offer ID still decodes")

    store.sessions[0].verifiedBookingEmail = "verified@example.invalid"
    let retry = try store.adoptOfferBooking(receipt())
    require(store.sessions.count == 1 && store.writes == 1 && retry.verifiedBookingEmail == "verified@example.invalid", "idempotent retry")
    for response in [try receipt("B2", nil, nil), try receipt("B2", "  ", nil), try receipt("", "secret", nil), try receipt("B2", "secret", "OTHER"), try receipt("B1", "wrong", "B1")] {
        do { _ = try store.adoptOfferBooking(response); fatalError("bad receipt accepted") }
        catch APIError.invalidResponse {} catch APIError.missingBookingToken {}
    }
    require(store.sessions.count == 1 && store.writes == 1, "invalid receipts must not persist")
    let pending = try store.adoptOfferBooking(receipt("B2", "second", nil))
    require(!pending.hasServerIdentity && store.sessions.count == 2, "202/pending identity receipt")
    let accountOnly = BookingStore()
    var restored = StoredBookingSession(id: initial.id, accessToken: "", booking: initial.booking, travelerName: nil, telegram: nil, whatsapp: nil, outboundFlight: nil, inboundFlight: nil, hotelSelection: nil)
    restored.verifiedBookingPhone = "+998000000000"
    accountOnly.sessions = [restored]
    let upgraded = try accountOnly.adoptOfferBooking(receipt())
    require(upgraded.accessToken == "secret" && upgraded.verifiedBookingPhone == restored.verifiedBookingPhone && accountOnly.sessions.count == 1, "upgrade existing account-only trip")
    print("PASS: native offer response decoding, canonical IDs, persistence, idempotence, token and trip rejection, pending identity, account-only upgrade")
}
try MainActor.assumeIsolated { try run() }
''')
PY
swiftc -swift-version 5 "$tmp/main.swift" -o "$tmp/offer-test"
"$tmp/offer-test"
