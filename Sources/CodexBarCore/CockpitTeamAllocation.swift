import Foundation

/// The v2 plan describes one shared quota pool. Local frozen plans remain independent.
public enum CockpitTeamAllocation {
    public struct Result: Equatable, Sendable {
        public let recommendedTotal: Double
        public let allocations: [String: Double]
        /// Overrides are independent: this can exceed `recommendedTotal` without changing other people.
        public let total: Double
    }

    public struct EstimatedCostShare: Equatable, Sendable, Identifiable {
        public let personID: String
        public let personCostUSD: Double?
        public let totalCostUSD: Double?
        public let costShare: Double?
        public let allocatedUsedPercent: Double?
        public let missingDeviceIDs: [String]
        public let coverage: CockpitCoverage
        public var id: String {
            self.personID
        }

        /// Cost ratios do not establish which person consumed official quota.
        public var isEstimate: Bool {
            true
        }
    }

    /// Matches `sharedDailyPlan.ts` for valid v2 inputs, including its one-decimal rounding.
    /// Invalid input is unavailable; an expired, valid quota window recommends zero.
    public static func recommendation(basis: CockpitTeamPlanBasis, riskPercent: Double) -> Double? {
        guard basis.remainingPercent.isFinite, riskPercent.isFinite,
              let anchor = self.timestamp(basis.anchorAt), let reset = self.timestamp(basis.resetsAt),
              let start = self.day(basis.localDate)
        else { return nil }
        let duration = 86400.0
        let days = reset.timeIntervalSince(anchor) / duration
        guard days > 0 else { return 0 }
        let remaining = min(100, max(0, basis.remainingPercent))
        let fraction = min(1, max(0, start.addingTimeInterval(duration).timeIntervalSince(anchor) / duration))
        let uniform = min(remaining, remaining / days * fraction)
        let risk = min(100, max(0, riskPercent)) / 100
        let amount = min(remaining, uniform + (remaining - uniform) * risk * risk * fraction)
        return (amount * 10).rounded(.toNearestOrAwayFromZero) / 10
    }

    public static func allocate(
        total: Double,
        people: [String],
        overrides: [String: CockpitTeamPlanField] = [:]) -> Result?
    {
        guard total.isFinite, total >= 0, people.allSatisfy({ !$0.isEmpty }) else { return nil }
        let ids = Set(people)
        let share = ids.isEmpty ? 0 : total / Double(ids.count)
        var allocations: [String: Double] = [:]
        for id in ids {
            let value = overrides[id]?.value ?? share
            guard value.isFinite, value >= 0 else { return nil }
            allocations[id] = value
        }
        let allocated = allocations.values.reduce(0, +)
        guard allocated.isFinite else { return nil }
        return Result(recommendedTotal: total, allocations: allocations, total: allocated)
    }

    public static func allocate(plan: CockpitTeamDailyPlan, people: [CockpitTeamPerson]) -> Result? {
        guard let total = self.recommendation(basis: plan.basis, riskPercent: plan.risk.value ?? 0) else { return nil }
        return self.allocate(total: total, people: people.map(\.id), overrides: plan.people)
    }

    /// Consumes cloud snapshots only. Callers must not append this Mac's local ledger to its cloud copy.
    /// Even a fully observed cost ratio remains an estimate, with at most partial quota attribution.
    public static func estimatedCostShares(
        people: [CockpitTeamPerson],
        snapshots: [CockpitTeamDeviceSnapshot],
        localDate: String,
        observedUsedPercent: Double? = nil) -> [EstimatedCostShare]
    {
        let peopleByID = Dictionary(grouping: people, by: \.id)
        let devicesByPerson = peopleByID.mapValues { Set($0.flatMap(\.deviceIDs)) }
        let requestedDevices = Set(devicesByPerson.values.flatMap(\.self))
        let allDevices = requestedDevices.union(snapshots.map(\.deviceID))
        let observations = self.deviceCosts(snapshots: snapshots, localDate: localDate)
        let ambiguousDevices = Set(requestedDevices.filter { deviceID in
            devicesByPerson.values.count(where: { $0.contains(deviceID) }) > 1
        })
        let unavailable = allDevices.filter { observations[$0] == nil || ambiguousDevices.contains($0) }
        let totalCost = unavailable.isEmpty && !allDevices.isEmpty
            ? self.finiteSum(allDevices.compactMap { observations[$0] }) : nil
        let quota = observedUsedPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        return peopleByID.keys.sorted().map { personID in
            let devices = devicesByPerson[personID] ?? []
            let missing = devices.intersection(unavailable).sorted()
            let personCost = missing.isEmpty && !devices.isEmpty
                ? self.finiteSum(devices.compactMap { observations[$0] }) : nil
            let share: Double? = if let personCost, let totalCost, totalCost > 0 {
                personCost / totalCost
            } else {
                nil
            }
            return EstimatedCostShare(
                personID: personID,
                personCostUSD: personCost,
                totalCostUSD: totalCost,
                costShare: share,
                allocatedUsedPercent: share.flatMap { fraction in quota.map { $0 * fraction } },
                missingDeviceIDs: missing,
                coverage: share == nil ? .unavailable : .partial)
        }
    }

    private static func deviceCosts(
        snapshots: [CockpitTeamDeviceSnapshot],
        localDate: String) -> [String: Double]
    {
        guard self.day(localDate) != nil else { return [:] }
        var result: [String: Double] = [:]
        for (deviceID, copies) in Dictionary(grouping: snapshots, by: \.deviceID) {
            let valid = copies.filter {
                $0.payload.deviceID == deviceID && $0.updatedAt.isFinite && $0.updatedAt >= 0
            }
            guard let latest = valid.max(by: {
                ($0.updatedAt, $0.payload.timestamp) < ($1.updatedAt, $1.payload.timestamp)
            }),
                latest.payload.metadata?.status != .unavailable,
                let cost = latest.payload.days[localDate]?.cost, cost.isFinite, cost >= 0,
                !valid.contains(where: {
                    $0.updatedAt == latest.updatedAt && $0.payload.timestamp == latest.payload.timestamp
                        && $0.payload != latest.payload
                })
            else { continue }
            result[deviceID] = cost
        }
        return result
    }

    private static func finiteSum(_ values: [Double]) -> Double? {
        let sum = values.reduce(0, +)
        return sum.isFinite ? sum : nil
    }

    private static func timestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func day(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let date = self.timestamp(value + "T00:00:00+08:00")
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
        return CockpitCalendar.dateKey(for: date, calendar: calendar) == value ? date : nil
    }
}
