import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitNavigationIsolationTests {
    @Test
    func `calendar projection leaves the statistics period selected day and saved defaults unchanged`() async throws {
        let fixture = try await Self.fixture()
        defer { fixture.controller.stop() }
        let projection = CockpitUsageProjection(controller: fixture.controller, nowProvider: { Self.now })
        let saved = fixture.defaults.string(forKey: "settingsSpendDashboardPeriod")
        let revision = fixture.controller.publication.revision
        #expect(fixture.controller.model.groups.first?.totalCost == 2)

        let calendar = projection.calendarModel

        #expect(calendar.selectedDay == nil)
        #expect(calendar.groups.first?.totalCost == 3)
        #expect(fixture.controller.selectedPeriod == .rolling(days: 7))
        #expect(fixture.controller.selectedDay == Self.selectedDay)
        #expect(fixture.defaults.string(forKey: "settingsSpendDashboardPeriod") == saved)
        #expect(fixture.controller.publication.revision == revision)
        #expect(await fixture.loads.count == 1)
    }

    @Test
    func `a shared publication refresh reaches the calendar without changing statistics filters`() async throws {
        let fixture = try await Self.fixture()
        defer { fixture.controller.stop() }
        let calendar = CockpitUsageProjection(controller: fixture.controller, nowProvider: { Self.now })
        #expect(calendar.calendarModel.groups.first?.totalCost == 3)

        fixture.controller.refresh()
        try await Self.waitUntilIdle(fixture.controller)

        #expect(calendar.calendarModel.groups.first?.totalCost == 6)
        #expect(fixture.controller.selectedPeriod == .rolling(days: 7))
        #expect(fixture.controller.selectedDay == Self.selectedDay)
        #expect(await fixture.loads.count == 2)
    }

    private static func fixture() async throws -> Fixture {
        let defaults = InMemoryUserDefaults(values: ["settingsSpendDashboardPeriod": "rolling:7"])
        let configuration = SpendDashboardConfiguration(
            costUsageEnabled: true,
            providerIDs: [UsageProvider.codex.rawValue],
            codexAccountIdentities: [],
            bucketTimeZoneIdentifier: "UTC")
        let first = Self.input(multiplier: 1)
        let second = Self.input(multiplier: 2)
        let now = Self.now
        let loads = Loads()
        let controller = SpendDashboardController(
            userDefaults: defaults,
            requestBuilder: { mode in
                let captured = await loads.inputs
                return SpendDashboardLoadRequest(
                    configuration: configuration,
                    capturedInputs: mode == .captureOnly ? captured : [],
                    unavailableSourceIDs: [],
                    codexRequests: [],
                    now: now,
                    force: mode.forcesLoader)
            },
            loader: { _ in
                let input = await loads.next(first: first, second: second)
                return SpendDashboardLoadResult(inputs: [input], failedSourceIDs: [])
            },
            nowProvider: { now })
        controller.update(configuration: configuration)
        try await Self.waitUntilIdle(controller)
        controller.selectDay(Self.selectedDay)
        return Fixture(controller: controller, defaults: defaults, loads: loads)
    }

    private static func input(multiplier: Int) -> SpendDashboardModel.ProviderInput {
        let entries = [("2026-10-01", 1), ("2026-10-28", 2)].map { day, amount in
            CostUsageDailyReport.Entry(
                date: day,
                inputTokens: amount * 100,
                outputTokens: 0,
                totalTokens: amount * 100,
                costUSD: Double(amount * multiplier),
                modelsUsed: nil,
                modelBreakdowns: nil)
        }
        return SpendDashboardModel.ProviderInput(
            id: "codex",
            provider: .codex,
            displayName: "Synthetic Codex",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: 300,
                last30DaysCostUSD: Double(3 * multiplier),
                historyDays: 30,
                daily: entries,
                updatedAt: Self.now))
    }

    private static func waitUntilIdle(_ controller: SpendDashboardController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.isRefreshing {
            guard ContinuousClock.now < deadline else { throw FixtureError.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_793_275_200)
    private static let selectedDay = Date(timeIntervalSince1970: 1_793_145_600)

    private struct Fixture {
        let controller: SpendDashboardController
        let defaults: InMemoryUserDefaults
        let loads: Loads
    }

    private actor Loads {
        private(set) var count = 0
        private(set) var inputs: [SpendDashboardModel.ProviderInput] = []
        func next(
            first: SpendDashboardModel.ProviderInput,
            second: SpendDashboardModel.ProviderInput) -> SpendDashboardModel.ProviderInput
        {
            self.count += 1
            let input = self.count == 1 ? first : second
            self.inputs = [input]
            return input
        }
    }

    private enum FixtureError: Error { case timeout }
}
