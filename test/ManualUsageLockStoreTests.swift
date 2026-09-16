import XCTest
@testable import Comux

final class ManualUsageLockStoreTests: XCTestCase {
    @MainActor
    func testLockPersistsAcrossRefreshAndRestartAndExpiresAtOriginalReset() {
        let suite = "manual-lock-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(300)
        let account = makeAccount(workspace: "a", reset: reset)
        let store = ManualUsageLockStore(defaults: defaults)
        store.lock(account, now: now)
        let reloaded = ManualUsageLockStore(defaults: defaults)
        XCTAssertEqual(reloaded.deadline(for: account, now: now), reset)
        let refreshed = makeAccount(workspace: "a", reset: now.addingTimeInterval(3600))
        XCTAssertEqual(reloaded.deadline(for: refreshed, now: now), reset)
        XCTAssertNil(reloaded.deadline(for: account, now: reset))
        XCTAssertEqual(account.fiveHourWindow?.usedPercentage, 99)
        XCTAssertNil(reloaded.deadline(for: makeAccount(workspace: "b", reset: reset), now: now))
        XCTAssertNil(reloaded.deadline(for: makeAccount(workspace: nil, reset: reset), now: now))
        reloaded.unlock(account)
        XCTAssertNil(ManualUsageLockStore(defaults: defaults).deadline(for: account, now: now))
    }

    @MainActor
    func testLockRequiresFutureResetAndSurvivesMissingUsage() {
        let suite = "manual-lock-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ManualUsageLockStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for reset in [nil, now, now.addingTimeInterval(-1)] {
            let account = makeAccount(workspace: "a", reset: reset)
            XCTAssertNil(store.availableReset(for: account, now: now))
            store.lock(account, now: now)
            XCTAssertNil(store.deadline(for: account, now: now))
        }
        let reset = now.addingTimeInterval(300)
        store.lock(makeAccount(workspace: "a", reset: reset), now: now)
        XCTAssertEqual(store.deadline(for: makeAccount(workspace: "a", reset: nil), now: now), reset)
    }

    private func makeAccount(workspace: String?, reset: Date?) -> AccountSnapshot {
        AccountSnapshot(
            accountId: "account", label: "Account", email: "same@example.com",
            workspaceId: workspace, workspaceLabel: "Raw workspace", plan: "Codex Team",
            source: "test", systemAuthProfileId: nil, isCurrentSystemAccount: false,
            lastSyncedAt: "", usageWindows: reset.map {
                [UsageWindow(id: "five-hour", scope: .shortHorizon, durationSeconds: 18000,
                    available: true, label: "5-hour", usedMinutes: 297, limitMinutes: 300,
                    usedPercentage: 99, resetsAt: $0.ISO8601Format())]
            } ?? []
        )
    }
}
