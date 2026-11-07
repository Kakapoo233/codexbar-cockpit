import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitCalendarQuotaFeedbackTests {
    @Test
    func `date actions edit and clear only their own day while preserving captured quota`() throws {
        try Self.withStore { store, url in
            let now = Self.now
            let yesterday = now.addingTimeInterval(-86400)
            store.ingest([.codex: Self.snapshot(at: now.addingTimeInterval(-600), used: 20)])
            store.ingest([.codex: Self.snapshot(at: now, used: 35)])
            let feedback = Self.feedback(store)
            feedback.update(.light, on: yesterday, now: now)
            feedback.update(.comfortable, on: now, now: now)
            let captured = try #require(Self.record(store, on: now))
            #expect(captured.feeling == .comfortable)
            #expect(captured.usedPercent == 15)
            #expect(captured.coverage == .partial)
            #expect(captured.totalTokens == nil)
            #expect(Self.record(store, on: yesterday)?.feeling == .light)

            let later = now.addingTimeInterval(60)
            store.ingest([.codex: Self.snapshot(at: later, used: 60)])
            feedback.update(.overloaded, on: now, now: later)
            let edited = try #require(Self.record(store, on: now))
            #expect(edited.feeling == .overloaded)
            #expect(edited.usedPercent == captured.usedPercent)
            #expect(edited.coverage == captured.coverage)

            feedback.update(nil, on: yesterday, now: later)
            #expect(Self.record(store, on: yesterday) == nil)
            #expect(Self.record(store, on: now) == edited)
            #expect(CockpitPlanStore(fileURL: url).state.comfortRecords == [edited])
        }
    }

    @Test
    func `actions cannot edit a future day or a provider without an identified account`() throws {
        try Self.withStore { store, _ in
            let now = Self.now
            let beforeIdentification = Self.feedback(store)
            #expect(!beforeIdentification.canRecord(on: now, now: now))
            beforeIdentification.update(.light, on: now, now: now)
            #expect(store.state.comfortRecords.isEmpty)

            store.ingest([.codex: Self.snapshot(at: now, used: 20)])
            let feedback = Self.feedback(store)
            let tomorrow = now.addingTimeInterval(86400)
            #expect(feedback.canRecord(on: now, now: now))
            #expect(!feedback.canRecord(on: tomorrow, now: now))
            feedback.update(.light, on: tomorrow, now: now)
            beforeIdentification.update(.overloaded, on: now, now: now)
            #expect(store.state.comfortRecords.isEmpty)

            feedback.update(.comfortable, on: now, now: now)
            let records = store.state.comfortRecords
            store.ingest([:])
            #expect(!feedback.canRecord(on: now, now: now))
            feedback.update(nil, on: now, now: now)
            #expect(store.state.comfortRecords == records)
        }
    }

    @Test
    func `actions captured for one account cannot change another account after switching`() throws {
        try Self.withStore { store, _ in
            let now = Self.now
            store.ingest([.codex: Self.snapshot(at: now, used: 20)])
            let old = Self.feedback(store)
            old.update(.light, on: now, now: now)
            store.ingest([.codex: Self.snapshot(at: now, used: 50, account: "synthetic-second")])
            Self.feedback(store).update(.comfortable, on: now, now: now)

            let records = store.state.comfortRecords
            #expect(records.count == 2)
            #expect(!old.canRecord(on: now, now: now))
            old.update(.overloaded, on: now, now: now)
            old.update(nil, on: now, now: now)
            #expect(store.state.comfortRecords == records)
            #expect(Self.record(store, on: now)?.feeling == .comfortable)
        }
    }

    private static let now = Date(timeIntervalSince1970: 1_793_361_600)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func feedback(_ store: CockpitPlanStore) -> CockpitCalendarQuotaFeedback {
        CockpitCalendarQuotaFeedback(store: store, provider: .codex, calendar: self.calendar)
    }

    private static func record(_ store: CockpitPlanStore, on day: Date) -> CockpitComfortRecord? {
        CockpitCalendarProjection.record(
            on: day,
            providerID: UsageProvider.codex.rawValue,
            accountID: store.accountID(for: .codex),
            records: store.state.comfortRecords,
            calendar: self.calendar)
    }

    private static func snapshot(at date: Date, used: Double, account: String = "synthetic-first") -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: used,
                windowMinutes: 10080,
                resetsAt: self.now.addingTimeInterval(4 * 86400),
                resetDescription: nil),
            updatedAt: date,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil,
                accountID: account))
    }

    private static func withStore(_ body: (CockpitPlanStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("plan.json")
        try body(CockpitPlanStore(fileURL: url), url)
    }
}
