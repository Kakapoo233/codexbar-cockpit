import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CockpitSessionReceiptTests {
    @Test
    func `receipt uses only the selected period summary without expanding other sessions or turns`() throws {
        let selected = self.session(tokens: 140, cost: 2).withRequestDetails([
            CostUsageSessionTurn(
                turnID: "synthetic-turn",
                firstActivity: nil,
                lastActivity: nil,
                inputTokens: 9000,
                cachedInputTokens: 0,
                outputTokens: 1000,
                reasoningTokens: nil,
                totalTokens: 10000,
                requestCount: 1,
                costUSD: 100),
        ])
        let context = self.context(
            sessions: [selected, self.session(id: "other-session", tokens: 99999, cost: 999)],
            currencyCode: "EUR",
            multiplier: 3)
        let receipt = CockpitReceiptModel.session(
            context: context,
            session: selected,
            hidePersonalInfo: false,
            createdAt: Date(timeIntervalSince1970: 1234))

        let item = try #require(receipt.items.first)
        let total = try #require(receipt.totals.first)
        #expect(receipt.items.count == 1)
        #expect(item.sessionCount == 1)
        #expect(!item.lineageIsPartial)
        #expect(item.tokens == 140)
        #expect(item.estimatedCost == 6)
        #expect(total.currencyCode == "EUR")
        #expect(total.knownTokens == 140)
        #expect(total.knownCost == 6)
        #expect(!total.tokensArePartial)
        #expect(!total.costIsPartial)
        #expect(receipt.createdAt == Date(timeIntervalSince1970: 1234))
        #expect(receipt.scopeLabel == [
            context.windowLabel,
            L("cockpit_ui_session_receipt_scope"),
            context.timeZone.identifier,
        ].joined(separator: "\n"))
        #expect(!receipt.scopeLabel.contains(L("cockpit_ui_full_session_scope")))
    }

    @Test
    func `missing metrics remain unknown while measured zero remains complete`() throws {
        let unknown = CockpitReceiptModel.session(
            context: self.context(),
            session: self.session(tokens: nil, cost: nil),
            hidePersonalInfo: false)
        let unknownTotal = try #require(unknown.totals.first)
        #expect(unknownTotal.knownTokens == nil)
        #expect(unknownTotal.knownCost == nil)
        #expect(unknownTotal.tokensArePartial)
        #expect(unknownTotal.costIsPartial)

        let zero = CockpitReceiptModel.session(
            context: self.context(),
            session: self.session(tokens: 0, cost: 0),
            hidePersonalInfo: false)
        let zeroTotal = try #require(zero.totals.first)
        #expect(zeroTotal.knownTokens == 0)
        #expect(zeroTotal.knownCost == 0)
        #expect(!zeroTotal.tokensArePartial)
        #expect(!zeroTotal.costIsPartial)
    }

    @Test
    func `partial source coverage preserves known amounts with explicit partial totals`() throws {
        var context = self.context()
        context.tokensArePartial = true
        context.costIsPartial = true
        let receipt = CockpitReceiptModel.session(
            context: context,
            session: self.session(tokens: 140, cost: 2),
            hidePersonalInfo: false)
        let item = try #require(receipt.items.first)
        let total = try #require(receipt.totals.first)
        #expect(item.tokens == 140)
        #expect(item.estimatedCost == 2)
        #expect(item.tokensArePartial)
        #expect(item.costIsPartial)
        #expect(total.knownTokens == 140)
        #expect(total.knownCost == 2)
        #expect(total.tokensArePartial)
        #expect(total.costIsPartial)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1, 0])
    func `invalid conversion never produces a known cost`(multiplier: Double) throws {
        let receipt = CockpitReceiptModel.session(
            context: self.context(multiplier: multiplier),
            session: self.session(tokens: 140, cost: 2),
            hidePersonalInfo: false)
        let total = try #require(receipt.totals.first)
        #expect(total.knownCost == nil)
        #expect(total.costIsPartial)
        #expect(total.knownTokens == 140)
        #expect(!total.tokensArePartial)
    }

    @Test(arguments: [Double.nan, Double.infinity, -Double.infinity, -1, Double.greatestFiniteMagnitude])
    func `invalid native cost and conversion overflow remain unknown`(cost: Double) throws {
        let receipt = CockpitReceiptModel.session(
            context: self.context(multiplier: 2),
            session: self.session(tokens: -1, cost: cost),
            hidePersonalInfo: false)
        let total = try #require(receipt.totals.first)
        #expect(total.knownTokens == nil)
        #expect(total.tokensArePartial)
        #expect(total.knownCost == nil)
        #expect(total.costIsPartial)
    }

    @Test
    func `privacy masks both the title and stale personal provider label`() throws {
        let session = self.session(title: "Private project title")
        var context = self.context()
        let visible = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: false)
        let hidden = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: true)
        let hiddenItem = try #require(hidden.items.first)
        #expect(visible.items.first?.title == "Private project title")
        #expect(visible.items.first?.providerName == "Synthetic personal account")
        #expect(hiddenItem.title == CostHistoryIdentity(
            sessionID: session.sessionID,
            title: session.title,
            hidePersonalInfo: true).name)
        #expect(hiddenItem.providerName == ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName)
        #expect(!hidden.scopeLabel.contains("Private"))
        #expect(!hiddenItem.providerName.contains("personal"))

        context.provider = nil
        let fallback = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: true)
        #expect(fallback.items.first?.providerName == L("Provider"))
    }

    @Test
    func `identity is stable across display changes and scoped by source and session`() {
        let session = self.session()
        var context = self.context()
        let first = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: false)
        context = self.context(providerName: "Changed display label", multiplier: 2)
        let hidden = CockpitReceiptModel.session(
            context: context,
            session: session.withTitle("Changed title"),
            hidePersonalInfo: true)
        #expect(first.items.first?.id == hidden.items.first?.id)

        context.sourceID = "other-source"
        let otherSource = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: true)
        #expect(first.items.first?.id != otherSource.items.first?.id)
        let otherSession = CockpitReceiptModel.session(
            context: self.context(),
            session: self.session(id: "other-session"),
            hidePersonalInfo: true)
        #expect(first.items.first?.id != otherSession.items.first?.id)

        context.sourceID = nil
        let codex = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: true)
        context.provider = .claude
        let claude = CockpitReceiptModel.session(context: context, session: session, hidePersonalInfo: true)
        #expect(codex.items.first?.id != claude.items.first?.id)
    }

    private func context(
        sessions: [CostUsageSessionBreakdown] = [],
        providerName: String = "Synthetic personal account",
        currencyCode: String = "USD",
        multiplier: Double = 1) -> SessionUsageBrowserContext
    {
        SessionUsageBrowserContext(
            providerName: providerName,
            windowLabel: "Synthetic reporting period",
            sessions: sessions,
            currencyCode: currencyCode,
            costMultiplier: multiplier,
            timeZone: .gmt,
            activityRange: Date(timeIntervalSince1970: 0)..<Date(timeIntervalSince1970: 100),
            sourceID: "synthetic-source",
            provider: .codex)
    }

    private func session(
        id: String = "synthetic-session",
        tokens: Int? = 140,
        cost: Double? = 2,
        title: String? = nil) -> CostUsageSessionBreakdown
    {
        CostUsageSessionBreakdown(
            sessionID: id,
            lastActivity: Date(timeIntervalSince1970: 50),
            inputTokens: 120,
            cachedInputTokens: 90,
            outputTokens: 20,
            totalTokens: tokens,
            requestCount: 2,
            costUSD: cost,
            modelBreakdowns: [],
            projectPath: "/synthetic/private-project",
            title: title)
    }
}
