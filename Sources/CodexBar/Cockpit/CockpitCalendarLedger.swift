import CodexBarCore
import Foundation

enum CockpitCalendarMetric: String, CaseIterable, Identifiable {
    case tokens
    case cost

    var id: String {
        self.rawValue
    }

    var title: String {
        L(self == .tokens ? "Tokens" : "Cost")
    }
}

/// Page-local aggregation of published daily records. Missing history is never filled with zeroes.
struct CockpitCalendarLedger {
    struct TokenValue: Equatable {
        let total: Int?
        let isPartial: Bool
    }

    struct CostValue: Equatable, Identifiable {
        let currencyCode: String
        let total: Double?
        let isPartial: Bool
        var id: String {
            self.currencyCode
        }
    }

    struct Summary: Equatable {
        let tokens: TokenValue
        let costs: [CostValue]
    }

    let model: SpendDashboardModel
    let calendar: Calendar
    let now: Date
    private let summariesByCurrency: [String: [Date: SpendDashboardModel.DailySummary]]
    private let tokenActivityByDay: [Date: SpendDashboardModel.TokenActivityPoint]

    init(model: SpendDashboardModel, calendar: Calendar, now: Date) {
        self.model = model
        self.calendar = calendar
        self.now = now
        self.summariesByCurrency = model.groups.reduce(into: [:]) { groups, group in
            groups[group.currencyCode] = group.dailySummaries.reduce(into: [:]) { days, summary in
                days[calendar.startOfDay(for: summary.day)] = summary
            }
        }
        self.tokenActivityByDay = model.tokenActivity.reduce(into: [:]) { days, point in
            days[calendar.startOfDay(for: point.day)] = point
        }
    }

    func summary(for period: CockpitCalendarPeriod) -> Summary {
        let days = period.days(calendar: self.calendar, through: self.now)
        let tokens = days.map(self.tokens(on:))
        let available = tokens.compactMap(\.total)
        let total = available.isEmpty ? nil : CheckedSum.integers(available)
        let costs = self.model.groups.map { group in
            let rows = days.map { self.summariesByCurrency[group.currencyCode]?[$0] }
            let amounts = rows.compactMap { $0?.totalCost }.filter { $0.isFinite && $0 >= 0 }
            let amount = amounts.isEmpty ? nil : amounts.reduce(0, +)
            return CostValue(
                currencyCode: group.currencyCode,
                total: amount.flatMap { $0.isFinite ? $0 : nil },
                isPartial: rows.count != amounts.count || rows.contains { $0?.hasPartialCost == true })
        }
        return Summary(
            tokens: TokenValue(
                total: total,
                isPartial: total == nil || available.count != days.count || tokens.contains(where: \.isPartial)),
            costs: costs)
    }

    func tokens(on day: Date) -> TokenValue {
        guard self.calendar.startOfDay(for: day) <= self.calendar.startOfDay(for: self.now) else {
            return TokenValue(total: nil, isPartial: true)
        }
        let key = self.calendar.startOfDay(for: day)
        let summaries = self.model.groups.compactMap { self.summariesByCurrency[$0.currencyCode]?[key] }
        if summaries.isEmpty {
            let value = self.tokenActivityByDay[key]
            return TokenValue(total: value?.totalTokens, isPartial: value?.totalTokens == nil)
        }
        let amounts = summaries.compactMap(\.totalTokens)
        let total = amounts.isEmpty ? nil : CheckedSum.integers(amounts)
        return TokenValue(
            total: total,
            isPartial: total == nil || summaries.count != self.model.groups.count || amounts.count != summaries.count
                || summaries.contains(where: \.hasPartialCounts))
    }

    func text(on day: Date, metric: CockpitCalendarMetric) -> String {
        self.text(
            self.summary(for: CockpitCalendarPeriod(containing: day, scale: .day, calendar: self.calendar)),
            metric: metric)
    }

    func text(_ summary: Summary, metric: CockpitCalendarMetric) -> String {
        switch metric {
        case .tokens:
            return summary.tokens.total.map {
                spendDashboardLowerBoundText(
                    UsageFormatter.tokenCountString($0),
                    isLowerBound: summary.tokens.isPartial)
            } ?? "—"
        case .cost:
            guard !summary.costs.isEmpty else { return "—" }
            return summary.costs.map { cost in
                cost.total.map {
                    spendDashboardLowerBoundText(
                        UsageFormatter.currencyString($0, currencyCode: cost.currencyCode),
                        isLowerBound: cost.isPartial)
                } ?? "\(cost.currencyCode) —"
            }.joined(separator: " · ")
        }
    }
}
