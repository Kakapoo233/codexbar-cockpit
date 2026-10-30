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

    static func canRecord(on date: Date, now: Date = Date(), calendar: Calendar) -> Bool {
        calendar.startOfDay(for: date) <= calendar.startOfDay(for: now)
    }

    static func feeling(
        on date: Date,
        providerID: String,
        records: [CockpitComfortRecord],
        calendar: Calendar) -> CockpitFeeling?
    {
        self.record(on: date, providerID: providerID, records: records, calendar: calendar)?.feeling
    }

    static func record(
        on date: Date,
        providerID: String,
        records: [CockpitComfortRecord],
        calendar: Calendar) -> CockpitComfortRecord?
    {
        let key = CockpitCalendar.dateKey(for: date, calendar: calendar)
        return records.filter {
            $0.providerID == providerID && $0.accountID == "local-machine"
                && $0.timeZoneIdentifier == calendar.timeZone.identifier && $0.localDateKey == key
        }.max { $0.recordedAt < $1.recordedAt }
    }

    static func canCaptureTokens(
        on date: Date,
        now: Date,
        existingRecord: CockpitComfortRecord?,
        calendar: Calendar) -> Bool
    {
        calendar.isDate(date, inSameDayAs: now)
            && !(existingRecord?.coverage == .complete && existingRecord?.totalTokens != nil)
    }
}

@MainActor
struct CockpitCalendarView: View {
    @State private var usage: CockpitUsageProjection
    @Bindable var planStore: CockpitPlanStore
    private let resetStore: CockpitResetHistoryStore?
    @State private var month: Date
    @State private var selectedDay: Date
    @State private var feelingProvider = UsageProvider.codex
    private let todayTokens: @MainActor (UsageProvider, Calendar) -> Int?

    init(
        controller: SpendDashboardController,
        planStore: CockpitPlanStore,
        resetStore: CockpitResetHistoryStore? = nil,
        todayTokens: @escaping @MainActor (UsageProvider, Calendar) -> Int? = { _, _ in nil })
    {
        let now = Date()
        self._usage = State(initialValue: CockpitUsageProjection(controller: controller))
        self.planStore = planStore
        self.resetStore = resetStore
        self._month = State(initialValue: now)
        self._selectedDay = State(initialValue: now)
        self.todayTokens = todayTokens
    }

    private var calendar: Calendar {
        self.usage.calendar
    }

