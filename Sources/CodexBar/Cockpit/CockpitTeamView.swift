import CodexBarCore
import SwiftUI

@MainActor
struct CockpitTeamView: View {
    let teamStore: CockpitTeamStore
    let onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                if let connection = self.teamStore.connection {
                    self.connectionStatus(connection)
                    TimelineView(.periodic(from: .now, by: 60)) { _ in
                        VStack(alignment: .leading, spacing: 12) {
                            self.distribution(connection: connection)
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label(L("Members and devices"), systemImage: "person.2")
                    } description: {
                        Text(L("Connect a shared space in Settings to coordinate budgets across members and devices."))
                    } actions: {
                        Button(L("Open team settings"), action: self.onSettings)
                    }
                }
                if let message = self.teamStore.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("cockpit-team")
    }

    private var header: some View {
        HStack {
            Label(L("Members and devices"), systemImage: "person.2.fill").font(.headline)
            Spacer()
            if self.teamStore.isBusy { ProgressView().controlSize(.small) }
            Button {
                Task { await self.teamStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("Refresh shared members, device usage, and budgets."))
            .accessibilityLabel(L("Refresh shared members, device usage, and budgets."))
            .disabled(self.teamStore.connection?.enabled != true || self.teamStore.isBusy)
            Button(action: self.onSettings) { Image(systemName: "gearshape") }
                .help(L("Open team settings"))
                .accessibilityLabel(L("Open team settings"))
        }
    }

    private func connectionStatus(_ connection: CockpitTeamStore.Connection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(connection.spaceName).font(.headline)
            if !connection.enabled {
                Text(L("Synchronization is paused. Showing the last shared data."))
                    .font(.caption).foregroundStyle(.orange)
            }
            Text(self.teamStore.uploadStatus).font(.caption).foregroundStyle(.secondary)
            if let date = self.teamStore.lastSyncedAt {
                HStack(spacing: 4) {
                    Text(L("Last synchronized"))
                    Text(date, style: .relative)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func distribution(connection: CockpitTeamStore.Connection) -> some View {
        if let identity = self.teamStore.identity,
           identity.space.id == connection.spaceID, identity.deviceID == connection.deviceID
        {
            let day = CockpitTeamStore.day(self.teamStore.now())
            let deviceNames = Dictionary(
                identity.members.map { ($0.deviceID, $0.displayName) },
                uniquingKeysWith: { first, _ in first })
            let usage = CockpitTeamUsageDistribution.build(
                people: self.teamStore.sharedSettings.value?.groups.groups ?? [],
                activeDeviceIDs: Set(deviceNames.keys),
                snapshots: self.teamStore.snapshots,
                localDate: day)
            let allocations = self.teamStore.allocations
            self.distributionSummary(usage, day: day)
            ForEach(usage.rows) { row in
                CockpitTeamUsageRow(
                    row: row,
                    budget: row.person.flatMap { allocations[$0.id] },
                    deviceNames: deviceNames,
                    currentDeviceID: connection.deviceID)
            }
        } else {
            Text(L("Synchronize to load members and devices."))
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func distributionSummary(_ usage: CockpitTeamUsageDistribution, day: String) -> some View {
        let shareExplanation = L(
            "Shares compare recorded Codex tokens across reporting devices, including unassigned devices.")
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(L("Usage day (UTC+8)"), value: day)
                if usage.rows.isEmpty {
                    Text(L("No members or devices yet.")).foregroundStyle(.secondary)
                } else {
                    CockpitTeamUsageMetrics(totals: usage.totals)
                    Text(shareExplanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                LabeledContent(
                    L("Team daily recommendation"),
                    value: self.teamStore.recommendedTotal.map { ($0 / 100).formatted(.percent.precision(
                        .fractionLength(0...1))) } ?? "—")
                Text(L("Shared plans use UTC+8. Budgets coordinate usage; provider limits remain authoritative."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .padding(4)
        } label: {
            Text(L("Shared usage distribution")).font(.headline)
        }
    }
}

@MainActor
private struct CockpitTeamUsageRow: View {
    let row: CockpitTeamUsageDistribution.Row
    let budget: Double?
    let deviceNames: [String: String]
    let currentDeviceID: String

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                CockpitTeamUsageMetrics(totals: self.row.totals)
                if let share = self.row.tokenShare {
                    LabeledContent(L("Share of recorded team tokens"), value: share.formatted(.percent.precision(
                        .fractionLength(0...1))))
                    ProgressView(value: share)
                        .accessibilityHidden(true)
                }
                if self.row.person != nil {
                    LabeledContent(
                        L("Shared daily budget · UTC+8"),
                        value: self.budget
                            .map { ($0 / 100).formatted(.percent.precision(.fractionLength(0...1))) } ?? "—")
                }
                if !self.row.devices.isEmpty {
                    DisclosureGroup(L("Devices")) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(self.row.devices) { device in
                                self.deviceDetail(device)
                            }
                        }
                        .padding(.top, 6)
                    }
                }
            }
            .font(.callout)
            .padding(4)
        } label: {
            HStack {
                Label(
                    self.row.person?.name ?? L("Unassigned"),
                    systemImage: self.row.person == nil
                        ? "desktopcomputer" : "person.fill")
                    .font(.headline)
                if self.row.devices.contains(where: { $0.id == self.currentDeviceID }), self.row.person != nil {
                    Text(L("My member")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func deviceDetail(_ device: CockpitTeamUsageDistribution.Device) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(self.deviceNames[device.id] ?? device.id).fontWeight(.medium)
                if device.id == self.currentDeviceID {
                    Text(L("This device")).foregroundStyle(.secondary)
                }
            }
            if let updatedAt = device.updatedAt {
                HStack(spacing: 4) {
                    Text(L("Updated"))
                    Text(updatedAt, style: .relative)
                }
                .foregroundStyle(.secondary)
            }
            if let tokens = device.tokens {
                LabeledContent(L("Recorded tokens"), value: tokens.formatted())
                if let cost = device.estimatedCostUSD {
                    LabeledContent(
                        L(device
                            .coverage == .partial ? "Partial estimated cost (USD)" : "Shared-day estimated cost (USD)"),
                        value: cost.formatted(.currency(code: "USD")))
                } else {
                    Text(L("Shared-day cost is unavailable")).foregroundStyle(.secondary)
                }
                if device.coverage == .partial {
                    Text(L("codex_workspaces_partial_data")).foregroundStyle(.secondary)
                }
            } else {
                Text(L(device.updatedAt == nil ? "No shared usage snapshot yet" : "No shared usage for this day"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

@MainActor
private struct CockpitTeamUsageMetrics: View {
    let totals: CockpitTeamUsageDistribution.Totals

    var body: some View {
        if self.totals.deviceCount == 0 {
            Text(L("No devices assigned")).foregroundStyle(.secondary)
        } else {
            if let tokens = self.totals.tokens {
                LabeledContent(L("Recorded tokens"), value: tokens.formatted())
                if let cost = self.totals.estimatedCostUSD {
                    LabeledContent(
                        L(self.totals.costCoverage == .partial
                            ? "Partial estimated cost (USD)" : "Shared-day estimated cost (USD)"),
                        value: cost.formatted(.currency(code: "USD")))
                } else {
                    Text(L("Shared-day cost is unavailable")).font(.caption).foregroundStyle(.secondary)
                }
                if self.totals.tokenCoverage == .partial {
                    Text(L("codex_workspaces_partial_data")).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(L("No shared usage for this day")).foregroundStyle(.secondary)
            }
            Text(L(
                "%1$@ of %2$@ devices reported usage",
                self.totals.reportingDeviceCount.formatted(),
                self.totals.deviceCount.formatted()))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor
struct CockpitTeamBudgetSummary: View {
    @Bindable var teamStore: CockpitTeamStore

    var body: some View {
        if self.teamStore.connection != nil {
            VStack(alignment: .leading, spacing: 6) {
                Label(L("My team allocation"), systemImage: "person.2.fill").font(.headline)
                if let person = self.teamStore.currentPerson,
                   self.teamStore.currentPlan != nil,
                   let budget = self.teamStore.allocations[person.id]
                {
                    LabeledContent(
                        person.name,
                        value: budget.formatted(.number.precision(.fractionLength(0...1))) + "%")
                        .font(.callout)
                    Text(L("Shared daily budget · UTC+8"))
                        .font(.caption).foregroundStyle(.secondary)
                    if self.teamStore.connection?.enabled != true {
                        Text(L("Synchronization paused; showing the last shared plan."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text(L("Assign this device to a member and synchronize a current shared plan."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier("cockpit-team-budget-summary")
        }
    }
}
