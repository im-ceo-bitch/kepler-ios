#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Exercise the actual production coordination methods with an isolated fake UIKit/network loader.
python3 - "$tmp/Coordinator.swift" <<'PY'
import sys
from pathlib import Path
s=Path('Sources/Services/HotelImageCache.swift').read_text()
start=s.index('    private struct Flight {'); end=s.index('    private var lastDiskTrim',start)
methods=s[s.index('    func image(for url:'):s.index('    private func load(url:')]
head='''import Foundation
final class UIImage: @unchecked Sendable {}
actor HotelImageCache {
    let memory = NSCache<NSURL, UIImage>()
'''
extra='''    private var failures: [String: Date] = [:]
    private var loads = 0
    private var running = 0
    private var peak = 0
    func stats() -> (Int, Int) { (loads, peak) }
    private func load(url: URL, key: NSURL, dimension: Int) async -> UIImage? {
        loads += 1; running += 1; peak = max(peak, running)
        defer { running -= 1 }
        do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return nil }
        let result = UIImage(); memory.setObject(result, forKey: key); return result
    }
}
'''
Path(sys.argv[1]).write_text(head+s[start:end]+methods+extra)
PY
swiftc -swift-version 5 "$tmp/Coordinator.swift" Tests/IumrahImageCoordinatorSmoke.swift -o "$tmp/test"
"$tmp/test"
