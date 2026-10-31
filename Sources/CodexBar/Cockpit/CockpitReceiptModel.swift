import CodexBarCore
import Foundation

struct CockpitReceiptLine: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let providerName: String
    let currencyCode: String
    let tokens: Int?
    let estimatedCost: Double?
    let tokensArePartial: Bool
    let costIsPartial: Bool
    var sessionCount = 1
    var lineageIsPartial = false
}

struct CockpitReceiptTotal: Identifiable, Equatable, Sendable {
    let currencyCode: String
    let knownTokens: Int?
    let knownCost: Double?
    let tokensArePartial: Bool
    let costIsPartial: Bool

    var id: String {
        self.currencyCode
    }
}

/// A receipt only totals selected, unique session rows. Unknown metrics remain explicitly partial.
struct CockpitReceiptModel: Equatable, Sendable {
    let createdAt: Date
    let scopeLabel: String
    let items: [CockpitReceiptLine]
    let totals: [CockpitReceiptTotal]

    init(items: [CockpitReceiptLine], createdAt: Date = Date(), scopeLabel: String = L("cockpit_ui_default_scope")) {
        self.createdAt = createdAt
        self.scopeLabel = scopeLabel
        var seen = Set<String>()
        self.items = items.filter { seen.insert($0.id).inserted }
        self.totals = Dictionary(grouping: self.items, by: \.currencyCode).map { currency, items in
            let tokens = items.compactMap(\.tokens)
            let costs = items.compactMap(\.estimatedCost)
            let totalTokens = tokens.isEmpty ? nil : CheckedSum.integers(tokens)
            let totalCost = SpendDashboardModel.safeCostSum(costs)
            return CockpitReceiptTotal(
                currencyCode: currency,
                knownTokens: totalTokens,
                knownCost: totalCost,
                tokensArePartial: items.contains(where: \.tokensArePartial)
                    || tokens.count != items.count || totalTokens == nil,
                costIsPartial: items.contains(where: \.costIsPartial)
                    || costs.count != items.count || totalCost == nil)
        }.sorted { $0.currencyCode < $1.currencyCode }
    }

