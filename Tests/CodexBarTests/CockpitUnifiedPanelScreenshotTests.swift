import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in proof renders the actual panel and native-menu bridge using contained synthetic state.
@MainActor
struct CockpitUnifiedPanelScreenshotTests {
    @Test
    func `render actual unified usage and calendar panels with a synthetic hosted provider card`() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_COCKPIT_PROOF_DIR"],
              !path.isEmpty else { return }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("CockpitUnifiedPanelProof-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        try await CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let now = Date()
            let settings = try Self.makeSettings(in: temporary)
            let store = UsageStore(
                fetcher: UsageFetcher(environment: [:]),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings,
                historicalUsageHistoryStore: HistoricalUsageHistoryStore(
                    fileURL: temporary.appendingPathComponent("history.json")),
                startupBehavior: .testing,
                environmentBase: [
                    "HOME": temporary.path,
                    "CODEX_HOME": temporary.appendingPathComponent("codex").path,
                    "CLAUDE_CONFIG_DIR": temporary.appendingPathComponent("claude").path,
                ],
                pluginApprovalStore: ProviderPluginApprovalStore(
                    fileURL: temporary.appendingPathComponent("plugin-approvals.json")),
                widgetSnapshotURL: temporary.appendingPathComponent("widget.json"),
                cliUsageCacheURL: temporary.appendingPathComponent("cli-cache.json"),
                widgetTimelineReloader: {})
            let tokens = try Self.tokenSnapshot(now: now)
            let configuration = SpendDashboardSource.configuration(settings: settings, store: store)
            let input = SpendDashboardModel.ProviderInput(
                provider: .claude, displayName: "Claude · 合成数据", snapshot: tokens)
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
                controller.stop()
                store.stopSharedSpendDashboardPublication()
                settings.configFileWatcher?.stop()
            }
            controller.update(configuration: configuration)
            try await Self.waitUntilIdle(controller)

            let plan = CockpitPlanStore(fileURL: temporary.appendingPathComponent("plan.json"))
            let midnight = Calendar.current.startOfDay(for: now)
            plan.ingest([.claude: Self.quota(at: midnight, now: now, usedPercent: 0)])
            let quota = Self.quota(at: now, now: now, usedPercent: 12)
            plan.ingest([.claude: quota])
            plan.setPersonalCap(18, for: .claude)
            plan.recordLocalComfort(.comfortable, for: .codex, totalTokens: nil)
            #expect(plan.availableProviders == [.claude])
            #expect(plan.status(for: .claude).effectiveCapPercent == 18)

