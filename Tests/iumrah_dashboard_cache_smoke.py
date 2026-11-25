#!/usr/bin/env python3
"""Compile the real cache declarations/methods with a deterministic mock API.
Run from the repository root: python3 Tests/iumrah_dashboard_cache_smoke.py
Tests the production state machine, not SwiftUI layout or real server responses.
"""
import pathlib
import subprocess
import tempfile

source = pathlib.Path('Sources/State/IumrahAccountStore.swift').read_text()
a = source.index('    @Published private(set) var dashboardRewards:')
b = source.index('\n    init()', a)
props = source[a:b].replace('@Published ', '')
a = source.index('    func refreshDashboardRewards(')
b = source.index('    func claimPrimaryDevice', a)
methods = source[a:b]
mock = '''import Foundation
struct IumrahFriendsDashboard: Equatable { let availableCreditUsd: Double; let tier: String }
enum APIError: Error { case status(Int); case server(Int, String) }
@MainActor final class MockService {
    var calls = 0
    var delay = 35
    var fail: APIError?
    var amount = 100.0
    func friendsDashboard(token: String) async throws -> IumrahFriendsDashboard {
        calls += 1
        let value = amount
        let failure = fail
        try await Task.sleep(for: .milliseconds(delay))
        if let failure { throw failure }
        return .init(availableCreditUsd: value, tier: "member")
    }
    func registerCurrentSession(token: String, locale: String) async throws -> Bool { true }
}
@MainActor final class Store {
    let service = MockService()
    var isAuthenticated: Bool { token != nil }
    func login(_ t: String?) { token = t }
''' + props + methods + '''
}
@main struct Test {
    @MainActor static func main() async throws {
        let store = Store()
        assert(store.dashboardRewards == nil)
        await store.refreshDashboardRewards()
        assert(store.service.calls == 0)
        store.login("account-A")
        async let a: Void = store.refreshDashboardRewards()
        async let b: Void = store.refreshDashboardRewards()
        _ = await (a,b)
        assert(store.service.calls == 1)
        assert(store.dashboardRewards?.availableCreditUsd == 100)
        assert(!store.dashboardRewardsLoading)
        await store.refreshDashboardRewards()
        assert(store.service.calls == 1)
        store.service.amount = 0
        await store.refreshDashboardRewards(force: true)
        assert(store.dashboardRewards?.availableCreditUsd == 0)
        store.service.fail = .status(500)
        await store.refreshDashboardRewards(force: true)
        assert(store.dashboardRewards?.availableCreditUsd == 0 && store.dashboardRewardsStale)
        store.service.fail = .status(401)
        await store.refreshDashboardRewards(force: true)
        assert(store.dashboardRewards == nil && !store.dashboardRewardsLoading)
        store.service.fail = nil
        store.service.amount = 100
        store.service.delay = 150
        let previous = Task { await store.refreshDashboardRewards(force: true) }
        try await Task.sleep(for: .milliseconds(25))
        store.login("account-B")
        assert(store.dashboardRewards == nil)
        store.service.amount = 300
        await store.refreshDashboardRewards(force: true)
        await previous.value
        assert(store.dashboardRewards?.availableCreditUsd == 300)
        store.login(nil)
        assert(store.dashboardRewards == nil && !store.dashboardRewardsLoading && !store.dashboardRewardsStale)
        print("PASS: guest, coalescing, TTL, verified zero, stale transient response, 401, account switch, logout")
    }
}
'''
with tempfile.TemporaryDirectory() as work:
    swift = pathlib.Path(work) / 'CacheSmoke.swift'
    exe = pathlib.Path(work) / 'smoke'
    swift.write_text(mock)
    subprocess.run(['swiftc', '-parse-as-library', str(swift), '-o', str(exe)], check=True)
    subprocess.run([str(exe)], check=True)
