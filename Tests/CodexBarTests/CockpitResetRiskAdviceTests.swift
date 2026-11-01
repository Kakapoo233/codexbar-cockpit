import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct CockpitResetRiskAdviceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `risk defaults remain explicit and stale watches cannot change advice`() async throws {
        try await self.withStore(status: CockpitResetStatus(
            generatedAt: self.now,
            activeWatch: self.watch()))
        { store in
            let reset = self.now.addingTimeInterval(5 * 86400)
            #expect(store.planningRisk(accountResetAt: reset, on: self.now)
                == CockpitResetRisk(probability: 0.7, source: .estimated))
            #expect(store.planningWindow(accountResetAt: reset, on: self.now)?.source == .account)
            #expect(store.planningRisk(accountResetAt: reset, on: self.now.addingTimeInterval(901)) == .assumed)
            #expect(store.planningRisk(accountResetAt: self.now, on: self.now) == .assumed)
        }
        for watch in try [self.watch(expires: -1), self.watch(percent: nil)] {
            try await self.withStore(status: CockpitResetStatus(generatedAt: self.now, activeWatch: watch)) { store in
                #expect(store
                    .planningRisk(accountResetAt: self.now.addingTimeInterval(86400), on: self.now) == .assumed)
            }
        }
    }

    @Test
    func `only dated regular announcements within 24 hours and before account reset get announced risk`() async throws {
        let reset = self.now.addingTimeInterval(5 * 86400)
        let ignoredDeadlines: [TimeInterval?] = [nil, -1, 86401, 6 * 86400]
        for seconds in ignoredDeadlines {
            let status = try CockpitResetStatus(
                generatedAt: self.now, scheduledReset: self.scheduled(after: seconds), activeWatch: self.watch())
            try await self.withStore(status: status) { store in
                #expect(store.planningRisk(accountResetAt: reset, on: self.now) == .assumed)
            }
        }
        let announced = try CockpitResetStatus(generatedAt: self.now, scheduledReset: self.scheduled(after: 86400))
        try await self.withStore(status: announced) { store in
            #expect(store.planningRisk(accountResetAt: reset, on: self.now)
                == CockpitResetRisk(probability: 1, source: .announced))
        }
        let banked = try CockpitResetStatus(
            generatedAt: self.now, scheduledReset: self.scheduled(after: 60, kind: .banked))
        try await self.withStore(status: banked) { store in
            #expect(store.planningRisk(accountResetAt: reset, on: self.now) == .assumed)
        }
    }

    @Test
    func `a watch changes Codex advice without quota refresh and never leaks to Claude`() async throws {
        let status = try CockpitResetStatus(generatedAt: self.now, activeWatch: self.watch())
        try await self.withStore(status: status, refresh: false) { resets in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let plans = CockpitPlanStore(
                fileURL: directory.appendingPathComponent("plan.json"),
                resetHistoryStore: resets)
            plans.ingest([.codex: self.snapshot(provider: .codex), .claude: self.snapshot(provider: .claude)])
            let before = plans.status(for: .codex, on: self.now)
            #expect(before.comfortAdvice?.risk == .assumed)
            #expect(before.usedPercent == nil)
            #expect(before.remainingSuggestedPercent == nil)
            let changed = RiskAdviceObservation()
            withObservationTracking {
                _ = plans.status(for: .codex, on: self.now).suggestedPercent
            } onChange: { changed.mark() }
            await resets.refresh()
            let after = plans.status(for: .codex, on: self.now)
            #expect(changed.value)
            #expect(after.planningResetWindow?.source == .account)
            #expect(after.comfortAdvice?.risk.source == .estimated)
            #expect(after.usedPercent == nil)
            #expect(after.remainingSuggestedPercent == nil)
            #expect((after.suggestedPercent ?? 0) > (before.suggestedPercent ?? 0))
            #expect(plans.status(for: .claude, on: self.now).comfortAdvice?.risk.probability == 0)
            #expect(plans.state.snapshots.count == 2)
        }
    }

    private func snapshot(provider: UsageProvider) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil,
                accountID: "synthetic-risk-account"))
    }

    private func watch(percent: Int? = 70, expires: TimeInterval = 3600) throws -> CockpitResetWatch {
        try CockpitResetWatch(
            id: "synthetic-watch",
            level: "elevated",
            resetChancePercent: percent,
            forecastWindow: "Synthetic window",
            observedAt: self.now.addingTimeInterval(-60),
            expiresAt: self.now.addingTimeInterval(expires),
            text: "Synthetic watch",
            sourceURL: URL(string: "https://example.com/watch")!)
    }

    private func scheduled(
        after seconds: TimeInterval?,
        kind: CockpitResetKind = .regular) throws -> CockpitScheduledReset
    {
        try CockpitScheduledReset(
            id: "synthetic-plan",
            kind: kind,
            announcedAt: self.now.addingTimeInterval(-60),
            scheduledFor: seconds.map { self.now.addingTimeInterval($0) },
            text: "Synthetic announcement",
            sourceURL: URL(string: "https://example.com/announcement")!)
    }

    private func withStore(
        status: CockpitResetStatus,
        refresh: Bool = true,
        body: (CockpitResetHistoryStore) async throws -> Void) async throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = self.now
        let store = CockpitResetHistoryStore(
            cacheURL: directory.appendingPathComponent("history.json"),
            receiptsURL: directory.appendingPathComponent("notices.json"),
            notificationsEnabled: { false },
            fetch: { CockpitResetHistory(events: [], generatedAt: now) },
            fetchStatus: { status },
            now: { now },
            post: { _ in Issue.record("Notifications are disabled") },
            remove: { _ in })
        if refresh { await store.refresh() }
        try await body(store)
    }
}

private final class RiskAdviceObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false
    var value: Bool {
        self.lock.withLock { self.changed }
    }

    func mark() { self.lock.withLock { self.changed = true } }
}
