import Foundation

/// Read-only view of the team's recorded Codex ledger. Budget and official quota are separate.
public struct CockpitTeamUsageDistribution: Sendable {
    public struct Device: Identifiable, Sendable {
        public let id: String
        public let updatedAt: Date?
        public let tokens: Int64?
        public let estimatedCostUSD: Double?
        public let coverage: CockpitCoverage
    }

    public struct Totals: Sendable {
        public let deviceCount: Int
        public let reportingDeviceCount: Int
        public let tokens: Int64?
        public let estimatedCostUSD: Double?
        public let tokenCoverage: CockpitCoverage
        public let costCoverage: CockpitCoverage
    }

    public struct Row: Identifiable, Sendable {
        public let person: CockpitTeamPerson?
        public let devices: [Device]
        public let totals: Totals
        public let tokenShare: Double?

        public var id: String? {
            self.person?.id
        }
    }

    public let totals: Totals
    public let rows: [Row]

    /// `localDate` is the explicit UTC+8 ledger day. Never derive it from a rolling range.
    public static func build(
        people: [CockpitTeamPerson],
        activeDeviceIDs: Set<String>,
        snapshots: [CockpitTeamDeviceSnapshot],
        localDate: String) -> Self
    {
        let latest = CockpitTeamDeviceSnapshot.latestPerDevice(snapshots)
        let date = CockpitTeamValidation.day(localDate) ? localDate : nil
        let devices = activeDeviceIDs.sorted().map { id in
            self.device(id: id, snapshot: latest[id], localDate: date)
        }
        let totals = self.totals(for: devices)
        var owners: [String: Set<String>] = [:]
        for person in people {
            for id in person.deviceIDs {
                owners[id, default: []].insert(person.id)
            }
        }
        let assignments = Dictionary(grouping: devices) { device -> String? in
            guard let matches = owners[device.id], matches.count == 1 else { return nil }
            return matches.first
        }
        var rows = people.map { person in
            self.row(person: person, devices: assignments[person.id] ?? [], teamTokens: totals.tokens)
        }
        if let unassigned = assignments[nil] {
            rows.append(self.row(person: nil, devices: unassigned, teamTokens: totals.tokens))
        }
        return Self(totals: totals, rows: rows)
    }

    private static func row(person: CockpitTeamPerson?, devices: [Device], teamTokens: Int64?) -> Row {
        let totals = self.totals(for: devices)
        let share: Double? = if let tokens = totals.tokens, let teamTokens, teamTokens > 0 {
            Double(tokens) / Double(teamTokens)
        } else {
            nil
        }
        return Row(person: person, devices: devices, totals: totals, tokenShare: share)
    }

    private static func device(id: String, snapshot: CockpitTeamDeviceSnapshot?, localDate: String?) -> Device {
        let updatedAt = snapshot.map { Date(timeIntervalSince1970: $0.updatedAt) }
        guard let payload = snapshot?.payload, let localDate, let day = payload.days[localDate],
              payload.metadata?.status != .unavailable,
              payload.metadata?.nativeDays?.contains(localDate) != false,
              let tokens = self.sumTokens([day.inputTokens, day.outputTokens])
        else { return Device(id: id, updatedAt: updatedAt, tokens: nil, estimatedCostUSD: nil, coverage: .unavailable) }

        // The daily input count already includes cached input; reasoning is a subset of output.
        let cost = day.cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        return Device(
            id: id,
            updatedAt: updatedAt,
            tokens: tokens,
            estimatedCostUSD: cost,
            coverage: payload.metadata?.status == .ready ? .complete : .partial)
    }

    private static func totals(for devices: [Device]) -> Totals {
        let tokenValues = devices.compactMap(\.tokens)
        let costValues = devices.compactMap(\.estimatedCostUSD)
        let tokens = self.sumTokens(tokenValues)
        let costSum = costValues.reduce(0, +)
        let cost = costValues.isEmpty || !costSum.isFinite ? nil : costSum
        let allComplete = devices.allSatisfy { $0.coverage == .complete }
        return Totals(
            deviceCount: devices.count,
            reportingDeviceCount: tokenValues.count,
            tokens: tokens,
            estimatedCostUSD: cost,
            tokenCoverage: self.coverage(hasValue: tokens != nil, isComplete: allComplete),
            costCoverage: self.coverage(
                hasValue: cost != nil,
                isComplete: allComplete && costValues.count == devices.count))
    }

    private static func coverage(hasValue: Bool, isComplete: Bool) -> CockpitCoverage {
        guard hasValue else { return .unavailable }
        return isComplete ? .complete : .partial
    }

    private static func sumTokens(_ values: [Int64]) -> Int64? {
        guard !values.isEmpty else { return nil }
        var total: Int64 = 0
        for value in values {
            let (sum, overflow) = total.addingReportingOverflow(value)
            guard value >= 0, !overflow else { return nil }
            total = sum
        }
        return total
    }
}
