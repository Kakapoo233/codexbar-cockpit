import CodexBarCore
import SwiftUI

struct CockpitPlanSummaryView: View {
    let status: CockpitDayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if self.status.isStale {
                Label(L("cockpit_ui_stale"), systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                self.metric(L("cockpit_advice_full_day"), value: self.percent(self.status.suggestedPercent))
                self.metric(L("cockpit_advice_remaining_today"), value: self.percent(
                    self.status.remainingSuggestedPercent,
                    partial: self.status.coverage != .complete,
                    upperBound: true))
                    .accessibilityIdentifier("cockpit-summary-remaining-today")
                self.metric(L("cockpit_ui_weekly_remaining"), value: self.percent(self.status.remainingPercent))
                self.metric(L("cockpit_ui_observed"), value: self.percent(
                    self.status.usedPercent,
                    partial: self.status.coverage != .complete))
            }
            if let window = self.status.planningResetWindow {
                Text(CockpitDailyAdviceProjection.resetWindowText(window))
                    .font(.caption).foregroundStyle(.secondary)
            }
            CockpitComfortAdviceSummaryView(status: self.status)
            Text(L("cockpit_advice_live_note")).font(.caption).foregroundStyle(.secondary)
            if self.status.suggestionIsPartial {
                Text(L("cockpit_advice_partial_note")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("cockpit_ui_observation_note"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func percent(_ value: Double?, partial: Bool = false, upperBound: Bool = false) -> String {
        guard let value else { return "—" }
        return (partial ? (upperBound ? "≤ " : "≥ ") : "") + cockpitLocalizedPercent(value)
    }
}
