import Foundation

// Token experience chart adapted from Codex Cockpit v0.3.4 (MIT).
// Copyright (c) 2026 Quota Float contributors. See the repository's third-party notices.

public struct CockpitComfortObservation: Equatable, Sendable, Identifiable {
    public let id: String
    public let localDateKey: String
    public let totalTokens: Int
    public let feeling: CockpitFeeling
    public let coverage: CockpitCoverage

    public var score: Double {
        self.feeling.score
    }
}

public struct CockpitComfortPoint: Equatable, Sendable, Identifiable {
    public let totalTokens: Double
    public let score: Double
    public let sampleCount: Int

    public var id: Double {
        self.totalTokens
    }
}

/// Describes the user's recorded experience. It does not predict productivity or set official quota budgets.
public struct CockpitComfortModel: Equatable, Sendable {
    public enum Status: String, Sendable {
        case insufficientData
        case ready
    }

    public let observations: [CockpitComfortObservation]
    public let points: [CockpitComfortPoint]
    public let completeSampleCount: Int
    public let status: Status

    public static func build(
        records: [CockpitComfortRecord],
        providerID: String,
        accountID: String = "default",
        now: Date = Date(),
        calendar: Calendar = .current) -> Self
    {
        let today = CockpitCalendar.dateKey(for: now, calendar: calendar)
        var unique: [String: CockpitComfortRecord] = [:]
        for record in records where record.providerID == providerID && record.accountID == accountID {
            guard record.timeZoneIdentifier == calendar.timeZone.identifier,
                  Self.validDateKey(record.localDateKey, calendar: calendar),
                  record.localDateKey <= today,
                  let tokens = record.totalTokens, tokens >= 0,
                  record.coverage != .unavailable else { continue }
            if let prior = unique[record.id], prior.recordedAt >= record.recordedAt { continue }
            unique[record.id] = record
        }
        let observations = unique.values.sorted { $0.localDateKey < $1.localDateKey }.suffix(90).compactMap {
            guard let tokens = $0.totalTokens else { return nil as CockpitComfortObservation? }
            return CockpitComfortObservation(
                id: $0.id,
                localDateKey: $0.localDateKey,
                totalTokens: tokens,
                feeling: $0.feeling,
                coverage: $0.coverage)
        }
        let complete = observations.filter { $0.coverage == .complete }
        let distinct = Set(complete.map(\.totalTokens))
        let spread = (distinct.max() ?? 0) - (distinct.min() ?? 0)
        let ready = complete.count >= 7 && distinct.count >= 3 && spread >= 100_000
        return Self(
            observations: observations,
            points: ready ? Self.binnedPoints(complete) : [],
            completeSampleCount: complete.count,
            status: ready ? .ready : .insufficientData)
    }

    private static func binnedPoints(_ observations: [CockpitComfortObservation]) -> [CockpitComfortPoint] {
        let groups = Dictionary(grouping: observations, by: \.totalTokens)
        let tokens = groups.keys.sorted()
        let bins = min(5, tokens.count, max(3, Int(Double(observations.count).squareRoot())))
        return (0..<bins).compactMap { index in
            let start = index * tokens.count / bins
            let end = (index + 1) * tokens.count / bins
            let members = tokens[start..<end].flatMap { groups[$0] ?? [] }
            guard !members.isEmpty else { return nil }
            return CockpitComfortPoint(
                totalTokens: members.reduce(0) { $0 + Double($1.totalTokens) } / Double(members.count),
                score: members.reduce(0) { $0 + $1.score } / Double(members.count),
                sampleCount: members.count)
        }
    }

    private static func validDateKey(_ key: String, calendar: Calendar) -> Bool {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, values.count == 3 else { return false }
        var parts = DateComponents()
        parts.year = values[0]
        parts.month = values[1]
        parts.day = values[2]
        parts.hour = 12
        guard let date = calendar.date(from: parts) else { return false }
        return CockpitCalendar.dateKey(for: date, calendar: calendar) == key
    }
}
