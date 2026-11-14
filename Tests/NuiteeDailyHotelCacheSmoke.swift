import Foundation

@main struct CacheTest {
    static func main() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date()
        let yesterday = today.addingTimeInterval(-86400)
        let tomorrow = today.addingTimeInterval(86400)
        let response = NuiteeHotelListEnvelope(ok: true, sandbox: false, city: "makkah", checkin: "2026-11-20", checkout: "2026-11-21", adults: 2, hotelCatalogStale: false, pricesStale: false, pricesUpdatedAt: nil, rateError: nil, hotels: [])
        let cache = NuiteeDailyHotelCache(directory: dir)
        let key = "makkah-2026-11-20-2026-11-21-2-rates"
        let miss = await cache.read(key: key, now: today)
        precondition(miss == nil, "missing entry")
        await cache.write(response, key: key, now: today)
        let hit = await cache.read(key: key, now: today)
        precondition(hit?.city == "makkah", "immediate read")
        let restarted = NuiteeDailyHotelCache(directory: dir)
        let persistent = await restarted.read(key: key, now: today)
        precondition(persistent?.adults == 2, "persistent across instance")
        let otherCity = await cache.read(key: "madinah-2026-11-20-2026-11-21-2-rates", now: today)
        precondition(otherCity == nil, "city separation")
        let otherDates = await cache.read(key: "makkah-2026-11-21-2026-11-22-2-rates", now: today)
        precondition(otherDates == nil, "date separation")
        let otherGuests = await cache.read(key: "makkah-2026-11-20-2026-11-21-3-rates", now: today)
        precondition(otherGuests == nil, "occupancy separation")
        let catalog = await cache.read(key: "makkah-2026-11-20-2026-11-21-2-catalog", now: today)
        precondition(catalog == nil, "rate versus catalog separation")
        precondition(!NuiteeDailyHotelCache.isFresh(savedAt: yesterday, now: today), "24-hour expiry")
        precondition(!NuiteeDailyHotelCache.isFresh(savedAt: tomorrow, now: today), "future timestamp")
        let midnight = cal.startOfDay(for: today)
        precondition(!NuiteeDailyHotelCache.isFresh(savedAt: midnight.addingTimeInterval(-1), now: midnight.addingTimeInterval(1), calendar: cal), "midnight expiry")
        let expired = await restarted.read(key: key, now: tomorrow)
        precondition(expired == nil, "expired on disk")
        await cache.write(response, key: key, now: today)
        let filename = dir.appendingPathComponent(key + ".json")
        try Data("bad json".utf8).write(to: filename)
        let hot = await cache.read(key: key, now: today)
        precondition(hot?.city == "makkah", "valid in-memory entry survives disk corruption")
        let cold = NuiteeDailyHotelCache(directory: dir)
        let corrupted = await cold.read(key: key, now: today)
        precondition(corrupted == nil, "corrupt file recovery on cold read")
        // Four recently used keys only: evicted entries remain readable on disk.
        for i in 0..<5 { await cache.write(response, key: "test-\(i)", now: today) }
        let evicted = dir.appendingPathComponent("test-0.json")
        try FileManager.default.removeItem(at: evicted)
        let evictedRead = await cache.read(key: "test-0", now: today)
        precondition(evictedRead == nil, "oldest entry evicted from memory")
        let retained = dir.appendingPathComponent("test-4.json")
        try FileManager.default.removeItem(at: retained)
        let retainedRead = await cache.read(key: "test-4", now: today)
        precondition(retainedRead != nil, "recent entry retained in memory")
        let expiredHot = await cache.read(key: "test-4", now: tomorrow)
        precondition(expiredHot == nil, "in-memory entry respects expiry")
        print("PASS: 16 cache checks")
    }
}
