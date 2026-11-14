import Foundation
@main struct Test {
    static func main() async {
        let cache = HotelImageCache()
        let url = URL(string: "https://example.com/same")!
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<30 { group.addTask { await cache.image(for: url) != nil } }
            for await success in group { precondition(success) }
        }
        let first = await cache.stats(); precondition(first.0 == 1)
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<20 { group.addTask { await cache.image(for: URL(string: "https://example.com/\(i)")!) != nil } }
            for await success in group { precondition(success) }
        }
        let second = await cache.stats(); precondition(second.0 == 21 && second.1 == 4)
        let same = URL(string: "https://example.com/shared-cancel")!
        let a = Task { await cache.image(for: same) }
        let b = Task { await cache.image(for: same) }
        try? await Task.sleep(nanoseconds: 20_000_000); a.cancel()
        let av = await a.value; let bv = await b.value
        precondition(av == nil && bv != nil)
        let canceledURL = URL(string: "https://example.com/all-cancel")!
        let c = Task { await cache.image(for: canceledURL) }
        try? await Task.sleep(nanoseconds: 20_000_000); c.cancel()
        let cv = await c.value; precondition(cv == nil)
        let retry = await cache.image(for: canceledURL); precondition(retry != nil)
        print("PASS: deduplication (30 callers), concurrency cap (20 unique URLs), partial cancellation, all-cancel retry")
    }
}
