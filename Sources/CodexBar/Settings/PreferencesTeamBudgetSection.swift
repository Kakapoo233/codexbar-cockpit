import CodexBarCore
import SwiftUI

@MainActor
struct PreferencesTeamBudgetSection: View {
    let teamStore: CockpitTeamStore
    @State private var personalBudget = 0.0
    @State private var risk = 0.0
    @State private var originalPersonalBudget = 0.0
    @State private var originalRisk = 0.0
    @State private var originalPlan: CockpitTeamDailyPlan?

    var body: some View {
        Section {
            if let total = self.teamStore.recommendedTotal {
                LabeledContent(L("Team daily recommendation"), value: self.percent(total))
            }
            if let person = self.teamStore.currentPerson {
                LabeledContent(L("My member"), value: person.name)
                if let allocation = self.teamStore.allocations[person.id] {
                    LabeledContent(L("My planned budget"), value: self.percent(allocation))
                }
                if self.teamStore.currentPlan != nil { self.personalBudgetEditor }
            } else {
                Text(L("Assign this device to a member to edit a personal budget."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            if self.teamStore.currentPlan != nil { self.riskEditor }
            if self.hasChanges, self.originalPlan != self.teamStore.currentPlan {
                Label(L("The shared plan changed. Reload before saving."), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                Button(L("Reload plan")) { self.reloadBudget() }
            }
            if !self.teamStore.accountMatches {
                Text(L("Bind the current Codex account in Settings to enable shared quota planning."))
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text(L("Shared daily plan"))
        } footer: {
            Text(L("Overrides do not change other budgets. Their sum may exceed the recommendation."))
        }
        .onChange(of: self.teamStore.currentPlan, initial: true) { _, _ in
            if !self.hasChanges { self.reloadBudget() }
        }
        .onChange(of: self.teamStore.currentPerson?.id) { _, _ in self.reloadBudget() }
    }

    private var personalBudgetEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Slider(value: self.$personalBudget, in: 0...100, step: 0.5) {
                    Text(L("Personal budget"))
                }
                Text(self.percent(self.personalBudget)).monospacedDigit().frame(width: 54)
            }
            HStack {
                Button(L("Save my budget")) { self.savePersonalBudget(self.personalBudget) }
                Button(L("Use equal share")) { self.savePersonalBudget(nil) }
            }
            .disabled(self.actionsDisabled)
        }
    }

    private var riskEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Slider(value: self.$risk, in: 0...100, step: 1) {
                    Text(L("Shared risk tolerance"))
                }
                .help(L("Higher risk tolerance increases today's recommended usage."))
                Text(self.percent(self.risk)).monospacedDigit().frame(width: 54)
            }
            HStack {
                Button(L("Save risk tolerance")) { self.saveRisk(self.risk) }
                Button(L("Use default risk tolerance")) { self.saveRisk(nil) }
            }
            .disabled(self.actionsDisabled)
        }
    }

    private var hasChanges: Bool {
        self.personalBudget != self.originalPersonalBudget || self.risk != self.originalRisk
    }

    private var actionsDisabled: Bool {
        self.teamStore.isBusy || self.teamStore.currentPlan == nil || !self.teamStore.accountMatches
            || self.teamStore.connection?.enabled != true || self.originalPlan != self.teamStore.currentPlan
    }

    private func reloadBudget() {
        self.personalBudget = self.teamStore.currentPerson.flatMap { self.teamStore.allocations[$0.id] } ?? 0
        self.risk = self.teamStore.currentPlan?.risk.value ?? 0
        self.originalPersonalBudget = self.personalBudget
        self.originalRisk = self.risk
        self.originalPlan = self.teamStore.currentPlan
    }

    private func savePersonalBudget(_ value: Double?) {
        guard let plan = self.originalPlan else { return }
        Task { await self.teamStore.setPersonalBudget(value, expectedPlan: plan) }
    }

    private func saveRisk(_ value: Double?) {
        guard let plan = self.originalPlan else { return }
        Task { await self.teamStore.setRisk(value, expectedPlan: plan) }
    }

    private func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...1)))
    }
}
