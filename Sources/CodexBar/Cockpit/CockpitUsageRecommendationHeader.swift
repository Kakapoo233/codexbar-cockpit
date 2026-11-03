import CodexBarCore
import SwiftUI

enum CockpitUsageRecommendationText {
    static func value(_ status: CockpitDayStatus?) -> String {
        guard let status, let value = status.suggestedPercent, value.isFinite, value >= 0 else { return "—" }
        let approximate = status.suggestionIsPartial || status.isStale
        return "\(approximate ? "≈ " : "")\(cockpitLocalizedPercent(value))"
    }

    static func accessibility(_ status: CockpitDayStatus?) -> String {
        guard let status, let value = status.suggestedPercent, value.isFinite, value >= 0 else {
            return L("%@ unavailable", L("cockpit_menu_daily_recommendation"))
        }
        var text = L("cockpit_menu_daily_recommendation_accessibility", cockpitLocalizedPercent(value))
        if status.suggestionIsPartial { text = L("cockpit_menu_daily_recommendation_partial", text) }
        if status.isStale { text += ", " + L("cockpit_ui_stale") }
        return text
    }
}

/// A compact, pinned summary of the same account-matched automatic plan used by the status item.
@MainActor
struct CockpitUsageRecommendationHeader: View {
    @Bindable var planStore: CockpitPlanStore
    @Bindable var store: UsageStore
    let providers: [UsageProvider]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            self.content(on: Date())
        }
    }

    @ViewBuilder
    func content(on date: Date) -> some View {
        let scoped = CockpitDailyAdviceProjection.providers(
            in: self.providers, available: self.planStore.availableProviders)
        if !scoped.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(L("cockpit_menu_daily_recommendation"), systemImage: "sparkles")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    self.metrics(scoped, on: date)
                    ScrollView(.horizontal) {
                        self.metrics(scoped, on: date)
                    }
                    .scrollIndicators(.hidden)
                }
                Text(L("cockpit_advice_full_day"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.15)))
            .help(L("cockpit_menu_daily_recommendation_help"))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("cockpit-usage-daily-recommendation")
        }
    }

    private func metrics(_ providers: [UsageProvider], on date: Date) -> some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(providers, id: \.self) { provider in
                let status = self.planStore.status(
                    for: provider,
                    matching: self.store.menuBarSnapshot(for: provider.instanceID),
                    on: date)
                let providerName = ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName
                VStack(alignment: .leading, spacing: 2) {
                    Text(providerName).font(.subheadline).foregroundStyle(.secondary)
                    Text(CockpitUsageRecommendationText.value(status))
                        .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(status?.isStale == true ? Color.secondary : Color.accentColor)
                }
                .fixedSize(horizontal: true, vertical: true)
                .frame(minWidth: 150, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(providerName), \(CockpitUsageRecommendationText.accessibility(status))")
                .accessibilityIdentifier("cockpit-usage-daily-recommendation-\(provider.rawValue)")
            }
        }
    }
}
