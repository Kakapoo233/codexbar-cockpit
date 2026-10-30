import CodexBarCore
import SwiftUI

/// Scope comes from the existing provider switcher, never from a remembered unrelated provider.
enum CockpitDailyAdviceProjection {
    static func providers(in scope: [UsageProvider], available: [UsageProvider]) -> [UsageProvider] {
        var seen = Set<UsageProvider>()
        return scope.filter { available.contains($0) && seen.insert($0).inserted }
    }
}

@MainActor
struct CockpitDailyAdviceView: View {
    @Bindable var planStore: CockpitPlanStore
    let providers: [UsageProvider]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("cockpit_ui_daily_advice"), systemImage: "sparkles")
                .font(.headline)
            if self.scopedProviders.isEmpty {
                Text(L("cockpit_ui_no_weekly_plan_detail"))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(self.scopedProviders, id: \.self) { provider in
                    CockpitDailyAdviceRow(
                        provider: provider,
                        status: self.planStore.status(for: provider),
                        setCap: { self.planStore.setPersonalCap($0, for: provider) })
                }
            }
            if let error = self.planStore.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("cockpit-daily-advice")
    }

    private var scopedProviders: [UsageProvider] {
        CockpitDailyAdviceProjection.providers(in: self.providers, available: self.planStore.availableProviders)
    }
}

struct CockpitDailyAdviceRow: View {
    let provider: UsageProvider
    let status: CockpitDayStatus
    let setCap: (Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(ProviderDescriptorRegistry.descriptor(for: self.provider).metadata.displayName)
                    .font(.headline)
                Spacer(minLength: 8)
                self.metric(L("cockpit_ui_suggestion"), self.status.suggestedPercent)
                self.metric(L("cockpit_ui_weekly_remaining"), self.status.remainingPercent)
                self.metric(
                    L("cockpit_ui_observed"),
                    self.status.usedPercent,
                    partial: self.status.coverage != .complete)
            }
            HStack(spacing: 12) {
                Text(L("cockpit_ui_personal_cap")).font(.caption)
                Slider(value: self.capBinding, in: 0...100, step: 0.5)
                    .accessibilityLabel(L("cockpit_ui_cap_accessibility"))
                    .disabled(self.status.suggestedPercent == nil)
                Text(self.percent(self.status.effectiveCapPercent))
                    .font(.callout.monospacedDigit())
                    .frame(width: 56, alignment: .trailing)
                Button(L("cockpit_ui_use_suggestion")) { self.setCap(nil) }
                    .disabled(self.status.manualCapPercent == nil)
            }
            Text(self.status.isStale ? L("cockpit_ui_stale") : L("cockpit_ui_observation_note"))
                .font(.caption2)
                .foregroundStyle(self.status.isStale ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, _ value: Double?, partial: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text((partial && value != nil ? "≥ " : "") + self.percent(value))
                .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—"
    }

    private var capBinding: Binding<Double> {
        Binding(get: { self.status.effectiveCapPercent ?? 0 }, set: { self.setCap($0) })
    }
}
