import CodexBarCore
import SwiftUI

/// Scope comes from the existing provider switcher, never from a remembered unrelated provider.
enum CockpitDailyAdviceProjection {
    static func providers(in scope: [UsageProvider], available: [UsageProvider]) -> [UsageProvider] {
        var seen = Set<UsageProvider>()
        return scope.filter { available.contains($0) && seen.insert($0).inserted }
    }

    static func resetWindowText(_ window: CockpitPlanningResetWindow) -> String {
        let date = window.resetsAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
            .locale(codexBarLocalizedLocale()))
        let key = switch window.source {
        case .account: "cockpit_advice_reset_account"
        case .announced: "cockpit_advice_reset_announced"
        case .estimated: "cockpit_advice_reset_estimated"
        }
        return L(key, date)
    }

    static func remainingDailyText(_ status: CockpitDayStatus) -> String {
        self.remainingText(status.remainingDailyBudgetPercent, coverage: status.coverage)
    }

    static func remainingWeeklyText(_ status: CockpitDayStatus) -> String {
        guard status.remainingDailyBudgetPercent != nil else { return "—" }
        return self.remainingText(status.remainingSuggestedPercent, coverage: status.coverage)
    }

    static func remainingWeeklyEquivalentText(_ status: CockpitDayStatus) -> String {
        L("cockpit_advice_weekly_equivalent", self.remainingWeeklyText(status))
    }

    private static func remainingText(_ value: Double?, coverage: CockpitCoverage) -> String {
        guard let value else { return "—" }
        return (coverage == .complete ? "" : "≤ ") + cockpitLocalizedPercent(value)
    }

    static func comfortCeilingText(_ advice: CockpitComfortAdvice) -> String {
        let key = advice.curveStatus == .fitted
            ? "cockpit_advice_comfort_fitted" : "cockpit_advice_comfort_default"
        return L(key, cockpitLocalizedPercent(advice.softCapPercent))
    }

    static func resetRiskText(_ risk: CockpitResetRisk) -> String {
        switch risk.source {
        case .assumed:
            L("cockpit_advice_risk_default", cockpitLocalizedPercent(risk.probability * 100))
        case .estimated:
            L("cockpit_advice_risk_estimated", cockpitLocalizedPercent(risk.probability * 100))
        case .announced:
            L("cockpit_advice_risk_announced")
        }
    }

    static func comfortLimitText(_ advice: CockpitComfortAdvice, manualCap: Double?) -> String? {
        if manualCap != nil {
            return L(advice.isComfortLimited
                ? "cockpit_advice_comfort_limited_manual" : "cockpit_advice_manual_priority")
        }
        return advice.isComfortLimited ? L("cockpit_advice_comfort_limited") : nil
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
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            self.content(on: Date())
        }
    }

    private func content(on date: Date) -> some View {
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
                        status: self.planStore.status(for: provider, on: date),
                        setCap: { self.planStore.setPersonalCap($0, for: provider) },
                        layout: self.layout)
                    CockpitPersonalInsightsView(
                        model: CockpitPersonalUsageModel.build(
                            state: self.planStore.state,
                            providerID: provider.rawValue,
                            accountID: self.planStore.accountID(for: provider),
                            now: date),
                        status: self.planStore.status(for: provider, on: date))
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
            if let window = self.status.planningResetWindow {
                Text(CockpitDailyAdviceProjection.resetWindowText(window))
                    .font(.caption2)
                    .foregroundStyle(window.source == .estimated ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CockpitComfortAdviceSummaryView(status: self.status)
            Text(L("cockpit_advice_live_note"))
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if self.status.suggestionIsPartial {
                Text(L("cockpit_advice_partial_note"))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
            self.providerTitle
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                self.metric(L("cockpit_advice_full_day"), self.status.suggestedPercent)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L("cockpit_advice_remaining_today")).font(.caption).foregroundStyle(.secondary)
                    CockpitDailyBudgetRemainingValue(status: self.status)
                }
                .accessibilityIdentifier("cockpit-advice-remaining-today")
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
                self.sidebarMetric(L("cockpit_advice_full_day"), self.status.suggestedPercent)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(L("cockpit_advice_remaining_today"))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    CockpitDailyBudgetRemainingValue(status: self.status)
                }
                .accessibilityIdentifier("cockpit-advice-remaining-today")
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

    private func sidebarMetric(
        _ title: String, _ value: Double?, partial: Bool = false, upperBound: Bool = false) -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            self.metricValue(value, partial: partial, upperBound: upperBound)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func metric(
        _ title: String, _ value: Double?, partial: Bool = false, upperBound: Bool = false) -> some View
    {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            self.metricValue(value, partial: partial, upperBound: upperBound)
        }
    }

    private func metricValue(_ value: Double?, partial: Bool, upperBound: Bool) -> some View {
        Text((partial && value != nil ? (upperBound ? "≤ " : "≥ ") : "") + self.percent(value))
            .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
    }

    private func percent(_ value: Double?) -> String {
        value.map(cockpitLocalizedPercent) ?? "—"
    }

    private var capBinding: Binding<Double> {
        Binding(get: { min(100, max(0, self.status.effectiveCapPercent ?? 0)) }, set: { self.setCap($0) })
    }
}

struct CockpitComfortAdviceSummaryView: View {
    let status: CockpitDayStatus

    var body: some View {
        if let advice = self.status.comfortAdvice {
            VStack(alignment: .leading, spacing: 4) {
                Label(CockpitDailyAdviceProjection.comfortCeilingText(advice), systemImage: "waveform.path")
                    .help(self.curveHelp(advice))
                    .accessibilityIdentifier("cockpit-advice-comfort-ceiling")
                Text(CockpitDailyAdviceProjection.resetRiskText(advice.risk))
                    .help(L("cockpit_advice_risk_help"))
                    .accessibilityIdentifier("cockpit-advice-reset-risk")
                if let limit = CockpitDailyAdviceProjection.comfortLimitText(
                    advice, manualCap: self.status.manualCapPercent)
                {
                    Text(limit)
                        .accessibilityIdentifier("cockpit-advice-comfort-limit-note")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func curveHelp(_ advice: CockpitComfortAdvice) -> String {
        let source = advice.curveStatus == .fitted
            ? L("cockpit_advice_comfort_samples", advice.sampleCount)
            : L("cockpit_advice_comfort_default_help")
        return source + " " + L("cockpit_advice_comfort_ceiling_help")
    }
}

struct CockpitDailyBudgetRemainingValue: View {
    let status: CockpitDayStatus
    var alignment: HorizontalAlignment = .trailing
    var fontSize: CGFloat = 19

    var body: some View {
        VStack(alignment: self.alignment, spacing: 3) {
            Text(CockpitDailyAdviceProjection.remainingDailyText(self.status))
                .font(.system(size: self.fontSize, weight: .semibold, design: .rounded)).monospacedDigit()
                .accessibilityIdentifier("cockpit-advice-remaining-daily-ratio")
            Text(CockpitDailyAdviceProjection.remainingWeeklyEquivalentText(self.status))
                .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("cockpit-advice-remaining-weekly-equivalent")
        }
        .help(L("cockpit_advice_daily_ratio_help"))
    }
}
