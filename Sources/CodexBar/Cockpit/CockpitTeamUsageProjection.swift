import CodexBarCore
import Foundation

/// A deliberately narrow v2 export of an explicitly bound, independent local Codex history.
/// No account identity is inferred, and neither a cloud snapshot nor a UI-filtered total is an input.
enum CockpitTeamUsageProjection {
    static let reportingTimeZoneIdentifier = "Asia/Shanghai"
    private static let maximumSafeCount: Int64 = 9_007_199_254_740_991

    enum UnavailableReason: String, Equatable, Sendable {
        case uploadDisabled, independentSourceRequired, bindingRequired, awaitingFirstFullDay
        case sourceUnavailable, incompatibleTimeZone, mixedSource, unsupportedCurrency
        case unsupportedCostProvenance, invalidData
    }

    struct Result: Equatable, Sendable {
        let snapshot: CockpitTeamUsageSnapshot
        let availability: CockpitTeamSnapshotMetadata.Status
        let reason: UnavailableReason?
        let eligibleFrom: Date?
        let dayCoverage: [String: CockpitCoverage]
        let costProvenance: CostProvenance
    }

    // `ambientSourceID` must come from the live-system CodexSpendScanRequest, never the selected managed account.
    // Binding starts at the following Shanghai midnight: an aggregate cannot remove pre-consent events from today.
    // swiftlint:disable:next function_parameter_count
    static func build(
        publication: SpendDashboardPublication,
        ambientSourceID: String?,
        deviceID: String,
        uploadEnabled: Bool,
        independentSourceConfirmed: Bool,
        boundAt: Date?,
        now: Date = Date()) -> Result
    {
        let eligibleFrom = boundAt.flatMap { self.firstEligibleDay(after: $0) }
        func unavailable(_ reason: UnavailableReason) -> Result {
            self.result(deviceID: deviceID, now: now, eligibleFrom: eligibleFrom, reason: reason)
        }
        guard uploadEnabled else { return unavailable(.uploadDisabled) }
        guard independentSourceConfirmed else { return unavailable(.independentSourceRequired) }
        guard let boundAt, boundAt <= now, let eligibleFrom else { return unavailable(.bindingRequired) }
        guard now >= eligibleFrom else { return unavailable(.awaitingFirstFullDay) }
        guard let configuration = publication.configuration,
              configuration.bucketTimeZoneIdentifier == self.reportingTimeZoneIdentifier
        else { return unavailable(.incompatibleTimeZone) }
        guard !configuration.openCodexUsageLogsEnabled else { return unavailable(.mixedSource) }
        guard configuration.costUsageEnabled, let ambientSourceID,
              ambientSourceID.hasPrefix("codex:"),
              configuration.codexAccountIdentities.contains(where: {
                  $0.hasPrefix(String(ambientSourceID.dropFirst("codex:".count)) + "|")
              }),
              publication.sources.contains(where: {
                  $0.id == ambientSourceID && $0.provider == .codex && $0.state == .available
              })
        else { return unavailable(.sourceUnavailable) }
        let matches = publication.inputs.filter { $0.id == ambientSourceID && $0.provider == .codex }
        guard matches.count == 1, let input = matches.first else { return unavailable(.sourceUnavailable) }
        guard input.sourceKind == .native else { return unavailable(.mixedSource) }
        if let accounting = input.accounting, accounting != .nativeOnly { return unavailable(.mixedSource) }
        let snapshot = input.snapshot
        guard !snapshot.daily.contains(where: { entry in
            entry.modelBreakdowns?.contains(where: { $0.sourceRecorded == true }) == true
        }) else { return unavailable(.mixedSource) }
        guard snapshot.currencyCode == "USD" else { return unavailable(.unsupportedCurrency) }
        guard snapshot.meteredCostUSD == nil,
              snapshot.costProvenance == .listPriceEstimate || snapshot.costProvenance == .unknown
        else { return unavailable(.unsupportedCostProvenance) }
        guard snapshot.daily.count <= 4096 else { return unavailable(.invalidData) }
        return self.project(snapshot, deviceID: deviceID, eligibleFrom: eligibleFrom, now: now)
    }

