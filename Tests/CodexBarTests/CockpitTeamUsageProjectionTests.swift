import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CockpitTeamUsageProjectionTests {
    private static let now = date("2026-10-30T04:00:00Z")
    private static let boundAt = date("2026-10-27T04:00:00Z")

    @Test
    func `consent and independent source declaration are both required`() {
        let publication = Self.publication()
        let disabled = Self.project(publication, uploadEnabled: false)
        #expect(disabled.reason == .uploadDisabled)
        #expect(disabled.snapshot.days.isEmpty)
        let mirror = Self.project(publication, independentSourceConfirmed: false)
        #expect(mirror.reason == .independentSourceRequired)
        #expect(mirror.snapshot.days.isEmpty)
        let unbound = Self.project(publication, boundAt: nil)
        #expect(unbound.reason == .bindingRequired)
    }

    @Test
    func `binding day is withheld and subsequent current day is explicitly partial`() {
        let publication = Self.publication(entries: [
            Self.entry("2026-10-28"),
            Self.entry("2026-10-29"),
            Self.entry("2026-10-30"),
        ])
        let result = Self.project(publication, boundAt: Self.date("2026-10-29T04:00:00Z"))
        #expect(result.eligibleFrom == Self.date("2026-10-29T16:00:00Z"))
        #expect(Set(result.snapshot.days.keys) == ["2026-10-30"])
        #expect(result.dayCoverage["2026-10-30"] == .partial)
        #expect(result.availability == .partial)
        let firstDay = Self.project(publication, boundAt: Self.now)
        #expect(firstDay.reason == .awaitingFirstFullDay)
        #expect(firstDay.snapshot.days.isEmpty)
    }

    @Test
    func `closed days retain completeness while the current natural day stays open`() {
        let result = Self.project(Self.publication(entries: [Self.entry("2026-10-28"), Self.entry("2026-10-30")]))
        #expect(result.dayCoverage["2026-10-28"] == .complete)
        #expect(result.dayCoverage["2026-10-30"] == .partial)
        #expect(result.snapshot.metadata?.retainedDays == 0)
        #expect(result.snapshot.metadata?.nativeDays == ["2026-10-28", "2026-10-30"])
        let partialScan = Self.project(Self.publication(historyIsPartial: true))
        #expect(partialScan.dayCoverage["2026-10-28"] == .partial)
    }

    @Test(arguments: ["America/New_York", "UTC", "", "Etc/GMT-8"])
    func `daily aggregates never acquire a different time zone label`(zone: String) {
        let result = Self.project(Self.publication(zone: zone))
        #expect(result.availability == .unavailable)
        #expect(result.reason == .incompatibleTimeZone)
        #expect(result.snapshot.days.isEmpty)
    }

    @Test
    func `only the explicit ambient source is exported without another account`() {
        let publication = Self.publication(extraInput: .init(
            id: "codex:managed",
            provider: .codex,
            displayName: "Private account",
            snapshot: Self.snapshot(entries: [Self.entry("2026-10-28", input: 999)])))
        let result = Self.project(publication)
        #expect(result.snapshot.days["2026-10-28"]?.inputTokens == 140)
        let unidentified = Self.project(publication, ambientSourceID: nil)
        #expect(unidentified.reason == .sourceUnavailable)
        let stale = Self.project(Self.publication(sourceState: .staleLastKnown))
        #expect(stale.reason == .sourceUnavailable)
    }

    @Test
    func `OpenCodex and Pi mixed sources cannot be uploaded as native Codex`() {
        #expect(Self.project(Self.publication(openCodexEnabled: true)).reason == .mixedSource)
        #expect(Self.project(Self.publication(sourceKind: .openCodex)).reason == .mixedSource)
        let native = Self.snapshot(entries: [Self.entry("2026-10-28")])
        #expect(Self.project(Self.publication(accounting: .includesPi(scope: "synthetic", native: native)))
            .reason == .mixedSource)
    }

    @Test
    func `non USD and account metered data remain unavailable`() {
        #expect(Self.project(Self.publication(currency: "EUR")).reason == .unsupportedCurrency)
        #expect(Self.project(Self.publication(provenance: .vendorMetered)).reason == .unsupportedCostProvenance)
        #expect(Self.project(Self.publication(provenance: .mixed)).reason == .unsupportedCostProvenance)
    }

    @Test
    func `unknown cost and priced subtotals are never promoted to full daily cost`() {
        let unknown = Self.project(Self.publication(provenance: .unknown))
        #expect(unknown.snapshot.days["2026-10-28"]?.cost == nil)
        #expect(unknown.costProvenance == .unknown)
        let unpriced = Self.entry("2026-10-28", unpriced: 2)
        let partial = Self.project(Self.publication(entries: [unpriced]))
        #expect(partial.snapshot.days["2026-10-28"]?.cost == nil)
        #expect(partial.dayCoverage["2026-10-28"] == .partial)
        let zero = Self.project(Self.publication(entries: [Self.entry("2026-10-28", cost: 0)]))
        #expect(zero.snapshot.days["2026-10-28"]?.cost == 0)
    }

    @Test
    func `inclusive daily input becomes exclusive v2 model input without counting cache twice`() throws {
        let model = CostUsageDailyReport.ModelBreakdown(
            modelName: "gpt-5",
            costUSD: 1,
            totalTokens: 150,
            inputTokens: 140,
            outputTokens: 10,
            cacheReadTokens: 40,
            reasoningTokens: 4)
        let result = Self.project(Self.publication(entries: [Self.entry("2026-10-28", models: [model])]))
        let day = try #require(result.snapshot.days["2026-10-28"])
        #expect(day.inputTokens == 140)
        #expect(day.cachedInputTokens == 40)
        #expect(day.models["gpt-5"]?.inputTokens == 100)
        #expect(day.models["gpt-5"]?.cachedInputTokens == 40)
        #expect(day.outputTokens == 10)
        #expect(day.models["gpt-5"]?.reasoningTokens == 4)
    }

    @Test
    func `unknown token classes remain absent and malformed totals are not invented`() {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-10-28",
            inputTokens: 140,
            outputTokens: 10,
            totalTokens: 150,
            costUSD: nil,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let result = Self.project(Self.publication(entries: [entry]))
        #expect(result.snapshot.days["2026-10-28"]?.cachedInputTokens == nil)
        #expect(result.snapshot.days["2026-10-28"]?.reasoningTokens == nil)
        let unknown = CostUsageDailyReport.Entry(
            date: "2026-10-28",
            inputTokens: nil,
            outputTokens: 10,
            totalTokens: nil,
            costUSD: nil,
            modelsUsed: nil,
            modelBreakdowns: nil)
        let unknownResult = Self.project(Self.publication(entries: [unknown]))
        #expect(unknownResult.snapshot.days.isEmpty)
        #expect(unknownResult.availability == .partial)
    }

    @Test
    func `invalid and duplicate dates fail closed rather than accumulating copies`() {
        let duplicate = Self.project(Self.publication(entries: [Self.entry("2026-10-28"), Self.entry("2026-10-28")]))
        #expect(duplicate.reason == .invalidData)
        #expect(duplicate.snapshot.days.isEmpty)
        #expect(Self.project(Self.publication(entries: [Self.entry("2026-02-30")])).reason == .invalidData)
    }

    @Test
    func `wire snapshot has aggregate fields only and excludes session and account metadata`() throws {
        let result = Self.project(Self.publication())
        let encoded = try JSONEncoder().encode(result.snapshot)
        let text = try #require(String(data: encoded, encoding: .utf8))
        for forbidden in [
            "private-title",
            "/Users/synthetic",
            "private-session",
            "private@example.test",
            "credential",
        ] {
            #expect(!text.contains(forbidden))
        }
        let decoded = try JSONDecoder().decode(CockpitTeamUsageSnapshot.self, from: encoded)
        #expect(decoded == result.snapshot)
        #expect(decoded.codex.ranges.isEmpty)
    }

    private static func project(
        _ publication: SpendDashboardPublication,
        ambientSourceID: String? = "codex:ambient",
        uploadEnabled: Bool = true,
        independentSourceConfirmed: Bool = true,
        boundAt: Date? = Self.boundAt) -> CockpitTeamUsageProjection.Result
    {
        CockpitTeamUsageProjection.build(
            publication: publication,
            ambientSourceID: ambientSourceID,
            deviceID: "synthetic-device",
            uploadEnabled: uploadEnabled,
            independentSourceConfirmed: independentSourceConfirmed,
            boundAt: boundAt,
            now: self.now)
    }

    private static func publication(
        entries: [CostUsageDailyReport.Entry] = [Self.entry("2026-10-28")],
        zone: String = "Asia/Shanghai",
        currency: String = "USD",
        provenance: CostProvenance = .listPriceEstimate,
        historyIsPartial: Bool = false,
        openCodexEnabled: Bool = false,
        sourceKind: SpendDashboardModel.SourceKind = .native,
        sourceState: SpendSourcePublication.State = .available,
        accounting: PiSnapshotAccounting? = nil,
        extraInput: SpendDashboardModel.ProviderInput? = nil) -> SpendDashboardPublication
    {
        var inputs = [SpendDashboardModel.ProviderInput(
            id: "codex:ambient",
            provider: .codex,
            displayName: "private@example.test",
            snapshot: self.snapshot(
                entries: entries,
                currency: currency,
                provenance: provenance,
                historyIsPartial: historyIsPartial),
            sourceKind: sourceKind,
            accounting: accounting)]
        if let extraInput { inputs.append(extraInput) }
        return SpendDashboardPublication(
            revision: 1,
            generation: 1,
            configuration: SpendDashboardConfiguration(
                costUsageEnabled: true,
                providerIDs: ["codex"],
                codexAccountIdentities: ["ambient|synthetic-cache"],
                bucketTimeZoneIdentifier: zone,
                openCodexUsageLogsEnabled: openCodexEnabled),
            loadedAt: self.now,
            isRefreshing: false,
            inputs: inputs,
            sources: [.init(
                id: "codex:ambient",
                provider: .codex,
                displayName: "Synthetic",
                role: .subscription,
                state: sourceState)])
    }

    private static func snapshot(
        entries: [CostUsageDailyReport.Entry],
        currency: String = "USD",
        provenance: CostProvenance = .listPriceEstimate,
        historyIsPartial: Bool = false) -> CostUsageTokenSnapshot
    {
        CostUsageTokenSnapshot(
            sessionTokens: nil,
            sessionCostUSD: nil,
            last30DaysTokens: nil,
            last30DaysCostUSD: nil,
            currencyCode: currency,
            historyScanIsPartial: historyIsPartial,
            costProvenance: provenance,
            credentialScopeFingerprint: "private-credential-fingerprint",
            daily: entries,
            sessions: [.init(
                sessionID: "private-session",
                lastActivity: self.now,
                inputTokens: 140,
                cachedInputTokens: 40,
                outputTokens: 10,
                totalTokens: 150,
                requestCount: 1,
                costUSD: 1,
                modelBreakdowns: [],
                projectPath: "/Users/synthetic/private-project",
                title: "private-title")],
            updatedAt: self.now)
    }

    private static func entry(
        _ day: String,
        input: Int = 140,
        cost: Double? = 1,
        unpriced: Int? = nil,
        models: [CostUsageDailyReport.ModelBreakdown]? = nil) -> CostUsageDailyReport.Entry
    {
        CostUsageDailyReport.Entry(
            date: day,
            inputTokens: input,
            outputTokens: 10,
            cacheReadTokens: 40,
            totalTokens: input + 10,
            costUSD: cost,
            modelsUsed: nil,
            modelBreakdowns: models,
            unpricedRequestCount: unpriced)
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
