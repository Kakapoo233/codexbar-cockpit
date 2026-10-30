import Foundation

// Fixed-score smooth-knee comfort curve adapted from Codex Cockpit v0.3.4 (MIT).
// Copyright (c) 2026 Quota Float contributors. See the repository's third-party notices.

public struct CockpitQuotaComfortObservation: Equatable, Sendable, Identifiable {
    public let id: String
    public let localDateKey: String
    public let usedPercent: Double
    public let feeling: CockpitFeeling
    public let coverage: CockpitCoverage
    public let weight: Double

    public var score: Double {
        self.feeling.score
    }
}

public struct CockpitQuotaComfortPoint: Equatable, Sendable, Identifiable {
    public let usedPercent: Double
    public let score: Double
    public let baselineScore: Double

    public var id: Double {
        self.usedPercent
    }
}

/// Fits only the original curve's knee to fixed subjective scores. It does not change quota plans.
public struct CockpitQuotaComfortModel: Equatable, Sendable {
    public enum Status: String, Sendable {
        case baseline
        case fitted
    }

    public static let baselineKneePercent = 25.0
    public static let recencyHalfLifeDays = 14.0
    public static let maximumObservedPercent = 10000.0

    public let kneePercent: Double
    public let observations: [CockpitQuotaComfortObservation]
    public let points: [CockpitQuotaComfortPoint]
    public let effectiveSampleCount: Double
    /// The upstream fit's heuristic concentration, not a statistical confidence interval.
    public let confidence: Double
    public let status: Status
    public let axisMaxPercent: Double
    public let axisTicks: [Double]

    public var sampleCount: Int {
        self.observations.count
    }

    public var maximumUsedPercent: Double {
        self.axisMaxPercent
    }

    public func score(atUsedPercent usedPercent: Double) -> Double {
        Self.score(atUsedPercent: usedPercent, kneePercent: self.kneePercent)
    }

    /// Original normalized fatigue family, including the 20% floor after 100% cumulative use.
    public static func score(
        atUsedPercent usedPercent: Double,
        kneePercent: Double = CockpitQuotaComfortModel.baselineKneePercent) -> Double
    {
        guard usedPercent.isFinite, usedPercent >= 0, kneePercent.isFinite else { return 0 }
        let knee = min(100, max(0.1, kneePercent)) / 100
        let tau = 0.02
        func shoulder(_ input: Double) -> Double {
            let value = (input - knee) / tau
            return tau * (value > 30 ? value : log1p(exp(value)))
        }
        func response(_ input: Double) -> Double { exp(-4.3 * pow(input, 1.5)) }
        let low = response(shoulder(0))
        let high = response(shoulder(1))
        guard abs(low - high) >= 1e-12 else { return 0.2 }
        let result = 0.2 + 0.8 * (response(shoulder(usedPercent / 100)) - high) / (low - high)
        return min(1, max(0.2, result))
    }

    public static func build(
        records: [CockpitComfortRecord],
        providerID: String,
        accountID: String,
        now: Date = Date(),
        calendar: Calendar = .current) -> Self
    {
        let observations = Self.observations(
            records: records, providerID: providerID, accountID: accountID, now: now, calendar: calendar)
        let fit = Self.fit(observations)
        let required = max(125, (observations.map(\.usedPercent).max() ?? 0) * 1.1)
        let step = [25.0, 50, 100, 250, 500, 1000, 2500, 5000].first { required / $0 <= 6 } ?? 5000
        let axisMax = ceil(required / step) * step
        return Self(
            kneePercent: fit.knee,
            observations: observations,
            points: (0...200).map { index in
                let used = Double(index) / 200 * axisMax
                return CockpitQuotaComfortPoint(
                    usedPercent: used,
                    score: Self.score(atUsedPercent: used, kneePercent: fit.knee),
                    baselineScore: Self.score(atUsedPercent: used))
            },
            effectiveSampleCount: observations.reduce(0) { $0 + $1.weight },
            confidence: fit.confidence,
            status: observations.isEmpty ? .baseline : .fitted,
            axisMaxPercent: axisMax,
            axisTicks: (0...Int((axisMax / step).rounded())).map { Double($0) * step })
    }

