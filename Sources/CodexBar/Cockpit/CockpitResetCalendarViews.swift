import CodexBarCore
import SwiftUI

extension CockpitResetKind {
    var cockpitTitle: String {
        switch self {
        case .regular: L("cockpit_reset_regular")
        case .banked: L("cockpit_reset_banked")
        case .unknown: L("cockpit_reset_other")
        }
    }
}

func cockpitResetDateText(_ date: Date, calendar: Calendar) -> String {
    var style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
    style.timeZone = calendar.timeZone
    style.locale = codexBarLocalizedLocale()
    return date.formatted(style)
}

@MainActor
extension CockpitResetHistoryStore {
    var pendingCalendarReset: CockpitScheduledReset? {
        self.status?.scheduledReset.flatMap { $0.isPending(at: Date()) ? $0 : nil }
    }

    var activeCalendarWatch: CockpitResetWatch? {
        self.status?.activeWatch.flatMap { $0.isActive(at: Date()) ? $0 : nil }
    }

    var calendarLocalForecast: CockpitResetForecast? {
        guard self.pendingCalendarReset == nil, self.activeCalendarWatch == nil else { return nil }
        if let latest = self.status?.latestReset, latest.kind == .regular, let forecast = self.forecast,
           latest.id != forecast.anchorEventID, latest.announcedAt > forecast.anchorDate { return nil }
        return self.forecast
    }
}

@MainActor
struct CockpitResetSummaryView: View {
    @Bindable var store: CockpitResetHistoryStore
    let calendar: Calendar
    let selectDate: (Date) -> Void

