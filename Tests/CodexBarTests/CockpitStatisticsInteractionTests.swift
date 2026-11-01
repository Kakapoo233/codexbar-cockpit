import AppKit
import SwiftUI
import Testing
@testable import CodexBar
@testable import CodexBarCore

/// Retain the real unified pages and native bridge while checking the active statistics hit path.
@MainActor
struct CockpitStatisticsInteractionTests {
    @Test(arguments: [CGSize(width: 960, height: 700), CGSize(width: 676, height: 460)])
    func `retained pages do not intercept the statistics control center or its selection binding`(
        size: CGSize) async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CockpitStatisticsInteraction-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try await CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let settings = try Self.settings(in: directory)
            settings.configFileWatcher?.stop()
            let store = UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings,
                historicalUsageHistoryStore: HistoricalUsageHistoryStore(
                    fileURL: directory.appendingPathComponent("history.json")),
                planUtilizationHistoryStore: PlanUtilizationHistoryStore(directoryURL: nil),
                startupBehavior: .testing,
                environmentBase: [
                    "HOME": directory.path,
                    "CODEX_HOME": directory.appendingPathComponent("codex").path,
                    "CLAUDE_CONFIG_DIR": directory.appendingPathComponent("claude").path,
                ],
                pluginApprovalStore: ProviderPluginApprovalStore(
                    fileURL: directory.appendingPathComponent("plugins.json")),
                widgetSnapshotURL: directory.appendingPathComponent("widget.json"),
                cliUsageCacheURL: directory.appendingPathComponent("cli.json"),
                widgetTimelineReloader: {})
            store._test_providerRefreshOverride = { _ in
                Issue.record("Synthetic panel interaction must not contact a provider")
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
            controller.selectPeriod(.rolling(days: 7))
            controller.update(configuration: configuration)
            try await SpendDashboardStateWait.until {
                !controller.isRefreshing && !controller.model.groups.isEmpty
            }
            let plan = CockpitPlanStore(fileURL: directory.appendingPathComponent("plan.json"))
            let navigation = CockpitPanelNavigation()
            navigation.page = .usage
            let bridge = CockpitMenuBridge()
            bridge.width = CockpitPanelLayout(width: size.width).menuCardWidth
            let card = NSHostingView(rootView: Text("Synthetic provider card")
                .frame(width: bridge.width, height: 260)
                .background(Color.gray.opacity(0.1)))
            card.frame = CGRect(x: 0, y: 0, width: bridge.width, height: 260)
            let menu = NSMenu(title: "Synthetic provider menu")
            menu.autoenablesItems = false
            let item = NSMenuItem(title: "Synthetic provider card", action: nil, keyEquivalent: "")
            item.view = card
            menu.addItem(item)
            bridge.reload(menu)
            let root = CockpitPanelView(
                settings: settings,
                store: store,
                planStore: plan,
                navigation: navigation,
                usageContent: AnyView(CockpitMenuBridgeView(bridge: bridge)),
                onSettings: {},
                onRefresh: {})
            let host = NSHostingView(rootView: root.codexBarLocalized()
                .environment(\.locale, Locale(identifier: "en_US")))
            host.frame = CGRect(origin: .zero, size: size)
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
            let periods: [CostReportingPeriod] = [
                .rolling(days: 7), .rolling(days: 30), .rolling(days: 90), .monthToDate, .allTime,
            ]
            for page in [CockpitPanelPage.usage, .statistics, .calendar, .statistics] {
                navigation.page = page
                try await Self.settle(host, controller: controller)
                if page == .usage {
                    #expect(card.superview != nil, "The real menu bridge must mount the synthetic native card")
                    #expect(card.window === window)
                    continue
                }
                if page == .calendar {
                    let calendarPicker = Self.controls(in: host).first { control in
                        control.superview is CockpitCalendarPickerHost
                    }
                    #expect(calendarPicker != nil, "The actual retained calendar must be mounted")
                    continue
                }
                for (index, period) in periods.enumerated() {
                    let control = try #require(Self.statisticsPicker(in: host))
                    let frame = control.convert(control.bounds, to: host)
                    #expect(host.bounds.contains(frame), "The statistics picker must be inside the visible panel")
                    #expect(control.window === window)
                    let parent = try #require(host.superview)
                    // Native segment AX children are unavailable in an undisplayed window.
                    // This checks the real control's center, not a guessed per-segment mouse position.
                    let center = CGPoint(x: control.bounds.midX, y: control.bounds.midY)
                    let parentPoint = control.convert(center, to: parent)
                    let hit = try #require(
                        host.hitTest(parentPoint),
                        "No hit for \(size), segment \(index), point \(parentPoint), picker \(frame)")
                    #expect(
                        hit === control || hit.isDescendant(of: control),
                        "\(size), segment \(index): hit \(type(of: hit)) instead of the active statistics range")
                    #expect(control.isEnabled(forSegment: index))
                    control.selectedSegment = index
                    let action = try #require(control.action)
                    let target = try #require(control.target)
                    let handled = control.sendAction(action, to: target)
                    #expect(handled)
                    try await Self.settle(host, controller: controller)
                    #expect(controller.selectedPeriod == period)
                    let updated = try #require(Self.statisticsPicker(in: host))
                    #expect(updated.selectedSegment == index)
                }
            }
        }
    }

    private static func statisticsPicker(in host: NSView) -> NSSegmentedControl? {
        let labels = [
            spendDashboardDayRangeText(7), spendDashboardDayRangeText(30), spendDashboardDayRangeText(90),
            L("Month to date"), L("All"),
        ]
        let matches = Self.controls(in: host).filter { control in
            control.segmentCount == labels.count
                && labels.enumerated().allSatisfy { control.label(forSegment: $0.offset) == $0.element }
                && !(control.superview is CockpitCalendarPickerHost)
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func controls(in view: NSView) -> [NSSegmentedControl] {
        (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap { Self.controls(in: $0) }
    }

    private static func settle(_ host: NSView, controller: SpendDashboardController) async throws {
        for _ in 0..<3 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        try await SpendDashboardStateWait.until { !controller.isRefreshing }
    }

    private static func input(now: Date, calendar: Calendar) throws -> SpendDashboardModel.ProviderInput {
        let daily = try [1, 10, 25, 60, 120].map { offset in
            let date = try #require(calendar.date(byAdding: .day, value: -offset, to: now))
            return CostUsageDailyReport.Entry(
                date: CockpitCalendar.dateKey(for: date, calendar: calendar),
                inputTokens: 1000,
                outputTokens: 100,
                totalTokens: 1100,
                costUSD: 1,
                modelsUsed: ["synthetic-panel-model"],
                modelBreakdowns: nil)
        }
        return SpendDashboardModel.ProviderInput(
            provider: .claude,
            displayName: "Synthetic panel history",
            snapshot: CostUsageTokenSnapshot(
                sessionTokens: 1100,
                sessionCostUSD: 1,
                last30DaysTokens: 5500,
                last30DaysCostUSD: 5,
                historyDays: 365,
                historyCoverageIsEstablished: true,
                daily: daily,
                updatedAt: now))
    }

    private static func settings(in directory: URL) throws -> SettingsStore {
        let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        var config = testConfigWithAllProvidersDisabled()
        config.setProviderConfig(ProviderConfig(id: .claude, enabled: true, source: .cli))
        try configStore.save(config)
        return SettingsStore(
            userDefaults: InMemoryUserDefaults(values: [
                "tokenCostUsageEnabled": true,
                "preferredCurrencyCode": "USD",
                "tokenCostUsageBucketTimeZone": "UTC",
                "statusChecksEnabled": false,
            ]),
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore(fileURL: directory.appendingPathComponent("accounts.json")),
            antigravityOAuthCredentialsStore: AntigravityOAuthCredentialsStore(
                fileURL: directory.appendingPathComponent("antigravity.json")),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }),
            performInitialProviderDetection: false)
    }
}
