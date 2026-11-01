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

    private func history(for provider: UsageProvider) -> some View {
        let histories = self.store.planUtilizationHistorySelection(for: provider, readOnly: true).histories
        let burndown = QuotaBurndownChartMenuView(
            provider: provider, histories: histories, width: self.chartWidth)
        return VStack(alignment: .leading, spacing: 10) {
            Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.top, 12)
            if [.codex, .claude, .kiro].contains(provider), burndown.hasSeries {
                burndown
                Divider()
            }
            PlanUtilizationHistoryChartMenuView(
                provider: provider,
                histories: histories,
                snapshot: self.store.snapshot(for: provider.instanceID),
                width: self.chartWidth)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