    static func firstEligibleDay(after binding: Date) -> Date? {
        guard binding.timeIntervalSince1970.isFinite else { return nil }
        let calendar = self.calendar
        return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: binding))
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: self.reportingTimeZoneIdentifier)!
        return calendar
    }

    private static func project(
        _ snapshot: CostUsageTokenSnapshot,
        deviceID: String,
        eligibleFrom: Date,
        now: Date) -> Result
    {
        let today = self.calendar.startOfDay(for: now)
        var seen = Set<String>()
        var days: [String: CockpitTeamLedgerDay] = [:]
        var coverage: [String: CockpitCoverage] = [:]
        var isPartial = !snapshot.historyIsFullyScanned
        for entry in snapshot.daily {
            guard let date = self.day(entry.date), seen.insert(entry.date).inserted else {
                return self.result(deviceID: deviceID, now: now, eligibleFrom: eligibleFrom, reason: .invalidData)
            }
            guard date >= eligibleFrom else { continue }
            guard date <= today, let mapped = self.ledgerDay(entry, provenance: snapshot.costProvenance) else {
                isPartial = true
                continue
            }
            let partial = !snapshot.historyIsFullyScanned || date == today || mapped.partial
            days[entry.date] = mapped.day
            coverage[entry.date] = partial ? .partial : .complete
            isPartial = isPartial || partial
        }
        let status: CockpitTeamSnapshotMetadata.Status = isPartial ? .partial : .ready
        let payload = CockpitTeamUsageSnapshot(
            deviceID: deviceID,
            timestamp: self.timestamp(now),
            days: days,
            metadata: CockpitTeamSnapshotMetadata(
                collectedAt: self.iso8601(snapshot.updatedAt),
                status: status,
                retainedDays: 0,
                nativeDays: days.keys.sorted()))
        return Result(
            snapshot: payload,
            availability: status,
            reason: nil,
            eligibleFrom: eligibleFrom,
            dayCoverage: coverage,
            costProvenance: snapshot.costProvenance)
    }

    private static func ledgerDay(
        _ entry: CostUsageDailyReport.Entry,
        provenance: CostProvenance) -> (day: CockpitTeamLedgerDay, partial: Bool)?
    {
        guard let input = self.count(entry.inputTokens), let output = self.count(entry.outputTokens),
              let total = self.count(entry.totalTokens), input <= self.maximumSafeCount - output,
              input + output == total,
              self.validSubset(entry.cacheReadTokens, of: input),
              self.validSubset(entry.reasoningTokens, of: output),
              entry.cacheCreationTokens == nil || entry.cacheCreationTokens == 0
        else { return nil }
        let incomplete = entry.incompleteRequestCount > 0 || (entry.unpricedRequestCount ?? 0) > 0
            || (entry.unmeteredRequestCount ?? 0) > 0
        // A priced subtotal with unknown requests is not the day's full cost.
        let cost = !incomplete && provenance == .listPriceEstimate ? self.cost(entry.costUSD) : nil
        var models: [String: CockpitTeamLedgerModel] = [:]
        var incompleteModels = false
        for model in entry.modelBreakdowns ?? [] {
            guard let mapped = self.ledgerModel(model, provenance: provenance), models[model.modelName] == nil else {
                incompleteModels = true
                models.removeAll()
                break
            }
            models[model.modelName] = mapped
        }
        return (
            CockpitTeamLedgerDay(
                inputTokens: input,
                cachedInputTokens: self.count(entry.cacheReadTokens),
                outputTokens: output,
                reasoningTokens: self.count(entry.reasoningTokens),
                cost: cost,
                models: models),
            incomplete || incompleteModels || cost == nil)
    }

    private static func ledgerModel(
        _ model: CostUsageDailyReport.ModelBreakdown,
        provenance: CostProvenance) -> CockpitTeamLedgerModel?
    {
        // Native day input includes cache reads; v2 model input excludes them. Unknown cache must not become zero.
        guard model.modelName.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._:+-]{0,127}$"#,
            options: .regularExpression) != nil,
            model.sourceRecorded != true,
            let input = self.count(model.inputTokens), let cached = self.count(model.cacheReadTokens),
            let output = self.count(model.outputTokens), cached <= input,
            self.validSubset(model.reasoningTokens, of: output),
            model.cacheCreationTokens == nil || model.cacheCreationTokens == 0
        else { return nil }
        return CockpitTeamLedgerModel(
            inputTokens: input - cached,
            cachedInputTokens: cached,
            outputTokens: output,
            reasoningTokens: self.count(model.reasoningTokens),
            cost: provenance == .listPriceEstimate && (model.incompleteRequestCount ?? 0) == 0
                ? self.cost(model.costUSD) : nil)
    }

    private static func count(_ value: Int?) -> Int64? {
        guard let value, let count = Int64(exactly: value), (0...self.maximumSafeCount).contains(count) else {
            return nil
        }
        return count
    }

    private static func validSubset(_ value: Int?, of total: Int64) -> Bool {
        guard let value else { return true }
        return self.count(value).map { $0 <= total } ?? false
    }

    private static func cost(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && (0...1e12).contains($0) ? $0 : nil }
    }

    private static func day(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              CockpitCalendar.dateKey(for: date, calendar: self.calendar) == value
        else { return nil }
        return date
    }

    private static func timestamp(_ date: Date) -> Int64 {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, (0...Double(self.maximumSafeCount)).contains(seconds) else { return 0 }
        return Int64(seconds.rounded(.down))
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func result(
        deviceID: String,
        now: Date,
        eligibleFrom: Date?,
        reason: UnavailableReason) -> Result
    {
        Result(
            snapshot: CockpitTeamUsageSnapshot(
                deviceID: deviceID,
                timestamp: self.timestamp(now),
                metadata: CockpitTeamSnapshotMetadata(
                    collectedAt: self.iso8601(now),
                    status: .unavailable,
                    retainedDays: 0,
                    nativeDays: [])),
            availability: .unavailable,
            reason: reason,
            eligibleFrom: eligibleFrom,
            dayCoverage: [:],
            costProvenance: .unknown)
    }
}