    private var monthTitle: String {
        var style = Date.FormatStyle.dateTime.year().month(.wide)
        style.timeZone = self.calendar.timeZone
        style.locale = codexBarLocalizedLocale()
        return self.month.formatted(style)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(self.monthTitle)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button { self.moveMonth(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L("cockpit_ui_previous_month"))
                    Button(L("cockpit_ui_current_month")) {
                        let now = Date()
                        self.month = now
                        self.selectedDay = now
                    }
                    Button { self.moveMonth(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(L("cockpit_ui_next_month"))
                }
                Text(L("cockpit_ui_calendar_zone", self.calendar.timeZone.identifier))
                    .font(.caption).foregroundStyle(.secondary)
                if let resetStore {
                    CockpitResetSummaryView(store: resetStore, calendar: self.calendar) { date in
                        self.month = date
                        self.selectedDay = date
                    }
                }
                HStack {
                    Text(spendDashboardLedgerDateText(
                        self.selectedDay,
                        timeZone: self.calendar.timeZone,
                        accessibility: true))
                        .font(.headline)
                    Spacer()
                    Picker(L("cockpit_ui_feeling_records"), selection: self.$feelingProvider) {
                        ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                            Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
                                .tag(provider)
                        }
                    }
                    .frame(width: 200)
                }
                self.personalStatus
                CockpitMonthGridView(
                    calendar: self.calendar,
                    month: self.month,
                    selectedDay: self.selectedDay,
                    days: self.calendarDays,
                    select: { self.selectedDay = $0 },
                    compact: true)
                Text(L("cockpit_ui_calendar_subjective_note"))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                if let resetStore {
                    CockpitResetDayDetails(
                        events: self.resetEventsByDay[self.calendar.startOfDay(for: self.selectedDay)] ?? [],
                        forecast: resetStore.calendarLocalForecast,
                        selectedDay: self.selectedDay,
                        calendar: self.calendar,
                        scheduled: resetStore.pendingCalendarReset)
                }
                self.dayDetails
                Text(L("cockpit_ui_local_experience_note"))
                    .font(.caption).foregroundStyle(.secondary)
                CockpitComfortChartView(
                    model: CockpitComfortModel.build(
                        records: self.comfortRecords,
                        providerID: self.feelingProvider.rawValue,
                        accountID: "local-machine",
                        calendar: self.calendar),
                    records: self.comfortRecords)
            }
            .padding(16)
        }
    }

    private var calendarDays: [Date: CockpitCalendarDay] {
        let eventsByDay = self.resetEventsByDay
        let forecast = self.resetStore?.calendarLocalForecast
        let scheduled = self.resetStore?.pendingCalendarReset?.scheduledFor
        return Dictionary(uniqueKeysWithValues: CockpitCalendarProjection.cells(
            month: self.month,
            calendar: self.calendar)
            .compactMap(\.self).map { day in
                (day, CockpitCalendarDay(
                    day: day,
                    tokens: self.tokens(on: day),
                    feeling: self.feeling(on: day),
                    resetKinds: (eventsByDay[day] ?? []).map(\.kind),
                    hasResetForecast: forecast.map { self.calendar.isDate($0.estimatedAt, inSameDayAs: day) } ?? false,
                    hasScheduledReset: scheduled.map { self.calendar.isDate($0, inSameDayAs: day) } ?? false))
            })
    }

    private var resetEventsByDay: [Date: [CockpitResetEvent]] {
        CockpitResetCalendar.eventsByDay(self.resetStore?.history?.events ?? [], calendar: self.calendar)
    }

    private func moveMonth(_ offset: Int) {
        if let month = self.calendar.date(byAdding: .month, value: offset, to: self.month) {
            self.month = month
        }
    }

    private func tokens(on day: Date) -> Int? {
        let summaries = self.usage.calendarModel.groups.compactMap { group in
            group.dailySummaries.first { self.calendar.isDate($0.day, inSameDayAs: day) }
        }
        if summaries.isEmpty {
            return self.usage.calendarModel.tokenActivity.first {
                self.calendar.isDate($0.day, inSameDayAs: day)
            }?.totalTokens
        }
        guard summaries.count == self.usage.calendarModel.groups.count,
              summaries.allSatisfy({ $0.totalTokens != nil && !$0.hasPartialCounts })
        else { return nil }
        return CheckedSum.integers(summaries.compactMap(\.totalTokens))
    }

    private func feeling(on day: Date) -> CockpitFeeling? {
        CockpitCalendarProjection.feeling(
            on: day,
            providerID: self.feelingProvider.rawValue,
            records: self.planStore.state.comfortRecords,
            calendar: self.calendar)
    }

    private var dayDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.usage.calendarModel.groups.isEmpty {
                Text(L("cockpit_ui_no_local_usage"))
                    .foregroundStyle(.secondary)
            }
            ForEach(self.usage.calendarModel.groups) { group in
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

    private var personalStatus: some View {
        CockpitCalendarStatusEditor(
            selected: self.feeling(on: self.selectedDay),
            canRecord: CockpitCalendarProjection.canRecord(on: self.selectedDay, calendar: self.calendar),
            errorMessage: self.planStore.errorMessage,
            onSelect: self.selectFeeling,
            onClear: {
                self.planStore.clearLocalComfort(
                    for: self.feelingProvider,
                    on: self.selectedDay,
                    calendar: self.calendar)
            },
            compact: true)
    }

    private func selectFeeling(_ feeling: CockpitFeeling) {
        let now = Date()
        let calendar = self.calendar
        guard CockpitCalendarProjection.canRecord(on: self.selectedDay, now: now, calendar: calendar) else { return }
        let existing = CockpitCalendarProjection.record(
            on: self.selectedDay,
            providerID: self.feelingProvider.rawValue,
            records: self.planStore.state.comfortRecords,
            calendar: calendar)
        // Only the root's validated provider-specific device snapshot may supply a new measurement.
        if CockpitCalendarProjection.canCaptureTokens(
            on: self.selectedDay,
            now: now,
            existingRecord: existing,
            calendar: calendar),
            let tokens = self.todayTokens(self.feelingProvider, calendar),
            calendar.isDate(now, inSameDayAs: Date())
        {
            self.planStore.recordLocalComfort(
                feeling,
                for: self.feelingProvider,
                on: now,
                totalTokens: tokens,
                coverage: .complete,
                calendar: calendar)
        } else {
            self.planStore.setLocalComfortFeeling(
                feeling,
                for: self.feelingProvider,
                on: self.selectedDay,
                calendar: calendar)
        }
    }

    private var comfortRecords: [CockpitComfortRecord] {
        self.planStore.state.comfortRecords.filter {
            $0.providerID == self.feelingProvider.rawValue && $0.accountID == "local-machine"
                && $0.timeZoneIdentifier == self.calendar.timeZone.identifier
        }.sorted { $0.recordedAt > $1.recordedAt }
    }
}

/// Pure-input editor shared by the live calendar and synthetic UI acceptance renders.
struct CockpitCalendarStatusEditor: View {
    let selected: CockpitFeeling?
    let canRecord: Bool
    var errorMessage: String?
    let onSelect: (CockpitFeeling) -> Void
    let onClear: () -> Void
    var compact = false

    var body: some View {
        GroupBox(L("cockpit_ui_calendar_personal_status")) {
            VStack(alignment: .leading, spacing: 12) {
                if !self.compact {
                    Text(L("cockpit_ui_calendar_subjective_note"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ForEach([CockpitFeeling.light, .comfortable, .overloaded], id: \.self) { feeling in
                        self.statusButton(feeling, selected: self.selected == feeling)
                            .disabled(!self.canRecord)
                    }
                    if self.compact { self.clearButton }
                }
                if !self.compact { self.clearButton }
                if !self.canRecord {
                    Label(L("cockpit_ui_calendar_future"), systemImage: "calendar.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = self.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(8)
        }
    }

    private var clearButton: some View {
        Button(L("cockpit_ui_calendar_clear")) { self.onClear() }
            .disabled(!self.canRecord || self.selected == nil)
    }

    private func statusButton(_ feeling: CockpitFeeling, selected: Bool) -> some View {
        Button {
            guard self.canRecord else { return }
            self.onSelect(feeling)
        } label: {
            Label(feeling.calendarTitle, systemImage: selected ? "checkmark.circle.fill" : feeling.cockpitSymbol)
                .frame(maxWidth: .infinity)
                .padding(.vertical, self.compact ? 6 : 10)
                .background(
                    selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(L(selected ? "cockpit_ui_calendar_selected" : "cockpit_ui_calendar_unselected"))
    }
}

extension CockpitFeeling {
    var calendarTitle: String {
        self == .overloaded ? L("cockpit_ui_calendar_overloaded") : self.cockpitTitle
    }
}
