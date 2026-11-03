import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct QuotaWarningRepeatTests {
    private final class NotifierSpy: SessionQuotaNotifying {
        var warnings: [QuotaWarningEvent] = []

        func post(transition _: SessionQuotaTransition, provider _: UsageProvider, badge _: NSNumber?) {}

        func postQuotaWarning(
            event: QuotaWarningEvent,
            provider _: UsageProvider,
            soundEnabled _: Bool,
            onScreenAlertEnabled _: Bool)
        {
            self.warnings.append(event)
        }
    }

    @Test(arguments: [UsageProvider.codex, .claude], [QuotaWarningWindow.session, .weekly])
    func `missing readings do not repeat the fifty percent warning`(
        provider: UsageProvider, lane: QuotaWarningWindow)
    {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        for (index, remaining) in [60.0, 49, nil, 48, nil, 47].enumerated() {
            store.handleQuotaWarningTransitions(
                provider: provider,
                snapshot: self.snapshot(remaining: remaining, lane: lane, step: index),
                accountDiscriminator: "fixture-account-a")
        }
        #expect(notifier.warnings.map(\.threshold) == [50])
        #expect(notifier.warnings.map(\.window) == [lane])
    }

    @Test(arguments: [true, false])
    func `other providers preserve recovery and lower threshold warnings through gaps`(recovers: Bool) {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        let readings: [Double?] = recovers ? [60, 49, nil, 55, 49] : [60, 49, nil, 19, 18]
        for (step, remaining) in readings.enumerated() {
            store.handleQuotaWarningTransitions(
                provider: .claude,
                snapshot: self.snapshot(remaining: remaining, lane: .weekly, step: step),
                accountDiscriminator: "fixture-account-a")
        }
        #expect(notifier.warnings.map(\.threshold) == (recovers ? [50, 50] : [50, 20]))
    }

    @Test(arguments: [UsageProvider.codex, .claude])
    func `older high readings cannot rearm an already fired warning`(provider: UsageProvider) {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        for (step, remaining) in [(0, 60.0), (2, 49), (1, 60), (3, 48)] {
            store.handleQuotaWarningTransitions(
                provider: provider,
                snapshot: self.snapshot(remaining: remaining, lane: .weekly, step: step),
                accountDiscriminator: "fixture-account-a")
        }
        #expect(notifier.warnings.map(\.threshold) == [50])
    }

    @Test(arguments: [true, false])
    func `a real reset after a gap can warn in the new cycle`(missingResetMetadata: Bool) {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: self.snapshot(remaining: 60, lane: .weekly, step: -1, resetOffset: 60),
            accountDiscriminator: "fixture-account-a")
        let samples: [(Double?, Int, Double?)] = [
            (49, 0, 60),
            (missingResetMetadata ? 48 : nil, 1, nil),
            (47, 61, 86460),
            (46, 62, 86460),
        ]
        for (remaining, step, resetOffset) in samples {
            store.handleQuotaWarningTransitions(
                provider: .codex,
                snapshot: self.snapshot(remaining: remaining, lane: .weekly, step: step, resetOffset: resetOffset),
                accountDiscriminator: "fixture-account-a")
        }
        #expect(notifier.warnings.map(\.threshold) == [50, 50])
    }

    @Test
    func `moving or elapsed reset metadata alone cannot repeat a warning`() {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        store.handleQuotaWarningTransitions(
            provider: .codex,
            snapshot: self.snapshot(remaining: 60, lane: .weekly, step: -1, resetOffset: 60),
            accountDiscriminator: "fixture-account-a")
        for (step, resetOffset) in [(0, 60.0), (1, 600), (2, 60), (61, 60), (62, 30)] {
            store.handleQuotaWarningTransitions(
                provider: .codex,
                snapshot: self.snapshot(remaining: 49, lane: .weekly, step: step, resetOffset: resetOffset),
                accountDiscriminator: "fixture-account-a")
        }
        #expect(notifier.warnings.map(\.threshold) == [50])
    }

    @Test
    func `missing readings keep account and quota window episodes independent`() {
        let notifier = NotifierSpy()
        let store = self.makeStore(notifier: notifier)
        let samples: [(String, QuotaWarningWindow, Double?)] = [
            ("a", .session, 49), ("a", .session, nil), ("b", .session, 49),
            ("a", .weekly, 60), ("a", .weekly, 49), ("a", .session, 48), ("b", .session, nil),
            ("a", .weekly, nil), ("b", .session, 48), ("a", .weekly, 48),
        ]
        for (step, sample) in samples.enumerated() {
            store.handleQuotaWarningTransitions(
                provider: .codex,
                snapshot: self.snapshot(remaining: sample.2, lane: sample.1, step: step),
                accountDiscriminator: sample.0)
        }
        #expect(notifier.warnings.map(\.threshold) == [50, 50, 50])
        #expect(notifier.warnings.map(\.window) == [.session, .session, .weekly])
        // Codex weekly state is persisted separately; session episodes retain their original scope.
        #expect(store.quotaWarningState.count == 2)
        #expect(store.quotaWarningState.values.allSatisfy { $0.firedThresholds == [50] })
    }

    private func makeStore(notifier: NotifierSpy) -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "QuotaWarningRepeatTests",
            userDefaults: InMemoryUserDefaults(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings.quotaWarningNotificationsEnabled = true
        settings.quotaWarningThresholds = [50, 20]
        settings.setQuotaWarningWindowEnabled(.session, enabled: true)
        settings.setQuotaWarningWindowEnabled(.weekly, enabled: true)
        settings.sessionQuotaNotificationsEnabled = false
        settings.predictivePaceWarningNotificationsEnabled = false
        return UsageStore(
            fetcher: UsageFetcher(),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            sessionQuotaNotifier: notifier,
            startupBehavior: .testing)
    }

    private func snapshot(
        remaining: Double?,
        lane: QuotaWarningWindow,
        step: Int,
        resetOffset: TimeInterval? = 7 * 24 * 60 * 60) -> UsageSnapshot
    {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let window = remaining.map {
            RateWindow(
                usedPercent: 100 - $0,
                windowMinutes: lane == .session ? 300 : 10080,
                resetsAt: resetOffset.map { start.addingTimeInterval($0) },
                resetDescription: nil)
        }
        return UsageSnapshot(
            primary: lane == .session ? window : nil,
            secondary: lane == .weekly ? window : nil,
            updatedAt: start.addingTimeInterval(Double(step)))
    }
}
