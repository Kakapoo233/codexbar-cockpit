import CodexBarCore

extension UsageMenuCardView.Model {
    /// Keep planning decoration on the measured main weekly pool, never on another allowance.
    static func cockpitRecommendationMetrics(_ metrics: [Metric], input: Input) -> [Metric] {
        let weeklyMetricID = self.cockpitWeeklyMetricID(input: input)
        return metrics.map { value in
            var metric = value
            metric.cockpitDailyRecommendation = metric.id == weeklyMetricID && metric.statusText == nil
                ? input.cockpitDailyRecommendation : nil
            return metric
        }
    }

    private static func cockpitWeeklyMetricID(input: Input) -> String? {
        guard input.cockpitDailyRecommendation != nil,
              let snapshot = input.snapshot,
              let weekly = CockpitPlanStore.weeklyWindow(in: snapshot) else { return nil }

        // Codex normalizes either physical source slot into its displayed weekly lane.
        if input.provider == .codex, let projection = input.codexProjection {
            return projection.rateWindow(for: .weekly) == weekly ? "secondary" : nil
        }

        // The planner prefers secondary, then primary, then tertiary for an actual seven-day window.
        // Reuse that exact choice instead of assuming that a provider's secondary slot is weekly.
        if snapshot.secondary == weekly { return "secondary" }
        if snapshot.primary == weekly { return "primary" }
        if snapshot.tertiary == weekly { return "tertiary" }
        return nil
    }
}
