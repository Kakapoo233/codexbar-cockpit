import CodexBarCore
import SwiftUI

enum CockpitUsageRecommendationText {
    static func value(_ recommendation: CockpitMenuBarRecommendation?) -> String {
        guard let recommendation else { return "—" }
        let approximate = recommendation.isPartial || recommendation.isStale
        return "\(approximate ? "≈ " : "")\(cockpitLocalizedPercent(recommendation.percent))"
    }

    static func accessibility(_ recommendation: CockpitMenuBarRecommendation?) -> String {
        guard let recommendation else {
            return L("%@ unavailable", L("cockpit_menu_daily_recommendation"))
        }
        var text = L("cockpit_menu_daily_recommendation_accessibility", cockpitLocalizedPercent(recommendation.percent))
        if recommendation.isPartial { text = L("cockpit_menu_daily_recommendation_partial", text) }
        if recommendation.isStale { text += ", " + L("cockpit_ui_stale") }
        return text
    }
}

/// The automatic full-day share is an allocation of weekly quota, never a used/remaining complement.
struct CockpitUsageRecommendationBar: View {
    let recommendation: CockpitMenuBarRecommendation
    let progressColor: Color
    var compact = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        let label = L("cockpit_menu_daily_recommendation")
        let title = "\(label) \(CockpitUsageRecommendationText.value(self.recommendation))"
        VStack(alignment: .leading, spacing: 6) {
            MetricRowHeader(
                title: title,
                layoutTitle: title,
                resetText: nil,
                layoutResetText: nil,
                isHighlighted: self.isHighlighted)
                .accessibilityIdentifier("cockpit-usage-daily-recommendation-title")
            UsageProgressBar(
                percent: self.recommendation.percent,
                tint: self.progressColor,
                accessibilityLabel: L("cockpit_menu_daily_recommendation"))
                .accessibilityValue(CockpitUsageRecommendationText.accessibility(self.recommendation))
                .accessibilityIdentifier("cockpit-usage-daily-recommendation-progress")
                .opacity(self.recommendation.isStale && !self.isHighlighted ? 0.5 : 1)
            if !self.compact {
                Text(L("cockpit_advice_full_day"))
                    .font(.footnote)
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cockpit-usage-daily-recommendation")
        .help(L("cockpit_menu_daily_recommendation_help"))
    }
}
