import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct CockpitLiveAdviceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `announcement outranks a conflicting forecast without extending the account deadline`() throws {
        let accountReset = self.now.addingTimeInterval(5 * 86400)
        let forecast = try self.forecast()
        let announced = try self.scheduled(at: self.now.addingTimeInterval(2 * 86400))
        let selected = CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset, scheduled: announced, forecast: forecast, now: self.now)
        #expect(selected?.source == .announced)
        #expect(selected?.resetsAt == announced.scheduledFor)
        let later = try self.scheduled(at: accountReset.addingTimeInterval(86400))
        #expect(CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset, scheduled: later, forecast: forecast, now: self.now)?.source == .account)
        #expect(CockpitPlanningResetWindow.resolve(
            accountResetAt: self.now, scheduled: announced, forecast: forecast, now: self.now) == nil)
    }

    @Test
    func `undated or overdue pending announcements cannot revive an older estimate`() throws {
        let accountReset = self.now.addingTimeInterval(5 * 86400)
        for announcedDate in [nil, self.now.addingTimeInterval(-1)] {
            let selected = try CockpitPlanningResetWindow.resolve(
                accountResetAt: accountReset,
                scheduled: self.scheduled(at: announcedDate),
                forecast: self.forecast(),
                now: self.now)
            #expect(selected?.source == .account)
        }
        let banked = try self.scheduled(at: self.now.addingTimeInterval(60), kind: .banked)
        #expect(CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset, scheduled: banked, now: self.now)?.source == .account)
    }

    @Test
    func `expired estimates and newer public reset events fall back without inventing a next cycle`() throws {
        let accountReset = self.now.addingTimeInterval(5 * 86400)
        let forecast = try self.forecast()
        let before = CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset, forecast: forecast, now: self.now)
        #expect(before?.source == .estimated)
        #expect(before?.resetsAt == forecast.estimatedAt)
        let newer = try self.event(id: "newer", at: forecast.anchorDate.addingTimeInterval(1))
        #expect(CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset,
            forecast: forecast,
            latestPublicReset: newer,
            now: self.now)?.source == .account)
        #expect(CockpitPlanningResetWindow.resolve(
            accountResetAt: accountReset, forecast: forecast, now: forecast.estimatedAt)?.source == .account)
    }

    @Test
    func `live horizon changes advice while manual caps observed use and archived anchors stay independent`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let start = calendar.startOfDay(for: self.now)
        let noon = start.addingTimeInterval(12 * 3600)
        let accountReset = start.addingTimeInterval(7 * 86400)
        var state = CockpitPlanState()
        state.record(CockpitQuotaSnapshot(
            providerID: "codex", capturedAt: start, remainingPercent: 70, resetsAt: accountReset), calendar: calendar)
        state.record(CockpitQuotaSnapshot(
            providerID: "codex", capturedAt: noon, remainingPercent: 50, resetsAt: accountReset), calendar: calendar)
        let originalAnchors = state.plans
        state.setPersonalCap(30, providerID: "codex", on: noon, calendar: calendar)
        let account = state.status(providerID: "codex", on: noon, calendar: calendar)
        let estimate = CockpitPlanningResetWindow(resetsAt: noon.addingTimeInterval(6 * 3600), source: .estimated)
        let estimated = state.status(
            providerID: "codex", on: noon, calendar: calendar, planningResetWindow: estimate)
        #expect(account.suggestedPercent == 11.36)
        #expect(abs((estimated.suggestedPercent ?? -1) - (estimated.comfortAdvice?.softCapPercent ?? -2)) <= 0.0051)
        #expect(estimated.usedPercent == 20)
        #expect(estimated.manualCapPercent == 30)
        #expect(estimated.effectiveCapPercent == 30)
        #expect(estimated.resetsAt == accountReset)
        #expect(estimated.planningResetWindow == estimate)
        let later = state.status(
            providerID: "codex",
            on: noon.addingTimeInterval(7 * 3600),
            calendar: calendar,
            planningResetWindow: estimate)
        #expect(later.planningResetWindow?.source == .account)
        #expect(later.usedPercent == 20)
        #expect(later.remainingPercent == 50)
        #expect(later.suggestedPercent != account.suggestedPercent)
        #expect(later.suggestionIsPartial)
        #expect(state.plans == originalAnchors)
        #expect(state.snapshots.count == 2)
    }

    @Test
    func `a first partial day remains provisional and another provider ignores public Codex windows`() {
        let reset = self.now.addingTimeInterval(5 * 86400)
        var state = CockpitPlanState()
        for provider in ["codex", "claude"] {
            state.record(CockpitQuotaSnapshot(
                providerID: provider, capturedAt: self.now, remainingPercent: 50, resetsAt: reset))
        }
        let estimate = CockpitPlanningResetWindow(resetsAt: self.now.addingTimeInterval(60), source: .estimated)
        let codex = state.status(providerID: "codex", on: self.now, planningResetWindow: estimate)
        #expect(codex.usedPercent == nil)
        #expect(codex.suggestionIsPartial)
        #expect(abs((codex.suggestedPercent ?? -1) - (codex.comfortAdvice?.softCapPercent ?? -2)) <= 0.0051)
        #expect(codex.remainingSuggestedPercent == nil)
        let claude = state.status(providerID: "claude", on: self.now, planningResetWindow: estimate)
        #expect(claude.planningResetWindow?.source == .account)
        #expect(claude.resetsAt == reset)
        #expect(state.status(providerID: "codex", accountID: "other", on: self.now).suggestedPercent == nil)
    }

    @Test
    func `reset refresh updates displayed advice without new quota and stale public metadata expires`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = AdviceResetFeed(
            status: CockpitResetStatus(generatedAt: self.now),
            history: CockpitResetHistory(events: [], generatedAt: self.now))
        let now = self.now
        let resets = CockpitResetHistoryStore(
            cacheURL: directory.appendingPathComponent("history.json"),
            receiptsURL: directory.appendingPathComponent("notices.json"),
            notificationsEnabled: { false },
            fetch: { await feed.history },
            fetchStatus: { await feed.status },
            now: { now },
            post: { _ in },
            remove: { _ in })
        let plans = CockpitPlanStore(fileURL: directory.appendingPathComponent("plan.json"), resetHistoryStore: resets)
        let accountReset = self.now.addingTimeInterval(5 * 86400)
        plans.ingest([.codex: UsageSnapshot(
            primary: nil,
            secondary: RateWindow(usedPercent: 30, windowMinutes: 10080, resetsAt: accountReset, resetDescription: nil),
            updatedAt: self.now,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil,
                accountID: "synthetic-live-advice"))])
        await resets.refresh()
        let baseline = try #require(plans.status(for: .codex, on: self.now).suggestedPercent)
        let invalidated = AdviceInvalidation()
        withObservationTracking {
            _ = plans.status(for: .codex, on: self.now).suggestedPercent
        } onChange: { invalidated.mark() }
        let announced = try self.scheduled(at: self.now.addingTimeInterval(3600))
        await feed.setStatus(CockpitResetStatus(generatedAt: self.now, scheduledReset: announced))
        await resets.refresh()
        #expect(invalidated.value)
        let updated = plans.status(for: .codex, on: self.now)
        #expect(updated.planningResetWindow?.source == .announced)
        #expect(abs((updated.suggestedPercent ?? -1) - (updated.comfortAdvice?.softCapPercent ?? -2)) <= 0.0051)
        #expect((updated.suggestedPercent ?? 0) > baseline)
        #expect(plans.state.snapshots.count == 1)
        #expect(resets.planningWindow(accountResetAt: accountReset, on: self.now.addingTimeInterval(16 * 60))?
            .source == .account)
    }

    @Test
    func `fresh historical estimates are independent of notifications and expire from planning`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = try self.history()
        let now = self.now
        let resets = CockpitResetHistoryStore(
            cacheURL: directory.appendingPathComponent("history.json"),
            receiptsURL: directory.appendingPathComponent("notices.json"),
            notificationsEnabled: { false },
            fetch: { history },
            now: { now },
            post: { _ in Issue.record("Notifications are disabled") },
            remove: { _ in })
        await resets.refresh()
        let reset = self.now.addingTimeInterval(5 * 86400)
        #expect(resets.planningWindow(accountResetAt: reset, on: self.now)?.source == .estimated)
        #expect(resets.planningWindow(accountResetAt: reset, on: self.now.addingTimeInterval(31 * 60))?
            .source == .account)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("notices.json").path))
    }

    private func forecast() throws -> CockpitResetForecast {
        try #require(CockpitResetForecast.estimate(events: self.history().events, now: self.now))
    }

    private func history() throws -> CockpitResetHistory {
        let events = try (0..<4).map { index in
            try self.event(id: "synthetic-\(index)", at: self.now.addingTimeInterval(-Double(index) * 86400 - 3600))
        }
        return CockpitResetHistory(events: events, generatedAt: self.now)
    }

    private func event(id: String, at date: Date) throws -> CockpitResetEvent {
        try CockpitResetEvent(
            id: id,
            kind: .regular,
            announcedAt: date,
            text: "Synthetic reset",
            sourceType: "synthetic",
            sourceURL: URL(string: "https://example.com/reset")!)
    }

    private func scheduled(at date: Date?, kind: CockpitResetKind = .regular) throws -> CockpitScheduledReset {
        try CockpitScheduledReset(
            id: "synthetic-scheduled",
            kind: kind,
            announcedAt: self.now.addingTimeInterval(-60),
            scheduledFor: date,
            text: "Synthetic plan",
            sourceURL: URL(string: "https://example.com/reset")!)
    }
}

private actor AdviceResetFeed {
    var status: CockpitResetStatus
    let history: CockpitResetHistory

    init(status: CockpitResetStatus, history: CockpitResetHistory) {
        self.status = status
        self.history = history
    }

    func setStatus(_ status: CockpitResetStatus) { self.status = status }
}

private final class AdviceInvalidation: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        self.lock.withLock { self.flag }
    }

    func mark() { self.lock.withLock { self.flag = true } }
}
