import CodexBarCore
import Foundation
import SwiftUI

struct CockpitCalendarDay: Identifiable, Equatable {
    let day: Date
    let tokens: Int?
    let feeling: CockpitFeeling?
    var resetKinds: [CockpitResetKind] = []
    var hasResetForecast = false
    var hasScheduledReset = false
    var id: Date {
        self.day
    }
}

struct CockpitMonthGridView: View {
    let calendar: Calendar
    let month: Date
    let selectedDay: Date
    let days: [Date: CockpitCalendarDay]
    let select: (Date) -> Void
    var compact = false
    var metricText: ((Date) -> String)?

    private var weekdaySymbols: [String] {
        var labelsCalendar = self.calendar
        labelsCalendar.locale = codexBarLocalizedLocale()
        let symbols = labelsCalendar.shortWeekdaySymbols
        let offset = self.calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                }
            }
            Divider()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(Array(CockpitCalendarProjection.cells(month: self.month, calendar: self.calendar)
                        .enumerated()), id: \.offset)
                { _, day in
                    if let day {
                        CockpitCalendarDateCell(
                            calendar: self.calendar,
                            day: day,
                            selectedDay: self.selectedDay,
                            model: self.days[day],
                            metricText: self.metricText?(day),
                            minimumHeight: self.compact ? 96 : 156,
                            compact: self.compact,
                            select: self.select)
                    } else {
                        Color.primary.opacity(0.018)
                            .frame(height: self.compact ? 96 : 156)
                            .modifier(CockpitCalendarCellBorder())
                    }
                }
            }
        }
        .modifier(CockpitCalendarSurface())
    }
}

/// Shared date treatment for the day, week and month views. The ledger is daily, so no hourly axis is implied.
struct CockpitCalendarDateCell: View {
    let calendar: Calendar
    let day: Date
    let selectedDay: Date
    let model: CockpitCalendarDay?
    var metricText: String?
    var minimumHeight: CGFloat = 156
    var compact = false
    var showsWeekday = false
    let select: (Date) -> Void

    private var selected: Bool {
        self.calendar.isDate(self.day, inSameDayAs: self.selectedDay)
    }

    private var today: Bool {
        self.calendar.isDateInToday(self.day)
    }

    private var value: String {
        self.metricText ?? self.model?.tokens.map(UsageFormatter.tokenCountString) ?? "—"
    }

    private var weekday: String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated)
        style.timeZone = self.calendar.timeZone
        style.locale = codexBarLocalizedLocale()
        return self.day.formatted(style)
    }

    var body: some View {
        Button { self.select(self.day) } label: {
            VStack(alignment: .leading, spacing: self.compact ? 5 : 10) {
                HStack(spacing: 6) {
                    if self.showsWeekday {
                        Text(self.weekday)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(self.today ? Color.red : .secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(codexBarLocalizedInteger(self.calendar.component(.day, from: self.day)))
                        .font(.system(size: self.compact ? 12 : 15, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(self.today || self.selected ? Color.white : Color.primary)
                        .frame(width: self.compact ? 24 : 29, height: self.compact ? 24 : 29)
                        .background {
                            if self.today || self.selected {
                                Circle().fill(self.today ? Color.red : Color.accentColor)
                            }
                        }
                }
                Text(self.value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(self.compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if self.compact {
                    HStack(alignment: .top, spacing: 4) {
                        if let feeling = self.model?.feeling {
                            Text(feeling.cockpitEmoji).font(.caption2).accessibilityHidden(true)
                        }
                        if let model = self.model {
                            CockpitCalendarResetMarkers(model: model, compact: true)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    if let feeling = self.model?.feeling {
                        HStack(spacing: 4) {
                            Text(feeling.cockpitEmoji).accessibilityHidden(true)
                            Text(feeling.calendarTitle).foregroundStyle(.secondary)
                        }
                        .font(.caption2)
                        .lineLimit(1)
                    }
                    if let model = self.model {
                        CockpitCalendarResetMarkers(model: model, compact: false)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(self.compact ? 7 : 11)
            .frame(maxWidth: .infinity)
            .frame(
                minHeight: self.minimumHeight,
                maxHeight: self.compact ? self.minimumHeight : nil,
                alignment: .topLeading)
            .clipped()
            .background(self.selected ? Color.accentColor.opacity(0.055) : Color.clear)
            .contentShape(Rectangle())
            .modifier(CockpitCalendarCellBorder())
        }
        .buttonStyle(.plain)
        .help(self.dayLabel)
        .accessibilityLabel(self.dayLabel)
        .accessibilityValue(L(self.selected ? "cockpit_ui_calendar_selected" : "cockpit_ui_calendar_unselected"))
        .accessibilityAddTraits(self.selected ? .isSelected : [])
    }

    private var dayLabel: String {
        let date = spendDashboardLedgerDateText(self.day, timeZone: self.calendar.timeZone, accessibility: true)
        var parts = [date, self.value]
        if let model = self.model {
            if let feeling = model.feeling { parts.append(feeling.calendarTitle) }
            parts += model.resetKinds.map(\.cockpitTitle)
            if model.hasResetForecast { parts.append(L("cockpit_reset_estimate")) }
            if model.hasScheduledReset { parts.append(L("cockpit_reset_scheduled")) }
        }
        return parts.joined(separator: ", ")
    }
}

private struct CockpitCalendarResetMarkers: View {
    let model: CockpitCalendarDay
    let compact: Bool

    private struct Marker: Identifiable {
        let id: String
        let symbol: String
        let color: Color
    }

    private var markers: [Marker] {
        var result: [Marker] = []
        if self.model.resetKinds.contains(.regular) {
            result.append(Marker(
                id: "cockpit_reset_regular", symbol: "arrow.counterclockwise.circle.fill", color: .blue))
        }
        if self.model.resetKinds.contains(.banked) {
            result.append(Marker(id: "cockpit_reset_banked", symbol: "archivebox.fill", color: .purple))
        }
        if self.model.resetKinds.contains(where: {
            if case .unknown = $0 {
                true
            } else {
                false
            }
        }) {
            result.append(Marker(id: "cockpit_reset_other", symbol: "questionmark.circle", color: .secondary))
        }
        if self.model.hasResetForecast {
            result.append(Marker(id: "cockpit_reset_estimate", symbol: "clock.badge.questionmark", color: .orange))
        }
        if self.model.hasScheduledReset {
            result.append(Marker(id: "cockpit_reset_scheduled", symbol: "calendar.badge.clock", color: .teal))
        }
        return result
    }

    var body: some View {
        let markers = self.markers
        Group {
            if self.compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        ForEach(markers) { marker in
                            Image(systemName: marker.symbol).foregroundStyle(marker.color)
                        }
                    }
                    if let first = markers.first {
                        HStack(spacing: 3) {
                            Image(systemName: first.symbol).foregroundStyle(first.color)
                            if markers.count > 1 {
                                Text("+\(codexBarLocalizedInteger(markers.count - 1))")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(markers) { self.markerLabel($0) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(markers) { self.markerLabel($0) }
                    }
                }
            }
        }
        .font(.caption2)
        .accessibilityHidden(true)
    }

    private func markerLabel(_ marker: Marker) -> some View {
        Label(L(marker.id), systemImage: marker.symbol)
            .foregroundStyle(marker.color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CockpitCalendarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

struct CockpitCalendarCellBorder: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.5) }
            .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 0.5) }
    }
}
