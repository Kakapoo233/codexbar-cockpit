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
        VStack(alignment: .leading, spacing: 6) {
            Text(L("cockpit_calendar_period_total"))
                .font(CockpitCalendarTypography.caption.weight(.medium)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(self.ledger.text(self.ledger.summary(for: self.period), metric: self.metric))
                    .font(CockpitCalendarTypography.title3.monospacedDigit().weight(.semibold))
                    .textSelection(.enabled)
                Text(L("cockpit_calendar_partial"))
                    .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                if self.metric == .cost {
                    Text(L("cockpit_calendar_currency_note"))
                        .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .modifier(CockpitCalendarSurface())
    }
}

struct CockpitCalendarPeriodView: View {
    let ledger: CockpitCalendarLedger
    let period: CockpitCalendarPeriod
    let metric: CockpitCalendarMetric
    let selectedDay: Date
    let select: (Date) -> Void
    var days: [Date: CockpitCalendarDay] = [:]

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
            if self.period.scale == .day {
                self.dateStrip(minimumHeight: 160)
            } else if self.period.scale == .week {
                ViewThatFits(in: .horizontal) {
                    self.dateStrip(minimumHeight: 176).frame(minWidth: 560)
                    ScrollView(.horizontal) {
                        self.dateStrip(minimumHeight: 176).frame(width: 560)
                    }
                    .frame(height: 176)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 0)], spacing: 0) {
                    ForEach(self.subperiods, id: \.start) { period in
                        self.cell(period)
                    }
                }
                .modifier(CockpitCalendarSurface())
            }
            Text(L("cockpit_calendar_select_day"))
                .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
        }
    }

    private func dateStrip(minimumHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(self.subperiods, id: \.start) { period in
                CockpitCalendarDateCell(
                    calendar: self.ledger.calendar,
                    day: period.start,
                    selectedDay: self.selectedDay,
                    model: self.days[period.start],
                    metricText: self.ledger.text(on: period.start, metric: self.metric),
                    minimumHeight: minimumHeight,
                    compact: self.period.scale == .week,
                    showsWeekday: true,
                    select: self.select)
            }
        }
        .modifier(CockpitCalendarSurface())
    }

    private func cell(_ period: CockpitCalendarPeriod) -> some View {
        let selected = period.contains(self.selectedDay)
        let title = period.title(calendar: self.ledger.calendar)
        let value = self.ledger.text(self.ledger.summary(for: period), metric: self.metric)
        return Button { self.select(period.start) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(CockpitCalendarTypography.caption.weight(.semibold))
                Text(value).font(CockpitCalendarTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(9)
            .background(selected ? Color.accentColor.opacity(0.055) : Color.clear)
            .modifier(CockpitCalendarCellBorder())
        }
        .buttonStyle(.plain)
        .help("\(title): \(value)")
        .accessibilityValue(L(selected ? "cockpit_ui_calendar_selected" : "cockpit_ui_calendar_unselected"))
    }
}

/// The same controls stay below the pinned reset announcement for every calendar scale.
struct CockpitCalendarToolbar: View {
    let title: String
    @Binding var scale: CockpitCalendarScale
    @Binding var metric: CockpitCalendarMetric
    let previous: () -> Void
    let today: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CockpitCalendarPicker(
                selection: self.$scale,
                choices: CockpitCalendarScale.allCases,
                title: { $0.cockpitTitle },
                label: L("cockpit_calendar_scale"))
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    self.periodTitle
                    Spacer(minLength: 12)
                    self.navigation
                    self.metricPicker
                }
                VStack(alignment: .leading, spacing: 10) {
                    self.periodTitle
                    HStack {
                        self.navigation
                        Spacer(minLength: 12)
                        self.metricPicker
                    }
                }
            }
        }
        .font(CockpitCalendarTypography.body)
        .accessibilityIdentifier("cockpit-calendar-toolbar")
    }

    private var periodTitle: some View {
        Text(self.title)
            .font(CockpitCalendarTypography.font(size: 23, weight: .semibold))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            Button(action: self.previous) { Image(systemName: "chevron.left") }
                .accessibilityLabel(L("cockpit_calendar_previous"))
            Button(L("cockpit_calendar_now"), action: self.today)
            Button(action: self.next) { Image(systemName: "chevron.right") }
                .accessibilityLabel(L("cockpit_calendar_next"))
        }
        .font(CockpitCalendarTypography.smallControl)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .fixedSize()
    }

    private var metricPicker: some View {
        CockpitCalendarPicker(
            selection: self.$metric,
            choices: CockpitCalendarMetric.allCases,
            title: { $0.title },
            label: L("cockpit_calendar_metric"))
            .frame(width: 150)
    }
}
