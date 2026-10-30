import CodexBarCore
import Foundation
import SwiftUI

enum CockpitCalendarProjection {
    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    /// Calendar arithmetic keeps days aligned through DST and respects the locale's first weekday.
    static func cells(month: Date, calendar: Calendar) -> [Date?] {
        let start = self.monthStart(containing: month, calendar: calendar)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        var cells = [Date?](repeating: nil, count: leading)
        cells += range.compactMap { day in calendar.date(byAdding: .day, value: day - 1, to: start) }
        let trailing = (7 - cells.count % 7) % 7
        return cells + [Date?](repeating: nil, count: trailing)
    }
}

@MainActor
struct CockpitCalendarView: View {
    @Bindable var controller: SpendDashboardController
    @Bindable var planStore: CockpitPlanStore
    @State private var month = Date()
    @State private var selectedDay = Date()
    @State private var feelingProvider = UsageProvider.codex

    private var calendar: Calendar {
        self.controller.configuration?.bucketCalendar ?? .current
    }

    private var monthTitle: String {
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.timeZone = self.calendar.timeZone
        return self.month.formatted(style)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(self.monthTitle)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button { self.moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L("cockpit_ui_previous_month"))
                    Button(L("cockpit_ui_current_month")) { self.month = Date(); self.selectedDay = Date() }
                    Button { self.moveMonth(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(L("cockpit_ui_next_month"))
                }
                Text(L("cockpit_ui_calendar_zone", self.calendar.timeZone.identifier))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L("cockpit_ui_feeling_records"), selection: self.$feelingProvider) {
                    ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                        Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName).tag(provider)
                    }
                }
                .frame(width: 220)
                Text(L("cockpit_ui_local_experience_note")).font(.caption).foregroundStyle(.secondary)
                CockpitMonthGridView(
                    calendar: self.calendar,
                    month: self.month,
                    selectedDay: self.selectedDay,
                    days: self.calendarDays,
                    select: { self.selectedDay = $0 })
                Divider()
                self.dayDetails
            }
            .padding(24)
        }
        .onAppear {
            self.controller.selectPeriod(.allTime)
        }
    }

    private var calendarDays: [Date: CockpitCalendarDay] {
        Dictionary(uniqueKeysWithValues: CockpitCalendarProjection.cells(month: self.month, calendar: self.calendar)
            .compactMap(\.self).map { day in
                (day, CockpitCalendarDay(day: day, tokens: self.tokens(on: day), feeling: self.feeling(on: day)))
            })
    }

    private func moveMonth(_ offset: Int) {
        if let month = self.calendar.date(byAdding: .month, value: offset, to: self.month) {
            self.month = month
        }
    }

    private func tokens(on day: Date) -> Int? {
        let summaries = self.controller.model.groups.compactMap { group in
            group.dailySummaries.first { self.calendar.isDate($0.day, inSameDayAs: day) }
        }
        if summaries.isEmpty {
            return self.controller.model.tokenActivity.first {
                self.calendar.isDate($0.day, inSameDayAs: day)
            }?.totalTokens
        }
        guard summaries.count == self.controller.model.groups.count,
              summaries.allSatisfy({ $0.totalTokens != nil && !$0.hasPartialCounts })
        else { return nil }
        return CheckedSum.integers(summaries.compactMap(\.totalTokens))
    }

    private func feeling(on day: Date) -> CockpitFeeling? {
        self.planStore.state.status(
            providerID: self.feelingProvider.rawValue,
            accountID: "local-machine",
            on: day,
            calendar: self.calendar).feeling
    }

    private var dayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spendDashboardLedgerDateText(self.selectedDay, timeZone: self.calendar.timeZone, accessibility: true))
                .font(.headline)
            if let feeling = self.feeling(on: self.selectedDay) {
                Label(L("cockpit_ui_feeling_value", feeling.cockpitTitle), systemImage: feeling.cockpitSymbol)
                    .foregroundStyle(.secondary)
            }
            if self.controller.model.groups.isEmpty {
                Text(L("cockpit_ui_no_local_usage"))
                    .foregroundStyle(.secondary)
            }
            ForEach(self.controller.model.groups) { group in
                if let summary = group.dailySummaries.first(where: {
                    self.calendar.isDate($0.day, inSameDayAs: self.selectedDay)
                }) {
                    GroupBox(group.currencyCode) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(summary.providers) { provider in
                                HStack {
                                    Text(provider.displayName)
                                    Spacer()
                                    Text(spendDashboardBreakdownMetricText(
                                        cost: provider.totalCost,
                                        tokens: provider.totalTokens,
                                        currencyCode: group.currencyCode,
                                        hasPartialCost: provider.costIsLowerBound,
                                        hasPartialTokens: provider.countsAreLowerBound,
                                        incompleteRequestCount: provider.incompleteRequestCount))
                                        .monospacedDigit()
                                }
                            }
                        }
                        .padding(6)
                    }
                } else {
                    Text(L("cockpit_ui_currency_no_day", group.currencyCode))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
