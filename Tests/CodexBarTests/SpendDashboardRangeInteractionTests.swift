import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Diagnose the real header's native action → period binding → model projection with isolated history.
@MainActor
struct SpendDashboardRangeInteractionTests {
    @Test
    func `whole dashboard range choices keep native highlight days and cost synchronized`() async throws {
        try await CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let settings = testSettingsStore(
                suiteName: "SpendDashboardRangeInteraction",
                userDefaults: InMemoryUserDefaults(),
                config: testConfigWithAllProvidersDisabled())
            settings.configFileWatcher?.stop()
            enableTestProviders([.cursor], settings: settings)
            settings.historicalTrackingEnabled = false
            settings.costUsageEnabled = true
            settings.preferredCurrencyCode = "USD"
            settings.costUsageBucketTimeZoneIdentifier = "UTC"
            let store = UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings,
                planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
                startupBehavior: .testing,
                environmentBase: [:])
            store._test_providerRefreshOverride = { _ in
                Issue.record("Header range selection must not contact a provider")
            }
            store._test_widgetSnapshotSaveOverride = { _ in }
            let now = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
            let configuration = SpendDashboardSource.configuration(settings: settings, store: store)
            let input = try Self.input(now: now, calendar: configuration.bucketCalendar)
            let controller = SpendDashboardController(
                userDefaults: InMemoryUserDefaults(),
                requestBuilder: { mode in
                    SpendDashboardLoadRequest(
                        configuration: configuration,
                        capturedInputs: [input],
                        unavailableSourceIDs: [],
                        codexRequests: [],
                        now: now,
                        force: mode.forcesLoader)
                },
                loader: { request in
                    SpendDashboardLoadResult(inputs: request.capturedInputs, failedSourceIDs: [])
                },
                nowProvider: { now })
            store.sharedSpendDashboardControllerStorage = controller
            defer {
                store.stopSharedSpendDashboardPublication()
                settings.configFileWatcher?.stop()
            }
            controller.update(configuration: configuration)
            try await SpendDashboardStateWait.until {
                !controller.isRefreshing && !controller.model.groups.isEmpty
            }
            let host = NSHostingView(rootView: SpendDashboardPane(settings: settings, store: store)
                .environment(\.cockpitPageActive, false)
                .environment(\.locale, Locale(identifier: "en_US")))
            host.frame = CGRect(x: 0, y: 0, width: 900, height: 1250)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            try await Self.settle(host)
            let picker = try #require(Self.findRangePicker(in: host))
            #expect(picker.segmentCount == 5)
            #expect(picker.isEnabled)
            let examples: [(Int, CostReportingPeriod, Int, Double)] = [
                (0, .rolling(days: 7), 7, 1),
                (1, .rolling(days: 30), 30, 7),
                (2, .rolling(days: 90), 90, 15),
                (3, .monthToDate, 15, 3),
                (4, .allTime, 121, 31),
                (0, .rolling(days: 7), 7, 1),
            ]
            for (index, period, days, cost) in examples {
                let control = try #require(Self.findRangePicker(in: host))
                #expect(control.isEnabled(forSegment: index))
                control.selectedSegment = index
                let action = try #require(control.action)
                let target = try #require(control.target)
                let handled = control.sendAction(action, to: target)
                #expect(handled)
                try await Self.settle(host)
                #expect(controller.selectedPeriod == period)
                #expect(controller.model.requestedDays == days)
                let group = try #require(controller.model.groups.first)
                #expect(controller.model.groups.count == 1)
                #expect(group.currencyCode == "USD")
                #expect(group.totalCost == cost)
                let selected = try #require(Self.findRangePicker(in: host))
                #expect(selected.selectedSegment == index)
            }
        }
    }

    @Test
    func `whole dashboard range changes filter the displayed quota observation samples`() async throws {
        try await CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let settings = testSettingsStore(
                suiteName: "SpendDashboardWholePaneRangeInteraction",
                userDefaults: InMemoryUserDefaults(),
                config: testConfigWithAllProvidersDisabled())
            settings.configFileWatcher?.stop()
            enableTestProviders([.antigravity], settings: settings)
            settings.costUsageEnabled = true
            settings.preferredCurrencyCode = "USD"
            settings.costUsageBucketTimeZoneIdentifier = "UTC"
            let store = UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings,
                planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
                startupBehavior: .testing,
                environmentBase: [:])
            store._test_providerRefreshOverride = { _ in
                Issue.record("Whole-pane range selection must not contact a provider")
            }
            store._test_widgetSnapshotSaveOverride = { _ in }
            let now = try #require(ISO8601DateFormatter().date(from: "2026-10-15T12:00:00Z"))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
            let today = calendar.startOfDay(for: now)
            let entries = try [1, 10, 25, 60, 120].enumerated().map { index, offset in
                try PlanUtilizationHistoryEntry(
                    capturedAt: #require(calendar.date(byAdding: .day, value: -offset, to: today)),
                    usedPercent: Double((index + 1) * 10),
                    resetsAt: nil)
            }
            // A zero-cadence pool preserves exactly these capture dates. No synthetic reset windows
            // or gap-fill samples can make the expected range counts ambiguous.
            store.planUtilizationHistory[.antigravity] = PlanUtilizationHistoryBuckets(unscoped: [
                PlanUtilizationSeriesHistory(name: .antigravityGemini, windowMinutes: 0, entries: entries),
            ])
            store.planUtilizationHistoryRevision &+= 1
            #expect(SpendPlanUsageSection(store: store).providers == [.antigravity])
            // Derive this from the same isolated settings as the actual pane's onAppear. No source
            // profile, provider transport, real history directory or Keychain is used by the loader.
            let configuration = SpendDashboardSource.configuration(settings: settings, store: store)
            let controller = SpendDashboardController(
                userDefaults: InMemoryUserDefaults(),
                requestBuilder: { mode in
                    SpendDashboardLoadRequest(
                        configuration: configuration,
                        capturedInputs: [],
                        unavailableSourceIDs: [],
                        codexRequests: [],
                        now: now,
                        force: mode.forcesLoader)
                },
                loader: { request in
                    SpendDashboardLoadResult(inputs: request.capturedInputs, failedSourceIDs: [])
                },
                nowProvider: { now })
            store.sharedSpendDashboardControllerStorage = controller
            defer {
                store.stopSharedSpendDashboardPublication()
                settings.configFileWatcher?.stop()
            }
            controller.selectPeriod(.rolling(days: 7))
            controller.update(configuration: configuration)
            controller.refreshDateWindow(now: now)
            let host = NSHostingView(rootView: SpendDashboardPane(settings: settings, store: store)
                .environment(\.cockpitPageActive, false)
                .environment(\.locale, Locale(identifier: "en_US")))
            host.frame = CGRect(x: 0, y: 0, width: 900, height: 1250)
            let window = NSWindow(
                contentRect: host.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }
            try await Self.settle(host)
            try await SpendDashboardStateWait.until { !controller.isRefreshing }
            let examples: [(Int, CostReportingPeriod, Int)] = [
                (0, .rolling(days: 7), 1),
                (1, .rolling(days: 30), 3),
                (2, .rolling(days: 90), 4),
                (3, .monthToDate, 2),
                (4, .allTime, 5),
                (0, .rolling(days: 7), 1),
            ]
            for (index, period, sampleCount) in examples {
                let control = try #require(Self.findRangePicker(in: host))
                control.selectedSegment = index
                let action = try #require(control.action)
                let target = try #require(control.target)
                let handled = control.sendAction(action, to: target)
                #expect(handled)
                try await Self.settle(host)
                #expect(controller.selectedPeriod == period)
                let highlighted = try #require(Self.findRangePicker(in: host))
                #expect(highlighted.selectedSegment == index)
                let section = SpendPlanUsageSection(store: store)
                let histories = section.displayedHistories(for: .antigravity)
                #expect(histories.flatMap(\.entries).count == sampleCount)
                let timeline = section.timeline(for: .antigravity).model
                #expect(timeline.points.count == sampleCount)
                let earliest = try #require(entries.map(\.capturedAt).min())
                let expectedBounds = period.bounds(now: now, calendar: calendar, earliest: earliest)
                let expectedEnd = try #require(calendar.date(byAdding: .day, value: 1, to: today))
                #expect(timeline.domain == expectedBounds.lowerBound...expectedEnd)
            }
        }
    }

    private static func input(now: Date, calendar: Calendar) throws -> SpendDashboardModel.ProviderInput {
        let today = calendar.startOfDay(for: now)
        let distribution: [(Int, Double)] = [(1, 1), (10, 2), (25, 4), (60, 8), (120, 16)]
        let daily = try distribution.map { offset, cost in
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: today))
            return CostUsageDailyReport.Entry(
                date: CostUsageScanner.CostUsageDayRange.dayKey(from: day, calendar: calendar),
                inputTokens: 1000,
                outputTokens: 100,
                totalTokens: 1100,
                costUSD: cost,
                modelsUsed: ["synthetic-range-model"],
                modelBreakdowns: nil)
        }
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 1100,
            sessionCostUSD: 1,
            last30DaysTokens: 5500,
            last30DaysCostUSD: 31,
            historyDays: 365,
            historyCoverageIsEstablished: true,
            costProvenance: .listPriceEstimate,
            daily: daily,
            updatedAt: now)
        return SpendDashboardModel.ProviderInput(
            provider: .cursor,
            displayName: "Synthetic range history",
            snapshot: snapshot)
    }

    private static func settle(_ host: NSView) async throws {
        for _ in 0..<3 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private static func findRangePicker(in view: NSView) -> NSSegmentedControl? {
        if let control = view as? NSSegmentedControl, control.segmentCount == 5 { return control }
        for child in view.subviews {
            if let control = Self.findRangePicker(in: child) { return control }
        }
        return nil
    }
}
