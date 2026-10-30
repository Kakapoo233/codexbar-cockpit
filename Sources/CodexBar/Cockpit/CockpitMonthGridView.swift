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

    private var weekdaySymbols: [String] {
        var labelsCalendar = self.calendar
        labelsCalendar.locale = codexBarLocalizedLocale()
        let symbols = labelsCalendar.veryShortWeekdaySymbols
        let offset = self.calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(Array(self.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach(Array(CockpitCalendarProjection.cells(month: self.month, calendar: self.calendar)
                    .enumerated()), id: \.offset)
            { _, day in
                if let day { self.dayCell(day) } else { Color.clear.frame(height: self.compact ? 50 : 86) }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let tokens = self.days[day]?.tokens
        let selected = self.calendar.isDate(day, inSameDayAs: self.selectedDay)
        let dayNumber = self.calendar.component(.day, from: day)
        return Button { self.select(day) } label: {
            VStack(alignment: .leading, spacing: self.compact ? 3 : 7) {
                HStack {
                    Text(dayNumber.formatted()).font(self.compact ? .caption.weight(.medium) : .body.weight(.medium))
                    Spacer(minLength: 0)
                    if self.calendar.isDateInToday(day) {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    }
                }
                HStack {
                    Text(tokens.map(UsageFormatter.tokenCountString) ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if self.compact, let feeling = self.days[day]?.feeling {
                        Spacer(minLength: 0)
                        Image(systemName: feeling.cockpitSymbol).font(.caption2).foregroundStyle(.tint)
                    }
                }
                if !self.compact, let feeling = self.days[day]?.feeling {
                    Text(feeling.calendarTitle).font(.caption2).foregroundStyle(.tint)
                }
                if let model = self.days[day],
                   !model.resetKinds.isEmpty || model.hasResetForecast || model.hasScheduledReset
                {
                    HStack(spacing: 4) {
                        if model.resetKinds.contains(.regular) {
                            Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(.blue)
                        }
                        if model.resetKinds.contains(.banked) {
                            Image(systemName: "archivebox.fill").foregroundStyle(.purple)
                        }
                        if model.resetKinds.contains(where: {
                            if case .unknown = $0 {
                                true
                            } else {
                                false
                            }
                        }) {
                            Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                        }
                        if model.hasResetForecast {
                            Image(systemName: "clock.badge.questionmark").foregroundStyle(.orange)
                        }
                        if model.hasScheduledReset {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(.teal)
                        }
                    }
                    .font(.caption2)
                }
            }
            .padding(self.compact ? 6 : 9)
            .frame(maxWidth: .infinity, minHeight: self.compact ? 50 : 86, alignment: .topLeading)
            .background(selected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(self.dayLabel(day, tokens: tokens))
    }

    private func dayLabel(_ day: Date, tokens: Int?) -> String {
        let date = spendDashboardLedgerDateText(day, timeZone: self.calendar.timeZone, accessibility: true)
        var parts = [L(
            "cockpit_ui_day_tokens",
            date,
            tokens.map(UsageFormatter.tokenCountString)
                ?? L("cockpit_ui_unknown"))]
        if let model = self.days[day] {
            parts += model.resetKinds.map(\.cockpitTitle)
            if model.hasResetForecast { parts.append(L("cockpit_reset_estimate")) }
            if model.hasScheduledReset { parts.append(L("cockpit_reset_scheduled")) }
        }
        return parts.joined(separator: ", ")
    }
}
