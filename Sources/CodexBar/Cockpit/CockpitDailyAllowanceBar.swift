import CodexBarCore
import SwiftUI

/// Remaining allowance uses today's effective allocation as its denominator.
struct CockpitDailyAllowanceBar: View {
    let status: CockpitDayStatus
    let progressColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(L("cockpit_advice_remaining_today"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                CockpitDailyBudgetRemainingValue(status: self.status)
            }
            if let remaining = CockpitMenuBarDailyRemaining(status: self.status) {
                UsageProgressBar(
                    percent: remaining.percent,
                    tint: self.progressColor,
                    accessibilityLabel: L("cockpit_advice_remaining_today"))
                    .accessibilityValue(self.accessibilityValue)
                    .accessibilityIdentifier("cockpit-advice-daily-remaining-progress")
                    .opacity(remaining.isStale ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cockpit-advice-remaining-today")
        .help(L("cockpit_advice_daily_ratio_help"))
    }

    private var accessibilityValue: String {
        var value = CockpitDailyAdviceProjection.remainingDailyText(self.status) + ", "
            + CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(self.status)
        if self.status.isStale { value += ", " + L("cockpit_ui_stale") }
        return value
    }
}
