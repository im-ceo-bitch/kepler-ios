import Foundation

/// Non-sensitive catalogue data only. Never cache final quotes or room-selection tokens here.
actor NuiteeDailyHotelCache {
    static let shared = NuiteeDailyHotelCache()
    private struct Entry: Codable {
        let savedAt: Date
        let response: NuiteeHotelListEnvelope
    }
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("iumrah-nuitee-daily-v1", isDirectory: true)
    }
    static func isFresh(savedAt: Date, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        now >= savedAt && now.timeIntervalSince(savedAt) < 86_400 && calendar.isDate(savedAt, inSameDayAs: now)
    }
    private func file(_ key: String) -> URL {
        // All callers generate keys from normalized city, ISO dates and occupancy.
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe) + ".json")
    }
    func read(key: String, now: Date = Date()) -> NuiteeHotelListEnvelope? {
        let url = file(key)
        guard let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(Entry.self, from: data), Self.isFresh(savedAt: entry.savedAt, now: now) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.response
    }
    func write(_ response: NuiteeHotelListEnvelope, key: String, now: Date = Date()) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Entry(savedAt: now, response: response))
            try data.write(to: file(key), options: .atomic)
            // Remove yesterday's records even for searches not revisited today.
            for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   (date < now && !Self.isFresh(savedAt: date, now: now)) { try? FileManager.default.removeItem(at: url) }
            }
        } catch { /* Cache failures must never prevent search or booking. */ }
    }
}
