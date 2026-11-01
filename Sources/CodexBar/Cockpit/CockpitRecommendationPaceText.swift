import CodexBarCore
import Foundation

/// The recommendation comparison is in weekly quota points, but its time basis is the local day.
/// Keep it out of the cumulative weekly stripe and the account's exhaustion forecast.
enum CockpitRecommendationPaceText {
    static func menuBarText(
        pace: CockpitRecommendationPace?,
        reservePositive: Bool = false) -> String?
    {
        guard let pace else { return nil }
        // A lower bound must round outward: ≥4.6 is safely displayed as ≥4, never as ≥5.
        let delta = pace.isLowerBound ? floor(pace.deltaPercent) : pace.deltaPercent.rounded()
        let displayed = reservePositive ? -delta : delta
        guard abs(displayed) < Double(Int.max) else { return nil }
        let sign = displayed > 0 ? "+" : displayed < 0 ? "-" : ""
        let bound = pace.isLowerBound ? (reservePositive ? "≤" : "≥") : ""
        return "\(bound)\(sign)\(Int(abs(displayed)))%"
    }

    static func weeklyDetail(
        pace: CockpitRecommendationPace?,
        officialPace: UsagePace?,
        now: Date) -> UsageMenuCardView.Model.PaceDetail
    {
        let forecast = officialPace.flatMap {
            UsagePaceText.weeklyDetail(provider: .codex, pace: $0, now: now).rightLabel
        }.map { L("cockpit_pace_quota_forecast", $0) }
        return UsageMenuCardView.Model.PaceDetail(
            leftLabel: self.detailLabel(pace),
            rightLabel: forecast,
            pacePercent: nil,
            paceOnTop: true,
            isPaceDerived: true)
    }

    static func detailLabel(_ pace: CockpitRecommendationPace?) -> String {
        guard let pace else { return L("cockpit_pace_today_unavailable") }
        if pace.isLowerBound {
            guard pace.deltaPercent > 0 else { return L("cockpit_pace_today_incomplete") }
            let lowerBound = floor(pace.deltaPercent * 100) / 100
            return L("cockpit_pace_today_observed_ahead", self.points(lowerBound))
        }
        if abs(pace.deltaPercent) < 0.005 {
            return L("cockpit_pace_today_on_track")
        }
        let key = pace.deltaPercent > 0 ? "cockpit_pace_today_ahead" : "cockpit_pace_today_behind"
        return L(key, self.points(abs(pace.deltaPercent)))
    }

    private static func points(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(codexBarLocalizedLocale()))
    }
}