            let bridge = CockpitMenuBridge()
            bridge.width = 704
            let card = try Self.makeCard(quota: quota, tokens: tokens, now: now, width: bridge.width)
            let menu = Self.makeMenu(card: card)
            bridge.reload(menu)
            let navigation = CockpitPanelNavigation()
            navigation.planningProviders = [.claude]
            let root = CockpitPanelView(
                settings: settings,
                store: store,
                planStore: plan,
                navigation: navigation,
                usageContent: AnyView(CockpitMenuBridgeView(bridge: bridge).padding(.horizontal, 16)),
                onSettings: {},
                onRefresh: {})
            let size = CGSize(width: 760, height: 650)
            let host = NSHostingView(rootView: root
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN")))
            host.appearance = NSAppearance(named: .aqua)
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            defer {
                window.contentView = nil
                window.close()
            }

            try await Self.settle(host, controller: controller)
            #expect(card.superview != nil, "The real bridge must mount the custom NSMenuItem view")
            #expect(menu.items.contains { $0.view === card })
            try Self.capture(
                host,
                size: size,
                to: output.appendingPathComponent("cockpit-unified-usage-synthetic-zh.png"))

            navigation.page = .calendar
            try await Self.settle(host, controller: controller)
            try Self.capture(
                host,
                size: size,
                to: output.appendingPathComponent("cockpit-unified-calendar-synthetic-zh.png"))
        }
    }

    private static func makeSettings(in directory: URL) throws -> SettingsStore {
        let configStore = CodexBarConfigStore(fileURL: directory.appendingPathComponent("config.json"))
        var config = testConfigWithAllProvidersDisabled()
        config.setProviderConfig(ProviderConfig(id: .claude, enabled: true, source: .cli))
        try configStore.save(config)
        return SettingsStore(
            userDefaults: InMemoryUserDefaults(values: [
                "tokenCostUsageEnabled": true,
                "preferredCurrencyCode": "USD",
                "tokenCostUsageBucketTimeZone": TimeZone.current.identifier,
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

    private static func quota(at capturedAt: Date, now: Date, usedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: 24,
                windowMinutes: 300,
                resetsAt: now.addingTimeInterval(4 * 3600),
                resetDescription: nil),
            secondary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 10080,
                resetsAt: Calendar.current.startOfDay(for: now).addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: capturedAt,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: "synthetic-only@example.invalid",
                accountOrganization: "Synthetic proof",
                loginMethod: "Synthetic Pro",
                accountID: "synthetic-panel-account"))
    }

    private static func tokenSnapshot(now: Date) throws -> CostUsageTokenSnapshot {
        let calendar = Calendar.current
        let daily = try (0..<30).map { offset in
            let day = try #require(calendar.date(byAdding: .day, value: -offset, to: now))
            let tokens = (offset + 1) * 12000
            return CostUsageDailyReport.Entry(
                date: CockpitCalendar.dateKey(for: day, calendar: calendar),
                inputTokens: tokens * 3 / 4,
                outputTokens: tokens / 4,
                totalTokens: tokens,
                costUSD: Double(offset + 1) * 0.08,
                modelsUsed: ["synthetic-proof-model"],
                modelBreakdowns: nil)
        }
        return CostUsageTokenSnapshot(
            sessionTokens: 12000,
            sessionCostUSD: 0.08,
            last30DaysTokens: daily.compactMap(\.totalTokens).reduce(0, +),
            last30DaysCostUSD: daily.compactMap(\.costUSD).reduce(0, +),
            historyDays: 30,
            daily: daily,
            updatedAt: now)
    }

    private static func makeCard(
        quota: UsageSnapshot,
        tokens: CostUsageTokenSnapshot,
        now: Date,
        width: CGFloat) throws -> NSHostingView<AnyView>
    {
        let metadata = try #require(ProviderDefaults.metadata[.claude])
        let model = UsageMenuCardView.Model.make(.init(
            provider: .claude,
            metadata: metadata,
            snapshot: quota,
            credits: nil,
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: tokens,
            tokenError: nil,
            account: AccountInfo(email: "synthetic-only@example.invalid", plan: "Synthetic Pro"),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: false,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: true,
            showOptionalCreditsAndExtraUsage: true,
            sourceLabel: "synthetic",
            subtitleOverride: "合成额度与 Token 用量 · 未连接真实账号",
            hidePersonalInfo: false,
            preferredCurrencyCode: "USD",
            now: now))
        let card = NSHostingView(rootView: AnyView(UsageMenuCardView(model: model, width: width)
                .environment(\.colorScheme, .light)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))))
        card.appearance = NSAppearance(named: .aqua)
        card.frame = NSRect(x: 0, y: 0, width: width, height: max(1, ceil(card.fittingSize.height)))
        card.layoutSubtreeIfNeeded()
        return card
    }

    private static func makeMenu(card: NSView) -> NSMenu {
        let menu = NSMenu(title: "Synthetic provider menu")
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: "合成数据预览 · 不读取真实账号或日志", action: nil, keyEquivalent: ""))
        let item = NSMenuItem(title: "Claude · 合成用量卡片", action: nil, keyEquivalent: "")
        item.view = card
        menu.addItem(item)
        menu.addItem(.separator())
        let details = NSMenuItem(title: "查看合成提供商详情", action: nil, keyEquivalent: "")
        details.submenu = NSMenu(title: "Synthetic details")
        details.submenu?.addItem(NSMenuItem(title: "仅用于布局验证", action: nil, keyEquivalent: ""))
        menu.addItem(details)
        return menu
    }

    private static func settle(_ host: NSView, controller: SpendDashboardController) async throws {
        for _ in 0..<3 {
            host.window?.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        try await self.waitUntilIdle(controller)
        host.layoutSubtreeIfNeeded()
    }

    private static func waitUntilIdle(_ controller: SpendDashboardController) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while controller.isRefreshing {
            guard ContinuousClock.now < deadline else { throw ProofError.loaderTimeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func capture(_ host: NSView, size: CGSize, to url: URL) throws {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0))
        bitmap.size = size
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        host.displayIgnoringOpacity(host.bounds, in: context)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        #expect(bitmap.pixelsWide == 760)
        #expect(bitmap.pixelsHigh == 650)
        try png.write(to: url)
    }

    private enum ProofError: Error { case loaderTimeout }
}
