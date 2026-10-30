import Foundation

enum CockpitTeamValidation {
    static func safeID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$", options: .regularExpression) != nil
            && value != "." && value != ".." && !value.hasSuffix(".")
    }

    static func safeName(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 64
            && !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
    }

    static func modelID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9~][A-Za-z0-9/~_.:+-]{0,255}$", options: .regularExpression) != nil
    }

    static func percent(_ value: Double?) -> Bool {
        value.map { $0.isFinite && (0...100).contains($0) } ?? true
    }

    static func planBasis(_ basis: CockpitTeamPlanBasis) throws {
        guard self.day(basis.localDate), self.percent(basis.remainingPercent),
              self.timestamp(basis.anchorAt), self.timestamp(basis.resetsAt)
        else {
            throw CockpitTeamError.invalidRequest
        }
    }

    static func plan(_ plan: CockpitTeamDailyPlan) throws {
        try self.planBasis(plan.basis)
        guard plan.people.count <= 32, plan.risk.revision >= 0, self.percent(plan.risk.value),
              plan.people.allSatisfy({ self.safeID($0.key) && $0.value.revision >= 0
                      && self.percent($0.value.value) }) else { throw CockpitTeamError.invalidResponse }
    }

    static func snapshot(_ snapshot: CockpitTeamUsageSnapshot) throws {
        guard self.safeID(snapshot.deviceID), snapshot.timestamp > 0,
              Double(snapshot.timestamp) <= Date().timeIntervalSince1970 + 300,
              Set(snapshot.codex.ranges.keys).isSubset(of: ["today", "yesterday", "week", "month", "all"]),
              snapshot.ledger.v == nil || snapshot.ledger.v == 1, snapshot.days.count <= 4096
        else {
            throw CockpitTeamError.invalidRequest
        }
        for range in snapshot.codex.ranges.values {
            guard self.metrics(
                input: range.inputTokens,
                cached: range.cachedInputTokens,
                output: range.outputTokens,
                reasoning: range.reasoningTokens,
                cost: range.cost), range.models.count <= 256
            else {
                throw CockpitTeamError.invalidRequest
            }
            for model in range.models {
                guard self.text(model.modelID), model.name.map(self.text) ?? true,
                      self.metrics(
                          input: model.inputTokens,
                          cached: model.cachedInputTokens,
                          output: model.outputTokens,
                          reasoning: model.reasoningTokens,
                          cost: model.cost)
                else {
                    throw CockpitTeamError.invalidRequest
                }
            }
        }
        for (day, value) in snapshot.days {
            guard self.day(day), value.models.count <= 256,
                  self.metrics(
                      input: value.inputTokens,
                      cached: value.cachedInputTokens,
                      output: value.outputTokens,
                      reasoning: value.reasoningTokens,
                      cost: value.cost)
            else {
                throw CockpitTeamError.invalidRequest
            }
            for (id, model) in value.models {
                guard self.text(id), model.name.map(self.text) ?? true,
                      model.cacheWriteTokens.map(self.count) ?? true,
                      self.metrics(
                          input: model.inputTokens,
                          cached: model.cachedInputTokens,
                          output: model.outputTokens,
                          reasoning: model.reasoningTokens,
                          cost: model.cost)
                else {
                    throw CockpitTeamError.invalidRequest
                }
            }
        }
        if let meta = snapshot.metadata {
            guard meta.schemaVersion == 1, meta.collectedAt.map(self.timestamp) ?? true,
                  meta.retainedDays.map({ $0 >= 0 }) ?? true, (meta.nativeDays?.count ?? 0) <= 4096,
                  meta.nativeDays?.allSatisfy(self.day) ?? true else { throw CockpitTeamError.invalidRequest }
        }
    }

    private static func metrics(
        input: Int64,
        cached: Int64?,
        output: Int64,
        reasoning: Int64?,
        cost: Double?) -> Bool
    {
        self.count(input) && self.count(output) && (cached.map(self.count) ?? true)
            && (reasoning.map(self.count) ?? true)
            && (cost.map { $0.isFinite && (0...1e12).contains($0) } ?? true)
    }

    private static func count(_ value: Int64) -> Bool {
        (0...9_007_199_254_740_991).contains(value)
    }

    private static func text(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 256 && !value.unicodeScalars.contains(where: {
            $0.value < 32 || $0.value == 127 || (0x202A...0x202E).contains($0.value)
                || (0x2066...0x2069).contains($0.value)
        })
    }

    private static func day(_ value: String) -> Bool {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            return false
        }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == parts[0] && actual.month == parts[1] && actual.day == parts[2]
    }

    private static func timestamp(_ value: String) -> Bool {
        guard value.utf8.count <= 64 else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if formatter.date(from: value) != nil { return true }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) != nil
    }
}