    private static func observations(
        records: [CockpitComfortRecord],
        providerID: String,
        accountID: String,
        now: Date,
        calendar: Calendar) -> [CockpitQuotaComfortObservation]
    {
        guard !providerID.isEmpty, !accountID.isEmpty,
              accountID != "unidentified", accountID != "local-machine",
              now.timeIntervalSince1970.isFinite else { return [] }
        var unique: [String: CockpitComfortRecord] = [:]
        for record in records where record.providerID == providerID && record.accountID == accountID {
            guard record.timeZoneIdentifier == calendar.timeZone.identifier,
                  record.recordedAt.timeIntervalSince1970.isFinite else { continue }
            // Deduplicate before filtering the measurement so a cleared newer sample cannot revive an older one.
            if let prior = unique[record.localDateKey], prior.recordedAt >= record.recordedAt { continue }
            unique[record.localDateKey] = record
        }
        return unique.values.sorted {
            $0.localDateKey < $1.localDateKey
        }.suffix(90).compactMap { record in
            guard let used = record.usedPercent, used.isFinite, (0...Self.maximumObservedPercent).contains(used),
                  record.coverage != .unavailable,
                  let date = Self.date(for: record.localDateKey, calendar: calendar),
                  let age = calendar.dateComponents([.day], from: date, to: calendar.startOfDay(for: now)).day,
                  age >= 0 else { return nil }
            let weight = (record.coverage == .complete ? 1.0 : 0.75) * pow(2, -Double(age) / Self.recencyHalfLifeDays)
            guard weight > 0 else { return nil }
            return CockpitQuotaComfortObservation(
                id: record.id,
                localDateKey: record.localDateKey,
                usedPercent: used,
                feeling: record.feeling,
                coverage: record.coverage,
                weight: weight)
        }
    }

    private static func date(for key: String, calendar: Calendar) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, values.count == 3,
              let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])),
              CockpitCalendar.dateKey(for: date, calendar: calendar) == key else { return nil }
        return date
    }

    private static func fit(_ observations: [CockpitQuotaComfortObservation]) -> (knee: Double, confidence: Double) {
        guard !observations.isEmpty else { return (self.baselineKneePercent, 0) }
        var profile: [(knee: Double, score: Double)] = []
        var bestScore = -Double.infinity
        var knee = Self.baselineKneePercent
        for index in 1...1000 {
            let candidate = Double(index) / 10
            let error = observations.reduce(0) { sum, observation in
                let residual = Self.score(atUsedPercent: observation.usedPercent, kneePercent: candidate)
                    - observation.score
                return sum + observation.weight * residual * residual
            }
            let score = -error / (2 * 0.15 * 0.15)
            profile.append((candidate, score))
            if score > bestScore + 1e-10
                || (abs(score - bestScore) <= 1e-10
                    && abs(candidate - Self.baselineKneePercent) < abs(knee - Self.baselineKneePercent))
            {
                bestScore = score
                knee = candidate
            }
        }
        let totalWeight = profile.reduce(0) { $0 + exp($1.score - bestScore) }
        let mean = profile.reduce(0) { $0 + $1.knee * exp($1.score - bestScore) } / totalWeight
        let variance = profile.reduce(0) { $0 + pow($1.knee - mean, 2) * exp($1.score - bestScore) } / totalWeight
        let sampleWeight = observations.reduce(0) { $0 + $1.weight }
        let confidence = min(0.75, sampleWeight / 5 * 0.75) * min(1, max(0.2, 1 - sqrt(variance) / 24))
        return (knee, (confidence * 1000).rounded() / 1000)
    }
}