    static func items(
        model: SpendDashboardModel,
        hidePersonalInfo: Bool,
        metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata] = [:],
        conflicting: Set<CockpitTaskIdentity> = []) -> [CockpitReceiptLine]
    {
        model.groups.flatMap { currencyGroup in
            self.taskItems(
                group: currencyGroup,
                hidePersonalInfo: hidePersonalInfo,
                metadata: metadata,
                conflicting: conflicting)
        }
    }

    /// Export the exact period-scoped summary shown by the session browser, without task expansion.
    static func session(
        context: SessionUsageBrowserContext,
        session: CostUsageSessionBreakdown,
        hidePersonalInfo: Bool,
        createdAt: Date = Date()) -> CockpitReceiptModel
    {
        let identity = CostHistoryIdentity(
            sessionID: session.sessionID,
            title: session.title,
            hidePersonalInfo: hidePersonalInfo)
        let tokens = SpendDashboardModel.nonnegative(session.totalTokens)
        let cost = SessionUsagePresentation.convertedCost(session.costUSD, multiplier: context.costMultiplier)
        let sourceID = context.sourceID ?? context.provider?.rawValue ?? context.providerName
        let providerName = hidePersonalInfo
            ? context.provider
            .map { ProviderDescriptorRegistry.descriptor(for: $0).metadata.displayName } ?? L("Provider")
            : context.providerName
        let line = CockpitReceiptLine(
            id: "session:\(context.provider?.rawValue ?? ""):\(sourceID.utf8.count):\(sourceID):\(session.sessionID)",
            title: identity.name,
            providerName: providerName,
            currencyCode: context.currencyCode,
            tokens: tokens,
            estimatedCost: cost,
            tokensArePartial: context.tokensArePartial || tokens == nil,
            costIsPartial: context.costIsPartial || cost == nil)
        return CockpitReceiptModel(
            items: [line],
            createdAt: createdAt,
            scopeLabel: [
                context.windowLabel,
                L("cockpit_ui_session_receipt_scope"),
                context.timeZone.identifier,
            ].joined(separator: "\n"))
    }

    static func scopeLabel(for period: CostReportingPeriod, timeZone: TimeZone) -> String {
        let activity: String = switch period {
        case let .rolling(days): L("cockpit_ui_active_last_days", days)
        case .monthToDate: L("cockpit_ui_active_this_month")
        case .allTime: L("cockpit_ui_all_scanned_tasks")
        }
        return activity + "\n" + L("cockpit_ui_full_session_scope") + "\n" + timeZone.identifier
    }

    private static func taskItems(
        group: SpendDashboardModel.CurrencyGroup,
        hidePersonalInfo: Bool,
        metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata],
        conflicting: Set<CockpitTaskIdentity>) -> [CockpitReceiptLine]
    {
        // Retained details can belong to an older snapshot; never bill them as the selected range.
        guard !group.detailsExcludedFromTotals else { return [] }
        var rows: [CockpitTaskIdentity: SpendDashboardModel.SessionRow] = [:]
        for row in group.sessions {
            let identity = CockpitTaskIdentity(sourceID: row.sourceID, sessionID: row.sessionID)
            if rows[identity] == nil { rows[identity] = row }
        }
        let required = Set(rows.compactMap { identity, row -> CockpitTaskIdentity? in
            let source = group.providers.first { $0.id == row.sourceID }
            return row.provider == .codex && source?.sourceKind == .native ? identity : nil
        })
        let graph = CockpitTaskLineage.build(
            sessionIDs: Set(rows.keys),
            metadata: metadata,
            metadataRequired: required,
            conflictingMetadata: conflicting)
        return graph.groups.compactMap { task in
            guard let root = rows[task.rootID] else { return nil }
            let lines = task.sessionIDs.compactMap { id -> CockpitReceiptLine? in
                guard let session = rows[id] else { return nil }
                return self.sessionLine(session, group: group, hidePersonalInfo: hidePersonalInfo)
            }
            let subtotal = CockpitReceiptModel(items: lines).totals.first
            var result = self.sessionLine(root, group: group, hidePersonalInfo: hidePersonalInfo)
            result = CockpitReceiptLine(
                id: "\(group.currencyCode):\(task.rootID.id)",
                title: result.title,
                providerName: result.providerName,
                currencyCode: group.currencyCode,
                tokens: subtotal?.knownTokens,
                estimatedCost: subtotal?.knownCost,
                tokensArePartial: subtotal?.tokensArePartial ?? true,
                costIsPartial: subtotal?.costIsPartial ?? true,
                sessionCount: lines.count,
                lineageIsPartial: !task.issues.isEmpty)
            return result
        }
    }

    private static func sessionLine(
        _ session: SpendDashboardModel.SessionRow,
        group: SpendDashboardModel.CurrencyGroup,
        hidePersonalInfo: Bool) -> CockpitReceiptLine
    {
        let source = group.providers.first { $0.id == session.sourceID }
        let identity = CostHistoryIdentity(
            sessionID: session.sessionID,
            title: session.title,
            hidePersonalInfo: hidePersonalInfo)
        let taskID = CockpitTaskIdentity(sourceID: session.sourceID, sessionID: session.sessionID)
        return CockpitReceiptLine(
            id: "\(group.currencyCode):\(taskID.id)",
            title: identity.name,
            providerName: hidePersonalInfo
                ? ProviderDescriptorRegistry.descriptor(for: session.provider).metadata.displayName
                : session.sourceName ?? session.provider.rawValue,
            currencyCode: group.currencyCode,
            tokens: SpendDashboardModel.nonnegative(session.totalTokens),
            estimatedCost: SpendDashboardModel.validCost(session.totalCost),
            tokensArePartial: source?.tokensAreLowerBound ?? true,
            costIsPartial: (source?.costIsLowerBound ?? true)
                || (source?.incompleteRequestCount ?? 0) > 0)
    }
}
