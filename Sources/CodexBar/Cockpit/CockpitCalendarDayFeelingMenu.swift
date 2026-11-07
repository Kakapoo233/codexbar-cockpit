import CodexBarCore
import SwiftUI

/// A sibling of the date-selection button, so opening the editor never activates that button.
struct CockpitCalendarDayFeelingMenu: View {
    let day: Date
    let calendar: Calendar
    let selected: CockpitFeeling?
    let canRecord: Bool
    var compact = false
    let onChange: (CockpitFeeling?) -> Void

    var body: some View {
        Menu {
            ForEach([CockpitFeeling.light, .comfortable, .overloaded], id: \.self) { feeling in
                Button {
                    guard self.canRecord else { return }
                    self.onChange(feeling)
                } label: {
                    HStack {
                        Text("\(feeling.cockpitEmoji) \(feeling.calendarTitle)")
                        if self.selected == feeling { Image(systemName: "checkmark") }
                    }
                }
            }
            Divider()
            Button(L("cockpit_ui_calendar_clear")) {
                guard self.canRecord else { return }
                self.onChange(nil)
            }
            .disabled(self.selected == nil)
        } label: {
            HStack(spacing: 4) {
                if let selected {
                    Text(selected.cockpitEmoji).accessibilityHidden(true)
                } else {
                    Image(systemName: "face.smiling").accessibilityHidden(true)
                }
                if !self.compact {
                    Text(self.selected?.calendarTitle ?? L("cockpit_ui_calendar_personal_status"))
                }
                Image(systemName: "chevron.down").accessibilityHidden(true)
            }
            .font(CockpitCalendarTypography.caption2)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!self.canRecord)
        .help(self.label)
        .accessibilityLabel(self.label)
        .accessibilityValue(self.selected?.calendarTitle ?? L("cockpit_ui_calendar_unselected"))
        .accessibilityIdentifier(
            "cockpit-calendar-feeling-\(CockpitCalendar.dateKey(for: self.day, calendar: self.calendar))")
    }

    private var label: String {
        let date = spendDashboardLedgerDateText(self.day, timeZone: self.calendar.timeZone, accessibility: true)
        return "\(date), \(L("cockpit_ui_calendar_personal_status"))"
    }
}
