import Testing
@testable import CodexBarCore

struct CockpitTeamUsageDistributionTests {
    private static let day = "2026-10-30"

    @Test
    func `active device ledger rows aggregate under members and include the unassigned share`() throws {
        let people = [
            CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["a", "b", "revoked"]),
            CockpitTeamPerson(id: "blair", name: "Blair", deviceIDs: ["pending"]),
            CockpitTeamPerson(id: "charlie", name: "Charlie"),
        ]
        let latest = Self.snapshot(
            "a",
            usage: .init(inputTokens: 60, cachedInputTokens: 40, outputTokens: 20, reasoningTokens: 10, cost: 2),
            timestamp: 120)
        let usage = CockpitTeamUsageDistribution.build(
            people: people,
            activeDeviceIDs: ["a", "b", "pending", "unassigned"],
            snapshots: [
                latest,
                latest,
                Self.snapshot("a", usage: .init(inputTokens: 800, outputTokens: 0, cost: 10)),
                Self.snapshot("b", usage: .init(inputTokens: 40, outputTokens: 0), metadata: .init(status: .partial)),
                Self.snapshot("unassigned", usage: .init(inputTokens: 120, outputTokens: 0, cost: 0)),
                Self.snapshot("revoked", usage: .init(inputTokens: 800, outputTokens: 0, cost: 10)),
            ],
            localDate: Self.day)
        #expect(usage.totals.tokens == 240)
        #expect(usage.totals.deviceCount == 4)
        #expect(usage.totals.reportingDeviceCount == 3)
        #expect(usage.totals.tokenCoverage == .partial)
        #expect(usage.totals.estimatedCostUSD == 2)
        #expect(usage.totals.costCoverage == .partial)
        let alex = try #require(usage.rows.first { $0.id == "alex" })
        #expect(alex.devices.map(\.id) == ["a", "b"])
        #expect(alex.totals.tokens == 120)
        #expect(alex.totals.estimatedCostUSD == 2)
        #expect(alex.tokenShare == 0.5)
        let blair = try #require(usage.rows.first { $0.id == "blair" })
        #expect(blair.totals.reportingDeviceCount == 0)
        #expect(blair.totals.deviceCount == 1)
        #expect(blair.totals.tokens == nil)
        #expect(blair.tokenShare == nil)
        let charlie = try #require(usage.rows.first { $0.id == "charlie" })
        #expect(charlie.totals.deviceCount == 0)
        #expect(charlie.totals.tokens == nil)
        let unassigned = try #require(usage.rows.first { $0.id == nil })
        #expect(unassigned.tokenShare == 0.5)
        #expect(unassigned.totals.estimatedCostUSD == 0)
    }

    @Test
    func `today uses its exact dated ledger with qualified status and keeps measured zero`() throws {
        let zero = CockpitTeamLedgerDay(inputTokens: 0, outputTokens: 0, cost: 0)
        let positive = CockpitTeamLedgerDay(inputTokens: 40, outputTokens: 10, cost: 1)
        let usage = CockpitTeamUsageDistribution.build(
            people: [],
            activeDeviceIDs: ["zero", "yesterday", "unavailable", "retained", "legacy"],
            snapshots: [
                Self.snapshot("zero", usage: zero),
                Self.snapshot("yesterday", usage: positive, day: "2026-10-29"),
                Self.snapshot("unavailable", usage: positive, metadata: .init(status: .unavailable)),
                Self.snapshot("retained", usage: positive, metadata: .init(status: .ready, nativeDays: ["2026-10-29"])),
                Self.snapshot("legacy", usage: zero, metadata: nil),
            ],
            localDate: Self.day)
        let devices = try #require(usage.rows.first?.devices)
        #expect(devices.filter { $0.tokens != nil }.map(\.id) == ["legacy", "zero"])
        #expect(devices.first { $0.id == "legacy" }?.coverage == .partial)
        #expect(usage.totals.tokens == 0)
        #expect(usage.totals.reportingDeviceCount == 2)
        #expect(usage.totals.estimatedCostUSD == 0)
        #expect(usage.rows.first?.tokenShare == nil)
    }

    @Test
    func `conflicting same revision snapshots are unavailable and ambiguous ownership is counted once`() throws {
        let people = [
            CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["ambiguous", "conflict"]),
            CockpitTeamPerson(id: "blair", name: "Blair", deviceIDs: ["ambiguous"]),
        ]
        let usage = CockpitTeamUsageDistribution.build(
            people: people,
            activeDeviceIDs: ["ambiguous", "conflict"],
            snapshots: [
                Self.snapshot("ambiguous", usage: .init(inputTokens: 40, outputTokens: 10)),
                Self.snapshot("conflict", usage: .init(inputTokens: 40, outputTokens: 10)),
                Self.snapshot("conflict", usage: .init(inputTokens: 80, outputTokens: 10)),
            ],
            localDate: Self.day)
        #expect(usage.totals.tokens == 50)
        #expect(usage.totals.reportingDeviceCount == 1)
        #expect(usage.totals.estimatedCostUSD == nil)
        #expect(usage.totals.costCoverage == .unavailable)
        let unassigned = try #require(usage.rows.first { $0.id == nil })
        #expect(unassigned.devices.map(\.id) == ["ambiguous"])
        #expect(unassigned.tokenShare == 1)
        #expect(usage.rows.first { $0.id == "alex" }?.totals.tokens == nil)
        #expect(usage.rows.first { $0.id == "blair" }?.totals.tokens == nil)
    }

    private static func snapshot(
        _ id: String,
        usage: CockpitTeamLedgerDay,
        timestamp: Int64 = 100,
        day: String = Self.day,
        metadata: CockpitTeamSnapshotMetadata? = .init(status: .ready)) -> CockpitTeamDeviceSnapshot
    {
        CockpitTeamDeviceSnapshot(
            deviceID: id,
            displayName: id,
            updatedAt: Double(timestamp),
            payload: CockpitTeamUsageSnapshot(
                deviceID: id,
                timestamp: timestamp,
                days: [day: usage],
                metadata: metadata))
    }
}
