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
        accountID: String = "local-machine",
        records: [CockpitComfortRecord],
        calendar: Calendar) -> CockpitFeeling?
    {
        self.record(on: date, providerID: providerID, accountID: accountID, records: records, calendar: calendar)?
            .feeling
    }

    static func record(
        on date: Date,
        providerID: String,
        accountID: String = "local-machine",
        records: [CockpitComfortRecord],
        calendar: Calendar) -> CockpitComfortRecord?
    {
        let key = CockpitCalendar.dateKey(for: date, calendar: calendar)
        return records.filter {
            $0.providerID == providerID && $0.accountID == accountID
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

enum CockpitExperienceMode: String, CaseIterable, Identifiable {
    case quota, tokens

    var id: String {
        self.rawValue
    }

    var title: String {
        L(self == .quota ? "cockpit_comfort_quota_tab" : "cockpit_comfort_tokens_tab")
    }
}

@MainActor
struct CockpitCalendarView: View {
    @State private var usage: CockpitUsageProjection
    @Bindable var planStore: CockpitPlanStore
    private let resetStore: CockpitResetHistoryStore?
    @State private var month: Date
    @State private var selectedDay: Date
    @State private var scale = CockpitCalendarScale.month
    @State private var metric = CockpitCalendarMetric.tokens
    @State private var feelingProvider = UsageProvider.codex
    @State private var experienceMode = CockpitExperienceMode.quota
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

    private var period: CockpitCalendarPeriod {
        CockpitCalendarPeriod(containing: self.month, scale: self.scale, calendar: self.calendar)
    }

    private var ledger: CockpitCalendarLedger {
        CockpitCalendarLedger(model: self.usage.calendarModel, calendar: self.calendar, now: Date())
    }

    private var periodTitle: String {
        self.period.title(calendar: self.calendar)
    }

    var body: some View {
        let ledger = self.ledger
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(self.periodTitle)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button { self.movePeriod(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(L("cockpit_calendar_previous"))
                    Button(L("cockpit_calendar_now")) {
                        let now = Date()
                        self.month = now
                        self.selectedDay = now
                    }
                    Button { self.movePeriod(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(L("cockpit_calendar_next"))
                }
                HStack {
                    Picker(L("cockpit_calendar_scale"), selection: self.$scale) {
                        ForEach(CockpitCalendarScale.allCases) { scale in
                            Text(scale.cockpitTitle).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker(L("cockpit_calendar_metric"), selection: self.$metric) {
                        ForEach(CockpitCalendarMetric.allCases) { metric in
                            Text(metric.title).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                CockpitCalendarPeriodSummaryView(
                    ledger: ledger,
                    period: self.period,
                    metric: self.metric)
                if self.scale != .month {
                    CockpitCalendarPeriodView(
                        ledger: ledger,
                        period: self.period,
                        metric: self.metric,
                        selectedDay: self.selectedDay,
                        select: { self.selectedDay = $0 })
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
                Picker(L("cockpit_comfort_mode"), selection: self.$experienceMode) {
                    ForEach(CockpitExperienceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(L(self.experienceMode == .quota
                        ? "cockpit_comfort_quota_scope" : "cockpit_ui_local_experience_note"))
                    .font(.caption).foregroundStyle(.secondary)
                self.personalStatus
                if self.experienceMode == .quota {
                    self.quotaFeedbackNotice
                }
                if [.month, .quarter, .year].contains(self.scale) {
                    if self.scale != .month {
                        Text(CockpitCalendarPeriod(
                            containing: self.selectedDay,
                            scale: .month,
                            calendar: self.calendar).title(calendar: self.calendar))
                            .font(.headline)
                    }
                    CockpitMonthGridView(
                        calendar: self.calendar,
                        month: self.displayedMonth,
                        selectedDay: self.selectedDay,
                        days: self.calendarDays(ledger: ledger),
                        select: { self.selectedDay = $0 },
                        compact: true,
                        metricText: { ledger.text(on: $0, metric: self.metric) })
                }
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
                if self.experienceMode == .quota {
                    CockpitQuotaComfortChartView(
                        model: CockpitQuotaComfortModel.build(
                            records: self.comfortRecords,
                            providerID: self.feelingProvider.rawValue,
                            accountID: self.experienceAccountID,
                            calendar: self.calendar),
                        records: self.comfortRecords)
                } else {
                    CockpitComfortChartView(
                        model: CockpitComfortModel.build(
                            records: self.comfortRecords,
                            providerID: self.feelingProvider.rawValue,
                            accountID: "local-machine",
                            calendar: self.calendar),
                        records: self.comfortRecords)
                }
            }
            .padding(16)
        }
        .onChange(of: self.scale) { _, _ in
            self.month = self.selectedDay
        }
    }

    private var displayedMonth: Date {
        self.scale == .month ? self.month : self.selectedDay
    }

    private func calendarDays(ledger: CockpitCalendarLedger) -> [Date: CockpitCalendarDay] {
        let eventsByDay = self.resetEventsByDay
        let forecast = self.resetStore?.calendarLocalForecast
        let scheduled = self.resetStore?.pendingCalendarReset?.scheduledFor
        return Dictionary(uniqueKeysWithValues: CockpitCalendarProjection.cells(
            month: self.displayedMonth,
            calendar: self.calendar)
            .compactMap(\.self).map { day in
                (day, CockpitCalendarDay(
                    day: day,
                    tokens: ledger.tokens(on: day).total,
                    feeling: self.feeling(on: day),
                    resetKinds: (eventsByDay[day] ?? []).map(\.kind),
                    hasResetForecast: forecast.map { self.calendar.isDate($0.estimatedAt, inSameDayAs: day) } ?? false,
                    hasScheduledReset: scheduled.map { self.calendar.isDate($0, inSameDayAs: day) } ?? false))
            })
    }

    private var resetEventsByDay: [Date: [CockpitResetEvent]] {
        CockpitResetCalendar.eventsByDay(self.resetStore?.history?.events ?? [], calendar: self.calendar)
    }

    private func movePeriod(_ offset: Int) {
        let next = self.period.shifted(by: offset, calendar: self.calendar)
        self.month = next.start
        self.selectedDay = next.start
    }

    private func feeling(on day: Date) -> CockpitFeeling? {
        CockpitCalendarProjection.feeling(
            on: day,
            providerID: self.feelingProvider.rawValue,
            accountID: self.experienceAccountID,
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
            canRecord: CockpitCalendarProjection.canRecord(on: self.selectedDay, calendar: self.calendar)
                && (self.experienceMode == .tokens || self.hasQuotaAccount),
            errorMessage: self.planStore.errorMessage,
            onSelect: self.selectFeeling,
            onClear: {
                if self.experienceMode == .quota {
                    self.planStore.clearQuotaComfort(
                        for: self.feelingProvider, on: self.selectedDay, calendar: self.calendar)
                } else {
                    self.planStore.clearLocalComfort(
                        for: self.feelingProvider, on: self.selectedDay, calendar: self.calendar)
                }
            },
            compact: true,
            unavailableReason: self.experienceMode == .quota && !self.hasQuotaAccount
                ? L("cockpit_comfort_no_account") : nil)
    }

    private var experienceAccountID: String {
        self.experienceMode == .quota ? self.planStore.accountID(for: self.feelingProvider) : "local-machine"
    }

    private var hasQuotaAccount: Bool {
        self.planStore.availableProviders.contains(self.feelingProvider)
    }

    @ViewBuilder
    private var quotaFeedbackNotice: some View {
        if self.hasQuotaAccount {
            let record = CockpitCalendarProjection.record(
                on: self.selectedDay,
                providerID: self.feelingProvider.rawValue,
                accountID: self.experienceAccountID,
                records: self.comfortRecords,
                calendar: self.calendar)
            let usage = self.planStore.state.quotaComfortUsage(
                providerID: self.feelingProvider.rawValue,
                accountID: self.experienceAccountID,
                on: self.selectedDay,
                calendar: self.calendar)
            let captured = record?.usedPercent != nil && record?.coverage != .unavailable
            let used = captured ? record?.usedPercent : usage.usedPercent
            let coverage = captured ? record?.coverage : usage.coverage
            if let used {
                Text("\(L("cockpit_comfort_curve_x")) · \(cockpitLocalizedPercent(used))")
                    .font(.caption).monospacedDigit()
                if coverage == .partial {
                    Text(L("cockpit_comfort_quota_partial"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("cockpit_comfort_quota_missing"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func selectFeeling(_ feeling: CockpitFeeling) {
        let now = Date()
        let calendar = self.calendar
        guard CockpitCalendarProjection.canRecord(on: self.selectedDay, now: now, calendar: calendar) else { return }
        if self.experienceMode == .quota {
            self.planStore.setQuotaComfortFeeling(
                feeling, for: self.feelingProvider, on: self.selectedDay, now: now, calendar: calendar)
            return
        }
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
            $0.providerID == self.feelingProvider.rawValue && $0.accountID == self.experienceAccountID
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
    var unavailableReason: String?

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
                    Label(
                        self.unavailableReason ?? L("cockpit_ui_calendar_future"),
                        systemImage: "calendar.badge.exclamationmark")
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
