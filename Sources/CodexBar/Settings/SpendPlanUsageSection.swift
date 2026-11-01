import CodexBarCore
import SwiftUI

/// Account-scoped quota history shares its existing collectors and interactive chart components.
@MainActor
struct SpendPlanUsageSection: View {
    @Bindable var store: UsageStore
    @State private var chartWidth: CGFloat = 300

    var providers: [UsageProvider] {
        // History buckets are intentionally ignored by Observation; their revision publishes load/sample changes.
        _ = self.store.planUtilizationHistoryRevision
        return self.store.enabledFirstPartyProvidersForDisplay().filter {
            self.store.supportsPlanUtilizationHistory(for: $0)
        }
    }

    var body: some View {
        if !self.providers.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Plan Usage")).font(.headline)
                ForEach(self.providers, id: \.self) { provider in
                    self.history(for: provider)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                self.chartWidth = max(1, width - 2)
            }
            .accessibilityIdentifier("spend-plan-usage")
        }
    }

    func displayedHistories(for provider: UsageProvider) -> [PlanUtilizationSeriesHistory] {
        let controller = self.store.sharedSpendDashboardController()
        return Self.filterHistories(
            self.store.planUtilizationHistorySelection(for: provider, readOnly: true).histories,
            period: controller.selectedPeriod,
            now: controller.reportingDate,
            calendar: controller.configuration?.bucketCalendar ?? .current)
    }

    static func filterHistories(
        _ histories: [PlanUtilizationSeriesHistory],
        period: CostReportingPeriod,
        now: Date,
        calendar: Calendar) -> [PlanUtilizationSeriesHistory]
    {
        let start = period.bounds(now: now, calendar: calendar).lowerBound
        return histories.map { history in
            PlanUtilizationSeriesHistory(
                name: history.name,
                windowMinutes: history.windowMinutes,
                entries: history.entries.filter { $0.capturedAt >= start && $0.capturedAt <= now })
        }
    }

    func timeline(for provider: UsageProvider) -> SpendPlanHistoryTimelineView {
        let controller = self.store.sharedSpendDashboardController()
        return SpendPlanHistoryTimelineView(
            provider: provider,
            histories: self.store.planUtilizationHistorySelection(for: provider, readOnly: true).histories,
            snapshot: self.store.snapshot(for: provider.instanceID),
            period: controller.selectedPeriod,
            referenceDate: controller.reportingDate,
            calendar: controller.configuration?.bucketCalendar ?? .current)
    }

    private func history(for provider: UsageProvider) -> some View {
        let histories = self.displayedHistories(for: provider)
        let controller = self.store.sharedSpendDashboardController()
        let detailWidth = max(1, self.chartWidth - 32)
        let burndown = QuotaBurndownChartMenuView(
            provider: provider, histories: histories, width: detailWidth, referenceDate: controller.reportingDate)
        return VStack(alignment: .leading, spacing: 10) {
            Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            self.timeline(for: provider)
            DisclosureGroup(L("cockpit_plan_cycle_details")) {
                if [.codex, .claude, .kiro].contains(provider), burndown.hasSeries {
                    burndown
                    Divider()
                }
                PlanUtilizationHistoryChartMenuView(
                    provider: provider,
                    histories: histories,
                    snapshot: self.store.snapshot(for: provider.instanceID),
                    width: detailWidth,
                    referenceDate: controller.reportingDate,
                    pointLimit: nil)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
