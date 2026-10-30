import CodexBarCore
import SwiftUI

/// Scope comes from the existing provider switcher, never from a remembered unrelated provider.
enum CockpitDailyAdviceProjection {
    static func providers(in scope: [UsageProvider], available: [UsageProvider]) -> [UsageProvider] {
        var seen = Set<UsageProvider>()
        return scope.filter { available.contains($0) && seen.insert($0).inserted }
    }
}

enum CockpitDailyAdviceLayout {
    case inline, sidebar
}

@MainActor
struct CockpitDailyAdviceView: View {
    @Bindable var planStore: CockpitPlanStore
    let providers: [UsageProvider]
    var layout: CockpitDailyAdviceLayout = .inline

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
                        setCap: { self.planStore.setPersonalCap($0, for: provider) },
                        layout: self.layout)
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
    var layout: CockpitDailyAdviceLayout = .inline

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if self.layout == .sidebar {
                self.sidebarContent
            } else {
                ViewThatFits(in: .horizontal) {
                    self.inlineContent
                    self.sidebarContent
                }
            }
            Text(self.status.isStale ? L("cockpit_ui_stale") : L("cockpit_ui_observation_note"))
                .font(.caption2)
                .foregroundStyle(self.status.isStale ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                self.providerTitle
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
                self.capSlider
                self.capValue.frame(width: 56, alignment: .trailing)
                self.resetButton
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            self.providerTitle
            VStack(spacing: 8) {
                self.sidebarMetric(L("cockpit_ui_suggestion"), self.status.suggestedPercent)
                self.sidebarMetric(L("cockpit_ui_weekly_remaining"), self.status.remainingPercent)
                self.sidebarMetric(
                    L("cockpit_ui_observed"),
                    self.status.usedPercent,
                    partial: self.status.coverage != .complete)
            }
            Divider()
            VStack(spacing: 6) {
                HStack {
                    Text(L("cockpit_ui_personal_cap")).font(.caption)
                    Spacer(minLength: 8)
                    self.capValue
                }
                self.capSlider
            }
            self.resetButton.controlSize(.small)
        }
    }

    private var providerTitle: some View {
        Text(ProviderDescriptorRegistry.descriptor(for: self.provider).metadata.displayName).font(.headline)
    }

    private var capValue: some View {
        Text(self.percent(self.status.effectiveCapPercent)).font(.callout.monospacedDigit())
    }

    private var capSlider: some View {
        Slider(value: self.capBinding, in: 0...100, step: 0.5)
            .accessibilityLabel(L("cockpit_ui_cap_accessibility"))
            .disabled(self.status.suggestedPercent == nil)
    }

    private var resetButton: some View {
        Button(L("cockpit_ui_use_suggestion")) { self.setCap(nil) }
            .disabled(self.status.manualCapPercent == nil)
    }

    private func sidebarMetric(_ title: String, _ value: Double?, partial: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            self.metricValue(value, partial: partial)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func metric(_ title: String, _ value: Double?, partial: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            self.metricValue(value, partial: partial)
        }
    }

    private func metricValue(_ value: Double?, partial: Bool) -> some View {
        Text((partial && value != nil ? "≥ " : "") + self.percent(value))
            .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
    }

    private func percent(_ value: Double?) -> String {
        value.map(cockpitLocalizedPercent) ?? "—"
    }

    private var capBinding: Binding<Double> {
        Binding(get: { self.status.effectiveCapPercent ?? 0 }, set: { self.setCap($0) })
    }
}
