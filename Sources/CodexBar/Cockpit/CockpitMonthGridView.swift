import CodexBarCore
import Foundation
import SwiftUI

struct CockpitCalendarDay: Identifiable, Equatable {
    let day: Date
    let tokens: Int?
    let feeling: CockpitFeeling?
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

    private var weekdaySymbols: [String] {
        let symbols = self.calendar.veryShortWeekdaySymbols
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
                if let day { self.dayCell(day) } else { Color.clear.frame(height: 86) }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let tokens = self.days[day]?.tokens
        let selected = self.calendar.isDate(day, inSameDayAs: self.selectedDay)
        let dayNumber = self.calendar.component(.day, from: day)
        return Button { self.select(day) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(dayNumber.formatted()).font(.body.weight(.medium))
                    Spacer(minLength: 0)
                    if self.calendar.isDateInToday(day) {
                        Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    }
                }
                Text(tokens.map(UsageFormatter.tokenCountString) ?? "—")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let feeling = self.days[day]?.feeling {
                    Text(feeling.cockpitTitle).font(.caption2).foregroundStyle(.tint)
                }
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
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
        return L("cockpit_ui_day_tokens", date, tokens.map(UsageFormatter.tokenCountString) ?? L("cockpit_ui_unknown"))
    }
}
