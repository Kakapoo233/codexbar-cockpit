import Foundation
import Testing
@testable import CodexBarCore

struct CockpitReceiptCoreTests {
    private func item(
        _ id: String,
        tokens: Int? = 100,
        cost: Double? = 1,
        unknown: Bool = false) -> CockpitReceiptItem
    {
        CockpitReceiptItem(
            id: id, providerID: "codex", title: "Same task title",
            totalTokens: tokens, knownCostUSD: cost, hasUnknownCost: unknown)
    }

    @Test
    func `stable session identities deduplicate selections while equal titles remain distinct`() {
        let first = self.item("one")
        let receipt = CockpitReceipt.build(items: [first, first, self.item("two")], selectedSessionIDs: ["one", "two"])
        #expect(receipt.items.count == 2)
        #expect(receipt.totalTokens == 200)
        #expect(receipt.knownCostUSD == 2)
        #expect(!receipt.hasUnknownCost)
    }

    @Test
    func `partly priced tasks retain their known amount without becoming complete`() {
        let receipt = CockpitReceipt.build(
            items: [self.item("one", cost: 2, unknown: true), self.item("two", cost: nil)],
            selectedSessionIDs: ["one", "two"])
        #expect(receipt.knownCostUSD == 2)
        #expect(receipt.incompleteCostItemCount == 2)
        #expect(receipt.hasUnknownCost)
        #expect(receipt.totalTokens == 200)
    }

    @Test
    func `missing values stay unknown while a measured zero is preserved`() {
        let unknown = CockpitReceipt.build(
            items: [self.item("unknown", tokens: nil, cost: nil)], selectedSessionIDs: ["unknown"])
        #expect(unknown.totalTokens == nil)
        #expect(unknown.knownCostUSD == nil)
        let zero = CockpitReceipt.build(
            items: [self.item("zero", tokens: 0, cost: 0)], selectedSessionIDs: ["zero"])
        #expect(zero.totalTokens == 0)
        #expect(zero.knownCostUSD == 0)
        #expect(!zero.hasUnknownCost)
        let empty = CockpitReceipt.build(items: [], selectedSessionIDs: [])
        #expect(empty.totalTokens == nil)
        #expect(empty.knownCostUSD == nil)
    }

    @Test
    func `token and cost overflow degrade completeness without wrapping or nonfinite totals`() {
        let receipt = CockpitReceipt.build(items: [
            self.item("one", tokens: Int.max, cost: Double.greatestFiniteMagnitude),
            self.item("two", tokens: 1, cost: Double.greatestFiniteMagnitude),
        ], selectedSessionIDs: ["one", "two"])
        #expect(receipt.totalTokens == nil)
        #expect(receipt.knownTokens == Int.max)
        #expect(receipt.knownCostUSD?.isFinite == true)
        #expect(receipt.hasUnknownCost)
    }
}
