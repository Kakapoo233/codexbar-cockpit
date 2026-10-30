import CodexBarCore
import Foundation
import SwiftUI

extension CockpitCalendarScale {
    var cockpitTitle: String {
        L("cockpit_calendar_\(self.rawValue)")
    }
}

extension CockpitCalendarPeriod {
    func title(calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.timeZone = calendar.timeZone
        style.locale = codexBarLocalizedLocale()
        switch self.scale {
        case .day:
            return spendDashboardLedgerDateText(self.start, timeZone: calendar.timeZone, accessibility: true)
        case .week:
            let last = calendar.date(byAdding: .day, value: -1, to: self.end) ?? self.start
            return L(
                "cockpit_calendar_range",
                spendDashboardLedgerDateText(self.start, timeZone: calendar.timeZone),
                spendDashboardLedgerDateText(last, timeZone: calendar.timeZone))
        case .month:
            return self.start.formatted(style)
        case .quarter:
            return L(
                "cockpit_calendar_quarter_title",
                calendar.component(.year, from: self.start).formatted(
                    .number.grouping(.never).locale(codexBarLocalizedLocale())),
                codexBarLocalizedInteger((calendar.component(.month, from: self.start) - 1) / 3 + 1))
        case .year:
            return calendar.component(.year, from: self.start).formatted(
                .number.grouping(.never).locale(codexBarLocalizedLocale()))
        }
    }
}

struct CockpitCalendarPeriodSummaryView: View {
    let ledger: CockpitCalendarLedger
    let period: CockpitCalendarPeriod
    let metric: CockpitCalendarMetric

    var body: some View {
        GroupBox(L("cockpit_calendar_period_total")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(self.ledger.text(self.ledger.summary(for: self.period), metric: self.metric))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
                Text(L("cockpit_calendar_partial"))
                    .font(.caption).foregroundStyle(.secondary)
                if self.metric == .cost {
                    Text(L("cockpit_calendar_currency_note"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }
}

struct CockpitCalendarPeriodView: View {
    let ledger: CockpitCalendarLedger
    let period: CockpitCalendarPeriod
    let metric: CockpitCalendarMetric
    let selectedDay: Date
    let select: (Date) -> Void

    private var subperiods: [CockpitCalendarPeriod] {
        switch self.period.scale {
        case .day, .week:
            return self.period.days(calendar: self.ledger.calendar).map {
                CockpitCalendarPeriod(containing: $0, scale: .day, calendar: self.ledger.calendar)
            }
        case .month, .quarter, .year:
            var months: [CockpitCalendarPeriod] = []
            var cursor = self.period.start
            while cursor < self.period.end {
                let month = CockpitCalendarPeriod(containing: cursor, scale: .month, calendar: self.ledger.calendar)
                months.append(month)
                guard month.end > cursor else { break }
                cursor = month.end
            }
            return months
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(self.subperiods, id: \.start) { period in
                    self.cell(period)
                }
            }
            Text(L("cockpit_calendar_select_day"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func cell(_ period: CockpitCalendarPeriod) -> some View {
        let selected = period.contains(self.selectedDay)
        let title = period.title(calendar: self.ledger.calendar)
        let value = self.ledger.text(self.ledger.summary(for: period), metric: self.metric)
        return Button { self.select(period.start) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption.weight(.semibold))
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(9)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help("\(title): \(value)")
        .accessibilityValue(L(selected ? "cockpit_ui_calendar_selected" : "cockpit_ui_calendar_unselected"))
    }
}
