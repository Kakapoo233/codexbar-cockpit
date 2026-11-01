import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CockpitDriveSyncTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private var historicalDate: Date {
        Date(timeIntervalSince1970: 1_793_404_800)
    }

    private func snapshot(account: String = "synthetic-account", at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: date.addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: date,
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: "synthetic@example.test",
                accountOrganization: "synthetic-organization",
                loginMethod: nil,
                accountID: account))
    }

    private func withStores(_ body: (CockpitPlanStore, CockpitPlanStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = CockpitPlanStore(fileURL: directory.appendingPathComponent("source.json"))
        let destination = CockpitPlanStore(fileURL: directory.appendingPathComponent("destination.json"))
        try body(source, destination, directory)
    }

    @Test
    func `personal cap round trip retains account boundaries and local quota observations`() throws {
        try self.withStores { source, destination, directory in
            source.ingest([.codex: self.snapshot(account: "first-account")])
            source.setPersonalCap(18, for: .codex)
            source.recordComfort(.light, for: .codex, totalTokens: 12345)
            destination.ingest([.codex: self.snapshot(account: "second-account")])
            let observations = destination.state.snapshots
            let plans = destination.state.plans
            let summaries = destination.state.observedDaySummaries
            let values = try source.driveSyncValues()
            #expect(values.count == 2)
            let joined = values.values.compactMap { String(data: $0, encoding: .utf8) }.joined()
            #expect(!joined.contains("first-account"))
            #expect(!joined.contains("synthetic@example.test"))
            #expect(!joined.contains("synthetic-organization"))
            #expect(!joined.contains("12345"))
            try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            #expect(destination.status(for: .codex).manualCapPercent == nil)
            #expect(destination.state.snapshots == observations)
            #expect(destination.state.plans == plans)
            #expect(destination.state.observedDaySummaries == summaries)
            destination.ingest([.codex: self.snapshot(account: "first-account")])
            #expect(destination.status(for: .codex).manualCapPercent == 18)
            let reloaded = CockpitPlanStore(fileURL: directory.appendingPathComponent("destination.json"))
            #expect(reloaded.state == destination.state)
        }
    }

    @Test
    func `calendar feeling sync does not transfer or erase receiver local measurements`() throws {
        try self.withStores { source, destination, _ in
            source.recordLocalComfort(
                .overloaded,
                for: .codex,
                on: self.historicalDate,
                totalTokens: 9000,
                coverage: .complete,
                calendar: self.calendar)
            destination.recordLocalComfort(
                .light,
                for: .codex,
                on: self.historicalDate,
                totalTokens: 1200,
                coverage: .complete,
                calendar: self.calendar)
            let values = try source.driveSyncValues()
            let data = try #require(values.values.first)
            let exported = try JSONDecoder().decode(CockpitComfortRecord.self, from: data)
            #expect(exported.totalTokens == nil)
            #expect(exported.usedPercent == nil)
            #expect(exported.coverage == .unavailable)
            try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            let received = try #require(destination.state.comfortRecords.first)
            #expect(received.feeling == .overloaded)
            #expect(received.totalTokens == 1200)
            #expect(received.coverage == .complete)
            #expect(try destination.driveSyncValues() == values)
        }
    }

    @Test
    func `new device receives an unmeasured calendar rating`() throws {
        try self.withStores { source, destination, _ in
            source.recordLocalComfort(
                .comfortable,
                for: .claude,
                on: self.historicalDate,
                totalTokens: 100,
                coverage: .complete,
                calendar: self.calendar)
            let values = try source.driveSyncValues()
            try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            let received = try #require(destination.state.comfortRecords.first)
            #expect(received.feeling == .comfortable)
            #expect(received.totalTokens == nil)
            #expect(received.coverage == .unavailable)
        }
    }

    @Test
    func `account scoped quota feedback carries its captured quota measurement`() throws {
        try self.withStores { source, destination, directory in
            source.ingest([.codex: self.snapshot()])
            var state = source.state
            state.recordComfort(
                .comfortable,
                providerID: UsageProvider.codex.rawValue,
                accountID: source.accountID(for: .codex),
                totalTokens: nil,
                coverage: .partial,
                usedPercent: 12)
            let url = directory.appendingPathComponent("quota-feedback.json")
            try JSONEncoder().encode(state).write(to: url)
            let quotaStore = CockpitPlanStore(fileURL: url)
            let values = try quotaStore.driveSyncValues()
            try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            let received = try #require(destination.state.comfortRecords.first)
            #expect(received.accountID == source.accountID(for: .codex))
            #expect(received.usedPercent == 12)
            #expect(received.coverage == .partial)
            #expect(received.totalTokens == nil)
            #expect(destination.state.snapshots.isEmpty)
        }
    }

    @Test
    func `explicit tombstones remove only their managed record`() throws {
        try self.withStores { source, destination, _ in
            source.ingest([.codex: self.snapshot()])
            source.setPersonalCap(10, for: .codex)
            source.recordLocalComfort(
                .comfortable,
                for: .codex,
                on: self.historicalDate,
                totalTokens: nil,
                calendar: self.calendar)
            destination.recordLocalComfort(
                .light,
                for: .claude,
                on: self.historicalDate,
                totalTokens: 30,
                calendar: self.calendar)
            let values = try source.driveSyncValues()
            try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            try destination.applyDriveSyncValues([:], managedKeys: [])
            #expect(destination.state.personalCaps.count == 1)
            #expect(destination.state.comfortRecords.count == 2)
            try destination.applyDriveSyncValues([:], managedKeys: Set(values.keys))
            #expect(destination.state.personalCaps.isEmpty)
            #expect(destination.state.comfortRecords.count == 1)
            #expect(destination.state.comfortRecords.first?.providerID == UsageProvider.claude.rawValue)
        }
    }

    @Test
    func `invalid and identity mismatched data rejects the whole transaction`() throws {
        try self.withStores { source, destination, _ in
            source.ingest([.codex: self.snapshot()])
            source.setPersonalCap(10, for: .codex)
            source.recordLocalComfort(
                .light, for: .codex, on: self.historicalDate, totalTokens: nil, calendar: self.calendar)
            var values = try source.driveSyncValues()
            let key = try #require(values.keys.first { $0.hasPrefix("plan.comfort.") })
            let data = try #require(values[key])
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["accountID"] = "raw-account@example.test"
            values[key] = try JSONSerialization.data(withJSONObject: object)
            let before = destination.state
            #expect(throws: (any Error).self) {
                try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            }
            #expect(destination.state == before)
            let mismatched = ["plan.comfort.invalid": data]
            #expect(throws: (any Error).self) {
                try destination.applyDriveSyncValues(mismatched, managedKeys: Set(mismatched.keys))
            }
            #expect(destination.state == before)
        }
    }

    @Test
    func `local measurements in a remote payload are rejected`() throws {
        try self.withStores { source, destination, _ in
            source.recordLocalComfort(
                .comfortable,
                for: .codex,
                on: self.historicalDate,
                totalTokens: nil,
                calendar: self.calendar)
            var values = try source.driveSyncValues()
            let key = try #require(values.keys.first)
            let data = try #require(values[key])
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["totalTokens"] = 12345
            values[key] = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: (any Error).self) {
                try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            }
            #expect(destination.state.comfortRecords.isEmpty)
        }
    }

    @Test
    func `a corrupt local plan cannot export or receive sync records`() throws {
        try self.withStores { source, _, directory in
            source.recordLocalComfort(
                .light, for: .codex, on: self.historicalDate, totalTokens: nil, calendar: self.calendar)
            let values = try source.driveSyncValues()
            let url = directory.appendingPathComponent("corrupt.json")
            let original = Data("unreadable planning state".utf8)
            try original.write(to: url)
            let corrupt = CockpitPlanStore(fileURL: url)
            #expect(throws: (any Error).self) { try corrupt.driveSyncValues() }
            #expect(throws: (any Error).self) {
                try corrupt.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test
    func `failed persistence leaves observable state unchanged and reports failure`() throws {
        try self.withStores { source, _, directory in
            source.recordLocalComfort(
                .light, for: .codex, on: self.historicalDate, totalTokens: nil, calendar: self.calendar)
            let values = try source.driveSyncValues()
            let blockedParent = directory.appendingPathComponent("not-a-directory")
            try Data("synthetic blocker".utf8).write(to: blockedParent)
            let destination = CockpitPlanStore(fileURL: blockedParent.appendingPathComponent("plan.json"))
            let before = destination.state
            #expect(throws: (any Error).self) {
                try destination.applyDriveSyncValues(values, managedKeys: Set(values.keys))
            }
            #expect(destination.state == before)
            #expect(destination.errorMessage != nil)
        }
    }
}
