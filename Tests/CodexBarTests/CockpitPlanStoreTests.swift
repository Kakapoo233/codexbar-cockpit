import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitPlanStoreTests {
    private func snapshot(account: String? = "synthetic-user", minutes: Int = 10080) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: minutes,
                resetsAt: Date().addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: Date(),
            identity: account.map {
                ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: nil,
                    accountOrganization: "synthetic-org",
                    loginMethod: nil,
                    accountID: $0)
            })
    }

    private func withStore(_ body: (CockpitPlanStore, URL) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("plan.json")
        try body(CockpitPlanStore(fileURL: url), url)
    }

    @Test func `plan persists and reloads without exposing account identifiers`() throws {
        try self.withStore { store, url in
            store.ingest([.codex: self.snapshot()])
            store.setPersonalCap(15, for: .codex)
            #expect(store.status(for: .codex).manualCapPercent == 15)
            let reloaded = CockpitPlanStore(fileURL: url)
            #expect(reloaded.state == store.state)
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("synthetic-user"))
            #expect(!text.contains("synthetic-org"))
        }
    }

    @Test func `switching accounts never borrows a personal cap`() throws {
        try self.withStore { store, _ in
            store.ingest([.codex: self.snapshot(account: "account-one")])
            store.setPersonalCap(15, for: .codex)
            store.ingest([.codex: self.snapshot(account: "account-two")])
            #expect(store.status(for: .codex).manualCapPercent == nil)
        }
    }

    @Test func `unknown identity and nonweekly quotas do not create plans`() throws {
        try self.withStore { store, _ in
            store.ingest([.codex: self.snapshot(account: nil)])
            #expect(store.state.snapshots.isEmpty)
            store.ingest([.codex: self.snapshot(minutes: 300)])
            #expect(store.state.snapshots.isEmpty)
            #expect(store.availableProviders.isEmpty)
        }
    }

    @Test func `a corrupt existing file is preserved after an update`() throws {
        try self.withStore { _, url in
            let original = Data("not a valid plan".utf8)
            try original.write(to: url)
            let store = CockpitPlanStore(fileURL: url)
            #expect(store.errorMessage != nil)
            store.ingest([.codex: self.snapshot()])
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test func `local comfort cannot become a quota account observation`() throws {
        try self.withStore { store, _ in
            store.ingest([.codex: self.snapshot(account: "account-one")])
            store.recordLocalComfort(.comfortable, for: .codex, totalTokens: 12345, coverage: .complete)
            store.ingest([.codex: self.snapshot(account: "account-two")])
            #expect(store.status(for: .codex).feeling == nil)
            let record = try #require(store.state.comfortRecords.first)
            #expect(record.accountID == "local-machine")
            #expect(record.totalTokens == 12345)
            #expect(record.coverage == .complete)
        }
    }

    @Test func `calendar feedback edits and clears only the selected provider day and zone`() throws {
        try self.withStore { store, url in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
            let day = try #require(ISO8601DateFormatter().date(from: "2026-10-30T03:30:00Z"))
            let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: day))
            var utc = calendar
            utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
            store.recordLocalComfort(.light, for: .codex, on: day, totalTokens: nil, calendar: calendar)
            store.recordLocalComfort(.comfortable, for: .codex, on: nextDay, totalTokens: nil, calendar: calendar)
            store.recordLocalComfort(.light, for: .claude, on: day, totalTokens: nil, calendar: calendar)
            store.recordLocalComfort(.comfortable, for: .codex, on: day, totalTokens: nil, calendar: utc)
            store.setLocalComfortFeeling(
                .overloaded,
                for: .codex,
                on: day,
                calendar: calendar)
            let records = store.state.comfortRecords
            #expect(records.count == 4)
            let selected = try #require(records.first {
                $0.providerID == "codex" && $0.localDateKey == "2026-10-29"
                    && $0.timeZoneIdentifier == calendar.timeZone.identifier
            })
            #expect(selected.feeling == .overloaded)
            #expect(selected.coverage == .partial)
            #expect(selected.accountID == "local-machine")
            #expect(CockpitPlanStore(fileURL: url).state == store.state)

            store.clearLocalComfort(for: .codex, on: day, calendar: calendar)
            #expect(store.state.comfortRecords == records.filter { $0.id != selected.id })
            #expect(CockpitPlanStore(fileURL: url).state == store.state)
            #expect(store.state.snapshots.isEmpty)
            #expect(store.state.plans.isEmpty)
        }
    }

    @Test func `editing a calendar feeling preserves its measured token sample`() throws {
        try self.withStore { store, url in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
            let observed = try #require(ISO8601DateFormatter().date(from: "2026-10-30T03:30:00Z"))
            store.recordLocalComfort(
                .comfortable,
                for: .codex,
                on: observed,
                totalTokens: 12345,
                coverage: .complete,
                calendar: calendar)
            store.setLocalComfortFeeling(
                .overloaded,
                for: .codex,
                on: calendar.startOfDay(for: observed),
                calendar: calendar)
            let record = try #require(store.state.comfortRecords.first)
            #expect(store.state.comfortRecords.count == 1)
            #expect(record.feeling == .overloaded)
            #expect(record.totalTokens == 12345)
            #expect(record.coverage == .complete)
            #expect(record.recordedAt == observed)
            #expect(CockpitPlanStore(fileURL: url).state == store.state)
        }
    }
}
