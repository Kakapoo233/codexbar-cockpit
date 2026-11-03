import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct CodexWeeklyQuotaWarningLedgerTests {
    private let start = Date(timeIntervalSince1970: 1_900_000_000)
    private let owner = "synthetic-owner@example.invalid"

    @Test
    func `serialized receipts contain no raw owner and are restored before another delivery`() throws {
        let defaults = InMemoryUserDefaults()
        let ledger = CodexWeeklyQuotaWarningLedger(defaults: defaults)
        #expect(self.observe(ledger, remaining: 60, step: 0) == nil)
        #expect(self.observe(ledger, remaining: 49, step: 1) == 50)
        let data = try #require(defaults.data(forKey: CodexWeeklyQuotaWarningLedger.defaultsKey))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains(self.owner))
        let entries = try Self.entries(data)
        #expect(entries.count == 1)
        #expect(entries.keys.allSatisfy { $0.count == 64 })
        #expect((entries.values.first?["firedThresholds"] as? [Int]) == [50])
        let restored = CodexWeeklyQuotaWarningLedger(defaults: InMemoryUserDefaults(values: [
            CodexWeeklyQuotaWarningLedger.defaultsKey: data,
        ]))
        #expect(self.observe(restored, remaining: 51, step: 2) == nil)
        #expect(self.observe(restored, remaining: 43, step: 3) == nil)
        #expect(self.observe(restored, remaining: 19, step: 4) == 20)
    }

    @Test(arguments: ["broken", "{\"version\":99,\"entries\":{}}"])
    func `unreadable or unsupported receipts establish a quiet low baseline`(payload: String) {
        let ledger = CodexWeeklyQuotaWarningLedger(defaults: InMemoryUserDefaults(values: [
            CodexWeeklyQuotaWarningLedger.defaultsKey: Data(payload.utf8),
        ]))
        #expect(self.observe(ledger, remaining: 44, step: 0) == nil)
        #expect(self.observe(ledger, remaining: 43, step: 1) == nil)
        #expect(self.observe(ledger, remaining: 19, step: 2) == 20)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func `invalid windows do not replace a valid receipt`(used: Double) {
        let defaults = InMemoryUserDefaults()
        let ledger = CodexWeeklyQuotaWarningLedger(defaults: defaults)
        #expect(self.observe(ledger, remaining: 60, step: 0) == nil)
        let before = defaults.data(forKey: CodexWeeklyQuotaWarningLedger.defaultsKey)
        #expect(ledger.observe(
            owner: self.owner,
            window: RateWindow(usedPercent: used, windowMinutes: 10080, resetsAt: nil, resetDescription: nil),
            observedAt: self.start.addingTimeInterval(1),
            thresholds: [50, 20]) == nil)
        #expect(defaults.data(forKey: CodexWeeklyQuotaWarningLedger.defaultsKey) == before)
        #expect(self.observe(ledger, remaining: 49, step: 2) == 50)
    }

    @Test
    func `stale samples and moving reset metadata cannot consume or repeat thresholds`() {
        let ledger = CodexWeeklyQuotaWarningLedger(defaults: InMemoryUserDefaults())
        #expect(self.observe(ledger, remaining: 60, step: 0) == nil)
        #expect(self.observe(ledger, remaining: 49, step: 2) == 50)
        #expect(self.observe(ledger, remaining: 19, step: 1) == nil)
        #expect(self.observe(ledger, remaining: 19, step: 2) == nil)
        #expect(self.observe(ledger, remaining: 51, step: 3, resetOffset: 3600) == nil)
        #expect(self.observe(ledger, remaining: 43, step: 4, resetOffset: nil) == nil)
        #expect(self.observe(ledger, remaining: 19, step: 5) == 20)
        #expect(self.observe(ledger, remaining: 49, step: 601, resetOffset: 605_400) == 50)
        #expect(self.observe(ledger, remaining: 48, step: 602, resetOffset: 605_400) == nil)
    }

    @Test
    func `bounded receipts retain the current owner and disabled thresholds stay disabled`() throws {
        let defaults = InMemoryUserDefaults()
        let ledger = CodexWeeklyQuotaWarningLedger(defaults: defaults)
        for index in 0...CodexWeeklyQuotaWarningLedger.maximumEntries {
            #expect(ledger.observe(
                owner: "synthetic-owner-\(index)",
                window: self.window(remaining: 60),
                observedAt: self.start.addingTimeInterval(Double(index)),
                thresholds: [50]) == nil)
        }
        let data = try #require(defaults.data(forKey: CodexWeeklyQuotaWarningLedger.defaultsKey))
        #expect(try Self.entries(data).count == CodexWeeklyQuotaWarningLedger.maximumEntries)
        let restored = CodexWeeklyQuotaWarningLedger(defaults: defaults)
        #expect(restored.observe(
            owner: "synthetic-owner-128",
            window: self.window(remaining: 49),
            observedAt: self.start.addingTimeInterval(129),
            thresholds: [50]) == 50)
        #expect(self.observe(restored, remaining: 60, step: 130, thresholds: [0]) == nil)
        #expect(self.observe(restored, remaining: 19, step: 131, thresholds: [0]) == nil)
    }

    private func observe(
        _ ledger: CodexWeeklyQuotaWarningLedger,
        remaining: Double,
        step: Int,
        resetOffset: TimeInterval? = 600,
        thresholds: [Int] = [50, 20]) -> Int?
    {
        ledger.observe(
            owner: self.owner,
            window: self.window(remaining: remaining, resetOffset: resetOffset),
            observedAt: self.start.addingTimeInterval(Double(step)),
            thresholds: thresholds)
    }

    private func window(remaining: Double, resetOffset: TimeInterval? = 600) -> RateWindow {
        RateWindow(
            usedPercent: 100 - remaining,
            windowMinutes: 10080,
            resetsAt: resetOffset.map { self.start.addingTimeInterval($0) },
            resetDescription: nil)
    }

    private static func entries(_ data: Data) throws -> [String: [String: Any]] {
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(payload["entries"] as? [String: [String: Any]])
    }
}
