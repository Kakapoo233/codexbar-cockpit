import Foundation
import Testing
@testable import CodexBarCore

struct CockpitTeamAllocationTests {
    private var basis: CockpitTeamPlanBasis {
        CockpitTeamPlanBasis(
            localDate: "2026-09-15",
            anchorAt: "2026-09-14T16:00:00.000Z",
            remainingPercent: 80,
            resetsAt: "2026-09-18T16:00:00.000Z")
    }

    @Test(arguments: [(0.0, 20.0), (50.0, 35.0), (100.0, 80.0)])
    func `recommendation matches original v2 golden values`(risk: Double, expected: Double) {
        #expect(CockpitTeamAllocation.recommendation(basis: self.basis, riskPercent: risk) == expected)
    }

    @Test
    func `remaining day fraction and expired windows match upstream`() {
        var basis = self.basis
        basis.anchorAt = "2026-09-15T04:00:00.000Z"
        basis.resetsAt = "2026-09-19T04:00:00.000Z"
        #expect(CockpitTeamAllocation.recommendation(basis: basis, riskPercent: 0) == 10)
        basis.resetsAt = basis.anchorAt
        #expect(CockpitTeamAllocation.recommendation(basis: basis, riskPercent: 50) == 0)
    }

    @Test
    func `malformed basis and nonfinite values remain unavailable`() {
        var basis = self.basis
        basis.localDate = "2026-02-30"
        #expect(CockpitTeamAllocation.recommendation(basis: basis, riskPercent: 0) == nil)
        basis = self.basis
        basis.remainingPercent = .nan
        #expect(CockpitTeamAllocation.recommendation(basis: basis, riskPercent: 0) == nil)
        #expect(CockpitTeamAllocation.recommendation(basis: self.basis, riskPercent: .infinity) == nil)
    }

    @Test
    func `one person receives one share and an override leaves everyone else unchanged`() throws {
        let allocation = try #require(CockpitTeamAllocation.allocate(
            total: 20,
            people: ["alex", "alex", "blair"],
            overrides: ["alex": .init(value: 12, revision: 1)]))
        #expect(allocation.allocations == ["alex": 12, "blair": 10])
        #expect(allocation.total == 22)
        #expect(allocation.recommendedTotal == 20)
        let zero = try #require(CockpitTeamAllocation.allocate(
            total: 20,
            people: ["alex", "blair"],
            overrides: ["alex": .init(value: 0)]))
        #expect(zero.allocations == ["alex": 0, "blair": 10])
        let cleared = try #require(CockpitTeamAllocation.allocate(
            total: 20,
            people: ["alex", "blair"],
            overrides: ["alex": .init(value: nil, revision: 2)]))
        #expect(cleared.total == 20)
    }

    @Test
    func `a member owning two devices still receives a single plan allocation`() throws {
        let people = [
            CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["a", "b"]),
            CockpitTeamPerson(id: "blair", name: "Blair", deviceIDs: ["c"]),
        ]
        let allocation = try #require(CockpitTeamAllocation.allocate(
            plan: CockpitTeamDailyPlan(basis: self.basis),
            people: people))
        #expect(allocation.allocations == ["alex": 10, "blair": 10])
    }

    @Test
    func `invalid overrides fail closed while unrelated overrides cannot allocate quota`() throws {
        #expect(CockpitTeamAllocation.allocate(
            total: 10,
            people: ["alex"],
            overrides: ["alex": .init(value: -.infinity)]) == nil)
        let result = try #require(CockpitTeamAllocation.allocate(
            total: 10,
            people: ["alex"],
            overrides: ["unknown": .init(value: 100)]))
        #expect(result.allocations == ["alex": 10])
        #expect(CockpitTeamAllocation.allocate(total: 10, people: [])?.total == 0)
    }

    @Test
    func `cloud device contributions deduplicate and cost quota attribution stays estimated`() throws {
        let people = [
            CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["a", "b", "b"]),
            CockpitTeamPerson(id: "blair", name: "Blair", deviceIDs: ["c"]),
        ]
        let deviceA = Self.snapshot("a", cost: 2)
        let shares = CockpitTeamAllocation.estimatedCostShares(
            people: people,
            snapshots: [deviceA, deviceA, Self.snapshot("b", cost: 3), Self.snapshot("c", cost: 5)],
            localDate: "2026-09-15",
            observedUsedPercent: 40)
        let alex = try #require(shares.first { $0.personID == "alex" })
        #expect(alex.personCostUSD == 5)
        #expect(alex.totalCostUSD == 10)
        #expect(alex.costShare == 0.5)
        #expect(alex.allocatedUsedPercent == 20)
        #expect(alex.isEstimate)
        #expect(alex.coverage == .partial)
    }

    @Test
    func `missing cost or missing date cannot become a zero contribution`() throws {
        let people = [CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["a", "b"])]
        for snapshots in [[Self.snapshot("a", cost: 2)], [Self.snapshot("a", cost: 2), Self.snapshot("b", cost: nil)]] {
            let share = try #require(CockpitTeamAllocation.estimatedCostShares(
                people: people,
                snapshots: snapshots,
                localDate: "2026-09-15").first)
            #expect(share.personCostUSD == nil)
            #expect(share.totalCostUSD == nil)
            #expect(share.costShare == nil)
            #expect(share.missingDeviceIDs == ["b"])
        }
        let absentDay = try #require(CockpitTeamAllocation.estimatedCostShares(
            people: people,
            snapshots: [Self.snapshot("a", cost: 2)],
            localDate: "2026-09-16").first)
        #expect(absentDay.personCostUSD == nil)
    }

    @Test
    func `zero denominator cannot establish a quota share`() throws {
        let share = try #require(CockpitTeamAllocation.estimatedCostShares(
            people: [.init(id: "alex", name: "Alex", deviceIDs: ["a"])],
            snapshots: [Self.snapshot("a", cost: 0)],
            localDate: "2026-09-15",
            observedUsedPercent: 10).first)
        #expect(share.personCostUSD == 0)
        #expect(share.totalCostUSD == 0)
        #expect(share.costShare == nil)
        #expect(share.allocatedUsedPercent == nil)
    }

    @Test
    func `conflicting ownership and equal revision copies are not double counted`() throws {
        let people = [
            CockpitTeamPerson(id: "alex", name: "Alex", deviceIDs: ["a"]),
            CockpitTeamPerson(id: "blair", name: "Blair", deviceIDs: ["a"]),
        ]
        let ambiguous = CockpitTeamAllocation.estimatedCostShares(
            people: people,
            snapshots: [Self.snapshot("a", cost: 2)],
            localDate: "2026-09-15")
        #expect(ambiguous.allSatisfy { $0.costShare == nil && $0.coverage == .unavailable })
        let conflict = try #require(CockpitTeamAllocation.estimatedCostShares(
            people: [people[0]],
            snapshots: [Self.snapshot("a", cost: 2), Self.snapshot("a", cost: 3)],
            localDate: "2026-09-15").first)
        #expect(conflict.personCostUSD == nil)
    }

    private static func snapshot(_ device: String, cost: Double?) -> CockpitTeamDeviceSnapshot {
        CockpitTeamDeviceSnapshot(
            deviceID: device,
            displayName: "Synthetic Mac",
            updatedAt: 100,
            payload: CockpitTeamUsageSnapshot(
                deviceID: device,
                timestamp: 100,
                days: ["2026-09-15": .init(inputTokens: 100, outputTokens: 10, cost: cost)],
                metadata: .init(status: .ready)))
    }
}