    var compact = false
    @State private var showsDetails = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("cockpit_reset_history_title")).font(CockpitCalendarTypography.headline)
                    Spacer()
                    Link("Codex Resets ↗", destination: CockpitResetHistoryClient.websiteURL)
                    Button { Task { await self.store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(self.store.isRefreshing)
                    .accessibilityLabel(L("cockpit_reset_sync"))
                    if self.compact {
                        Button {
                            self.showsDetails.toggle()
                        } label: {
                            Image(systemName: self.showsDetails ? "chevron.up" : "chevron.down")
                        }
                        .help(L(self.showsDetails ? "Hide details" : "Show details"))
                        .accessibilityLabel(L(self.showsDetails ? "Hide details" : "Show details"))
                    }
                }
                if self.compact {
                    self.compactNotice
                    if let error = self.store.errorMessage ?? self.store.statusErrorMessage {
                        Text(error).font(CockpitCalendarTypography.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                    if self.showsDetails {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                self.syncStatus
                                self.notice
                                self.legend
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: CockpitCalendarTypography.scaled(150))
                    }
                } else {
                    self.syncStatus
                    self.notice
                    self.legend
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
        .font(CockpitCalendarTypography.body)
        .accessibilityIdentifier("cockpit-reset-summary")
    }

    @ViewBuilder
    private var compactNotice: some View {
        if let scheduled = self.store.pendingCalendarReset {
            HStack(alignment: .firstTextBaseline) {
                Label(L("cockpit_reset_scheduled"), systemImage: "calendar.badge.clock")
                    .foregroundStyle(.teal)
                if let date = scheduled.scheduledFor {
                    Button(cockpitResetDateText(date, calendar: self.calendar)) { self.selectDate(date) }
                        .buttonStyle(.link)
                } else {
                    Text(L("cockpit_reset_scheduled_unspecified"))
                }
                Spacer(minLength: 0)
                Link(L("cockpit_reset_original"), destination: scheduled.sourceURL)
            }
            .font(CockpitCalendarTypography.caption)
            if let date = scheduled.scheduledFor, date <= Date() {
                Text(L("cockpit_reset_scheduled_overdue")).font(CockpitCalendarTypography.caption)
                    .foregroundStyle(.orange)
            }
        } else if let watch = self.store.activeCalendarWatch {
            Label("\(L("cockpit_reset_watch_title")) · \(watch.forecastWindow)", systemImage: "binoculars.fill")
                .font(CockpitCalendarTypography.caption).foregroundStyle(.orange).lineLimit(2)
        } else if let forecast = self.store.calendarLocalForecast {
            Button { self.selectDate(forecast.estimatedAt) } label: {
                Label(L("cockpit_reset_forecast_date", cockpitResetDateText(
                    forecast.estimatedAt, calendar: self.calendar)), systemImage: "clock.badge.questionmark")
            }
            .buttonStyle(.plain).font(CockpitCalendarTypography.caption).foregroundStyle(.orange)
            if forecast.isOverdue(at: Date()) {
                Text(L("cockpit_reset_forecast_overdue")).font(CockpitCalendarTypography.caption)
                    .foregroundStyle(.secondary).lineLimit(2)
            }
        } else {
            Text(L("cockpit_reset_forecast_unavailable")).font(CockpitCalendarTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        if self.store.isRefreshing {
            Text(L("cockpit_reset_syncing")).font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
        } else if let synced = self.store.lastSyncedAt {
            Text(L(
                "cockpit_reset_sync_status",
                codexBarLocalizedInteger(self.store.history?.events.count ?? 0),
                cockpitResetDateText(synced, calendar: self.calendar)))
                .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
        } else {
            Text(L("cockpit_reset_not_synced")).font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
        }
        if let checked = self.store.lastStatusSyncedAt {
            Text(L("cockpit_reset_status_checked", cockpitResetDateText(checked, calendar: self.calendar)))
                .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
        }
        if let error = self.store.errorMessage ?? self.store.statusErrorMessage {
            Text(error).font(CockpitCalendarTypography.caption).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var notice: some View {
        if let scheduled = self.store.pendingCalendarReset {
            CockpitScheduledResetView(reset: scheduled, calendar: self.calendar, selectDate: self.selectDate)
        } else if let watch = self.store.activeCalendarWatch {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("cockpit_reset_watch_title"), systemImage: "binoculars.fill")
                    .font(CockpitCalendarTypography.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Text(watch.forecastWindow).font(CockpitCalendarTypography.callout)
                Text(L("cockpit_reset_watch_note", cockpitResetDateText(watch.expiresAt, calendar: self.calendar)))
                    .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                Link(L("cockpit_reset_original"), destination: watch.sourceURL).font(CockpitCalendarTypography.caption)
            }
        } else if let forecast = self.store.calendarLocalForecast {
            HStack(alignment: .top) {
                Label(L("cockpit_reset_forecast_date", cockpitResetDateText(
                    forecast.estimatedAt, calendar: self.calendar)), systemImage: "clock.badge.questionmark")
                    .font(CockpitCalendarTypography.subheadline.weight(.semibold)).foregroundStyle(.orange)
                Button(L("cockpit_reset_show_date")) { self.selectDate(forecast.estimatedAt) }
                    .buttonStyle(.borderless).font(CockpitCalendarTypography.body)
            }
            Text(L("cockpit_reset_forecast_basis", codexBarLocalizedInteger(forecast.sampleCount)))
                .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
            if forecast.isOverdue(at: Date()) {
                Text(L("cockpit_reset_forecast_overdue")).font(CockpitCalendarTypography.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            Text(L("cockpit_reset_forecast_unavailable")).font(CockpitCalendarTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var legend: some View {
        if let error = self.store.notificationErrorMessage {
            Text(error).font(CockpitCalendarTypography.caption).foregroundStyle(.orange)
        }
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
            alignment: .leading,
            spacing: 8)
        {
            Label(L("cockpit_reset_regular"), systemImage: "arrow.counterclockwise.circle.fill")
                .foregroundStyle(.blue)
            Label(L("cockpit_reset_banked"), systemImage: "archivebox.fill").foregroundStyle(.purple)
            Label(L("cockpit_reset_estimate"), systemImage: "clock.badge.questionmark").foregroundStyle(.orange)
            Label(L("cockpit_reset_scheduled"), systemImage: "calendar.badge.clock").foregroundStyle(.teal)
        }
        .font(CockpitCalendarTypography.caption)
        Text(L("cockpit_reset_history_note")).font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
    }
}

@MainActor
struct CockpitResetDayDetails: View {
    let events: [CockpitResetEvent]
    let forecast: CockpitResetForecast?
    let selectedDay: Date
    let calendar: Calendar
    var scheduled: CockpitScheduledReset?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let scheduled, let date = scheduled.scheduledFor,
               self.calendar.isDate(date, inSameDayAs: self.selectedDay)
            {
                CockpitScheduledResetView(reset: scheduled, calendar: self.calendar, selectDate: { _ in })
            }
            if let forecast, self.calendar.isDate(forecast.estimatedAt, inSameDayAs: self.selectedDay) {
                Label(
                    L("cockpit_reset_forecast_date", cockpitResetDateText(
                        forecast.estimatedAt,
                        calendar: self.calendar)),
                    systemImage: "clock.badge.questionmark")
                    .foregroundStyle(.orange)
                Text(L("cockpit_reset_forecast_basis", codexBarLocalizedInteger(forecast.sampleCount)))
                    .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
            }
            ForEach(self.events) { event in
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.kind.cockpitTitle).font(CockpitCalendarTypography.subheadline.weight(.semibold))
                            Text(cockpitResetDateText(event.announcedAt, calendar: self.calendar))
                                .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                            if event.sourceURL != CockpitResetHistoryClient.websiteURL {
                                Link(L("cockpit_reset_original"), destination: event.sourceURL)
                            }
                        }
                        Text(event.text).font(CockpitCalendarTypography.callout).textSelection(.enabled)
                        HStack {
                            Text(L(event.sourceType == "observed"
                                    ? "cockpit_reset_observed_source" : "cockpit_reset_announcement_source"))
                            Spacer()
                            Link("Codex Resets ↗", destination: CockpitResetHistoryClient.websiteURL)
                        }
                        .font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
            }
        }
        .font(CockpitCalendarTypography.body)
        .accessibilityIdentifier("cockpit-reset-day-details")
    }
}

@MainActor
private struct CockpitScheduledResetView: View {
    let reset: CockpitScheduledReset
    let calendar: Calendar
    let selectDate: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("cockpit_reset_scheduled"), systemImage: "calendar.badge.clock")
                    .font(CockpitCalendarTypography.subheadline.weight(.semibold)).foregroundStyle(.teal)
                Text(self.reset.kind.cockpitTitle).font(CockpitCalendarTypography.caption).foregroundStyle(.secondary)
                if let date = self.reset.scheduledFor {
                    Button(L("cockpit_reset_show_date")) { self.selectDate(date) }
                        .buttonStyle(.borderless).font(CockpitCalendarTypography.body)
                }
            }
            if let date = self.reset.scheduledFor {
                Text(cockpitResetDateText(date, calendar: self.calendar)).font(CockpitCalendarTypography.callout)
                if date <= Date() {
                    Text(L("cockpit_reset_scheduled_overdue")).font(CockpitCalendarTypography.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                Text(L("cockpit_reset_scheduled_unspecified")).font(CockpitCalendarTypography.callout)
            }
            Text(self.reset.text).font(CockpitCalendarTypography.caption)
                .fixedSize(horizontal: false, vertical: true)
            Link(L("cockpit_reset_original"), destination: self.reset.sourceURL).font(CockpitCalendarTypography.caption)
        }
        .font(CockpitCalendarTypography.body)
        .fixedSize(horizontal: false, vertical: true)
    }
}
