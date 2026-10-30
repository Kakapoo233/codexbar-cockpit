import Foundation

/// Values come from the application's existing session index; no independent session scanner is introduced.
public struct CockpitReceiptItem: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let providerID: String
    public let accountID: String
    public let title: String
    public let totalTokens: Int?
    public let knownCostUSD: Double?
    public let hasUnknownCost: Bool

    public init(
        id: String,
        providerID: String,
        accountID: String = "default",
        title: String,
        totalTokens: Int?,
        knownCostUSD: Double?,
        hasUnknownCost: Bool)
    {
        self.id = id
        self.providerID = providerID
        self.accountID = accountID
        self.title = title
        self.totalTokens = totalTokens.flatMap { $0 >= 0 ? $0 : nil }
        self.knownCostUSD = knownCostUSD.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.hasUnknownCost = hasUnknownCost || self.knownCostUSD == nil
    }
}

public struct CockpitReceipt: Equatable, Sendable {
    public let items: [CockpitReceiptItem]
    public let knownTokens: Int
    public let totalTokens: Int?
    public let knownCostUSD: Double?
    public let incompleteCostItemCount: Int

    public var hasUnknownCost: Bool { self.incompleteCostItemCount > 0 }

    /// Uses provider/account/session identity. Equal titles and duplicate selections never merge different tasks.
    public static func build(items: [CockpitReceiptItem], selectedSessionIDs: Set<String>) -> Self {
        struct Identity: Hashable {
            let provider: String
            let account: String
            let session: String
        }
        var seen: Set<Identity> = []
        let selected = items.filter { item in
            selectedSessionIDs.contains(item.id) && seen.insert(Identity(
                provider: item.providerID, account: item.accountID, session: item.id)).inserted
        }
        var knownTokens = 0
        var tokensComplete = true
        var knownCost: Double?
        var incompleteCostCount = 0
        for item in selected {
            var costIncomplete = item.hasUnknownCost
            if let tokens = item.totalTokens {
                let sum = knownTokens.addingReportingOverflow(tokens)
                knownTokens = sum.overflow ? Int.max : sum.partialValue
                tokensComplete = tokensComplete && !sum.overflow
            } else {
                tokensComplete = false
            }
            if let cost = item.knownCostUSD {
                let sum = (knownCost ?? 0) + cost
                knownCost = sum.isFinite ? sum : knownCost
                costIncomplete = costIncomplete || !sum.isFinite
            }
            if costIncomplete { incompleteCostCount += 1 }
        }
        return Self(
            items: selected,
            knownTokens: knownTokens,
            totalTokens: tokensComplete && !selected.isEmpty ? knownTokens : nil,
            knownCostUSD: knownCost,
            incompleteCostItemCount: incompleteCostCount)
    }
}
