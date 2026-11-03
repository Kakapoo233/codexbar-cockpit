import CodexBarCore
import Foundation

/// The recommendation comparison is in weekly quota points, but its time basis is the local day.
/// Keep it out of the cumulative weekly stripe and the account's exhaustion forecast.
enum CockpitRecommendationPaceText {
    /// Status numbers describe the recorded comparison, not a claim of complete account usage.
    static func statusItemText(
        pace: CockpitRecommendationPace?,
        reservePositive: Bool = false) -> String?
    {
        guard let pace else { return nil }
        let delta = pace.deltaPercent.rounded()
        let displayed = reservePositive ? -delta : delta
        guard abs(displayed) < Double(Int.max) else { return nil }
        let sign = displayed > 0 ? "+" : displayed < 0 ? "-" : ""
        return "\(sign)\(Int(abs(displayed)))%"
    }

    static func statusItemExplanation(
        pace: CockpitRecommendationPace,
        reservePositive: Bool = false) -> String
    {
        let displayed = reservePositive ? -pace.deltaPercent : pace.deltaPercent
        let value = abs(displayed) < 0.005 ? 0 : displayed
        let number = abs(value).formatted(.number.precision(.fractionLength(0...2))
            .locale(codexBarLocalizedLocale()))
        let sign = value > 0 ? "+" : value < 0 ? "-" : ""
        var parts = [L("Pace: %@", "\(sign)\(number)%"), L("cockpit_menu_pace_recorded_reference_help")]
        if pace.isLowerBound { parts.append(L("cockpit_menu_pace_partial_color_help")) }
        return parts.joined(separator: "\n")
    }

    static func menuBarText(
        pace: CockpitRecommendationPace?,
        reservePositive: Bool = false) -> String?
    {
        guard let pace else { return nil }
        // Retain the existing partial-observation rounding; only its visible qualifier is hidden.
        let delta = pace.isLowerBound ? floor(pace.deltaPercent) : pace.deltaPercent.rounded()
        let displayed = reservePositive ? -delta : delta
        guard abs(displayed) < Double(Int.max) else { return nil }
        let sign = displayed > 0 ? "+" : displayed < 0 ? "-" : ""
        return "\(sign)\(Int(abs(displayed)))%"
    }

    static func weeklyDetail(
        pace: CockpitRecommendationPace?,
        officialPace: UsagePace?,
        now: Date) -> UsageMenuCardView.Model.PaceDetail
    {
        UsageMenuCardView.Model.PaceDetail(
            leftLabel: self.detailLabel(pace),
            rightLabel: self.quotaForecast(officialPace, now: now),
            pacePercent: nil,
            paceOnTop: true,
            isPaceDerived: true)
    }

    static func detailLabel(_ pace: CockpitRecommendationPace?) -> String {
        guard let pace else { return "—" }
        if pace.isLowerBound {
            // A negative lower bound does not establish a reserve or an on-pace result.
            return pace.deltaPercent > 0 ? self.menuBarText(pace: pace) ?? "—" : "—"
        }
        // Match CodexBar's native neutral band without changing the daily comparison itself.
        let stage: UsagePace.Stage = abs(pace.deltaPercent) <= 2
            ? .onTrack : pace.deltaPercent > 0 ? .ahead : .behind
        return UsagePaceText.deviationLabel(deltaPercent: pace.deltaPercent, stage: stage)
    }

    static func detailHelp(
        pace: CockpitRecommendationPace?,
        officialPace: UsagePace?,
        now: Date) -> String
    {
        let forecast = self.quotaForecast(officialPace, now: now).map { L("cockpit_pace_quota_forecast", $0) }
        return [L("menu_bar_help_pace"), self.explanationLabel(pace), forecast]
            .compactMap(\.self)
            .joined(separator: "\n")
    }

    static func explanationLabel(_ pace: CockpitRecommendationPace?) -> String {
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

    private static func quotaForecast(_ pace: UsagePace?, now: Date) -> String? {
        pace.flatMap { UsagePaceText.weeklyDetail(provider: .codex, pace: $0, now: now).rightLabel }
    }
}
