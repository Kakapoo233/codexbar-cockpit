import Charts
import CodexBarCore
import SwiftUI

@MainActor
struct CockpitOverviewView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var planStore: CockpitPlanStore
    @State private var selectedProvider = UsageProvider.codex
    @State private var localProvider = UsageProvider.codex

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                self.header
                if let error = self.planStore.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                if self.planStore.availableProviders.contains(self.selectedProvider) {
                    self.planContent
                } else {
                    ContentUnavailableView(
                        L("cockpit_ui_no_weekly_plan"),
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text(L("cockpit_ui_no_weekly_plan_detail")))
                }
                Divider()
                self.localExperience
            }
            .padding(24)
        }
        .onAppear { self.reconcileProvider() }
        .onChange(of: self.planStore.availableProviders) { _, _ in self.reconcileProvider() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("cockpit_ui_plan")).font(.title2.weight(.semibold))
                Text(L("cockpit_ui_plan_zone", Calendar.current.timeZone.identifier))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !self.planStore.availableProviders.isEmpty {
                Picker(L("cockpit_ui_provider"), selection: self.$selectedProvider) {
                    ForEach(self.planStore.availableProviders, id: \.self) { provider in
                        Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName).tag(provider)
                    }
                }
                .frame(width: 200)
            }
        }
    }

    private var status: CockpitDayStatus {
        self.planStore.status(for: self.selectedProvider)
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            CockpitPlanSummaryView(status: self.status)
            self.personalBudget
        }
    }

    private var personalBudget: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("cockpit_ui_personal_cap")).font(.headline)
                    Spacer()
                    Text(self.percent(self.status.effectiveCapPercent)).monospacedDigit()
                    Button(L("cockpit_ui_use_suggestion")) { self.planStore.setPersonalCap(
                        nil,
                        for: self.selectedProvider) }
                        .disabled(self.status.manualCapPercent == nil)
                }
                Slider(value: self.personalCapBinding, in: 0...100, step: 0.5)
                    .accessibilityLabel(L("cockpit_ui_cap_accessibility"))
                Text(self.status.manualCapPercent == nil ? L("cockpit_ui_automatic_cap") : L("cockpit_ui_manual_cap"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var personalCapBinding: Binding<Double> {
        Binding(
            get: { self.status.effectiveCapPercent ?? 0 },
            set: { self.planStore.setPersonalCap($0, for: self.selectedProvider) })
    }

    private var localExperience: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(L("cockpit_ui_local_experience")).font(.title2.weight(.semibold))
                Spacer()
                Picker(L("cockpit_ui_provider"), selection: self.$localProvider) {
                    ForEach([UsageProvider.codex, .claude], id: \.self) { provider in
                        Text(ProviderDescriptorRegistry.descriptor(for: provider).metadata.displayName).tag(provider)
                    }
                }
                .frame(width: 190)
            }
            Text(L("cockpit_ui_local_experience_note"))
                .font(.caption).foregroundStyle(.secondary)
            self.feelings
            CockpitComfortChartView(
                model: CockpitComfortModel.build(
                    records: self.planStore.state.comfortRecords,
                    providerID: self.localProvider.rawValue,
                    accountID: "local-machine"),
                records: self.comfortRecords)
        }
    }

    private var localFeeling: CockpitFeeling? {
        self.planStore.state.status(providerID: self.localProvider.rawValue, accountID: "local-machine", on: Date())
            .feeling
    }

    private var completeLocalTokens: Int? {
        let expected = self.localProvider == .codex ? "codex:ambient" : "claude"
        let ambient = self.store.tokenCostScope(for: self.localProvider).signature == expected
        let snapshot = self.store.tokenSnapshotForCurrentProviderConfig(for: self.localProvider)?.snapshot
        return CockpitLocalComfortProjection.tokens(
            snapshot: snapshot,
            isAmbient: ambient,
            bucketCalendar: self.settings.costUsageBucketCalendar)
    }

    private var feelings: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L("cockpit_ui_feel_question")).font(.headline)
                    Spacer()
                    if let feeling = self.localFeeling {
                        Text(L("cockpit_ui_feeling_saved", feeling.cockpitTitle)).font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    ForEach(CockpitFeeling.allCases, id: \.self) { feeling in
                        Button {
                            let tokens = self.completeLocalTokens
                            self.planStore.recordLocalComfort(
                                feeling,
                                for: self.localProvider,
                                totalTokens: tokens,
                                coverage: tokens == nil ? .partial : .complete)
                        } label: {
                            Label(feeling.cockpitTitle, systemImage: feeling.cockpitSymbol)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(self.localFeeling == feeling ? Color.accentColor : Color.secondary)
                    }
                }
                Text(L("cockpit_ui_local_snapshot_note"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(8)
        }
    }

    private var comfortRecords: [CockpitComfortRecord] {
        self.planStore.state.comfortRecords.filter {
            $0.providerID == self.localProvider.rawValue
                && $0.accountID == "local-machine"
                && $0.timeZoneIdentifier == Calendar.current.timeZone.identifier
        }.sorted { $0.recordedAt > $1.recordedAt }
    }

    private func reconcileProvider() {
        if !self.planStore.availableProviders.contains(self.selectedProvider),
           let first = self.planStore.availableProviders.first
        {
            self.selectedProvider = first
        }
    }

    private func percent(_ value: Double?, partial: Bool = false) -> String {
        guard let value else { return "—" }
        return (partial ? "≥ " : "") + value.formatted(.number.precision(.fractionLength(1))) + "%"
    }
}

extension CockpitFeeling {
    var cockpitTitle: String {
        switch self {
        case .overloaded: L("cockpit_ui_overloaded")
        case .comfortable: L("cockpit_ui_comfortable")
        case .light: L("cockpit_ui_light")
        }
    }

    var cockpitSymbol: String {
        switch self {
        case .overloaded: "cloud.rain"
        case .comfortable: "sun.haze"
        case .light: "sun.max"
        }
    }
}

struct CockpitComfortChartView: View {
    let model: CockpitComfortModel
    let records: [CockpitComfortRecord]

    var body: some View {
        GroupBox(L("cockpit_ui_experience")) {
            VStack(alignment: .leading, spacing: 14) {
                if !self.model.observations.isEmpty {
                    Chart {
                        ForEach(self.model.observations) { sample in
                            PointMark(
                                x: .value(L("cockpit_ui_chart_tokens"), Double(sample.totalTokens)),
                                y: .value(L("cockpit_ui_chart_feeling"), sample.score))
                                .foregroundStyle(sample.coverage == .complete ? Color.accentColor : Color.gray)
                        }
                        ForEach(self.model.points) { point in
                            LineMark(
                                x: .value(L("cockpit_ui_chart_tokens"), point.totalTokens),
                                y: .value(L("cockpit_ui_chart_feeling"), point.score))
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        }
                    }
                    .chartYScale(domain: 0...1.05)
                    .chartXAxisLabel(L("cockpit_ui_chart_tokens"))
                    .frame(height: 220)
                    .accessibilityLabel(L("cockpit_ui_chart_accessibility"))
                }
                if self.model.status == .insufficientData {
                    Text(L("cockpit_ui_chart_insufficient"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(self.records.prefix(7)) { record in
                    HStack {
                        Text(record.localDateKey).monospacedDigit()
                        Text(record.feeling.cockpitTitle)
                        Spacer()
                        Text(record.totalTokens
                            .map(UsageFormatter.tokenCountString) ?? L("cockpit_ui_incomplete_tokens"))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if self.records.isEmpty {
                    Text(L("cockpit_ui_empty_feelings"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
    }
}
