import CodexBarCore
import SwiftUI

@MainActor
struct CockpitTeamView: View {
    @Bindable var teamStore: CockpitTeamStore
    let onSettings: () -> Void
    @State private var draft = CockpitTeamGroups()
    @State private var original = CockpitTeamGroups()
    @State private var draftRevision = 0
    @State private var personalBudget = 0.0
    @State private var risk = 0.0
    @State private var originalPersonalBudget = 0.0
    @State private var originalRisk = 0.0
    @State private var originalPlan: CockpitTeamDailyPlan?
    @State private var revokingDevice: CockpitTeamDevice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                if self.teamStore.connection == nil {
                    ContentUnavailableView {
                        Label(L("Members and devices"), systemImage: "person.2")
                    } description: {
                        Text(L("Connect a shared space in Settings to coordinate budgets across members and devices."))
                    } actions: {
                        Button(L("Open team settings"), action: self.onSettings)
                    }
                } else {
                    self.connectionStatus
                    self.budgetSection
                    self.membersSection
                    self.devicesSection
                    self.invitationSection
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
        .onAppear { self.reloadDraft(); self.reloadBudget() }
        .onChange(of: self.teamStore.sharedSettings) { _, _ in
            if !self.hasChanges { self.reloadDraft() }
        }
        .onChange(of: self.teamStore.currentPlan) { _, _ in
            if !self.budgetHasChanges { self.reloadBudget() }
        }
        .onChange(of: self.teamStore.currentPerson?.id) { _, _ in self.reloadBudget() }
        .confirmationDialog(
            L("Revoke device access?"),
            isPresented: Binding(
                get: { self.revokingDevice != nil },
                set: { if !$0 { self.revokingDevice = nil } }),
            titleVisibility: .visible)
        {
            if let device = self.revokingDevice {
                Button(L("Revoke access"), role: .destructive) {
                    Task { await self.teamStore.revoke(deviceID: device.deviceID) }
                    self.revokingDevice = nil
                }
            }
            Button(L("Cancel"), role: .cancel) { self.revokingDevice = nil }
        } message: {
            Text(L("This device will lose access. Previously shared data and other devices' caches are retained."))
        }
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
            .disabled(self.teamStore.connection == nil || self.teamStore.isBusy)
            Button(action: self.onSettings) { Image(systemName: "gearshape") }
                .help(L("Open team settings"))
        }
    }

    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(self.teamStore.connection?.spaceName ?? "").font(.headline)
            Text(self.teamStore.uploadStatus).font(.caption).foregroundStyle(.secondary)
            if let date = self.teamStore.lastSyncedAt {
                HStack(spacing: 4) {
                    Text(L("Last synchronized"))
                    Text(date, style: .relative)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Shared plans use UTC+8. Budgets coordinate usage; provider limits remain authoritative."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var budgetSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let total = self.teamStore.recommendedTotal {
                    LabeledContent(L("Team daily recommendation"), value: self.percent(total))
                }
                if let person = self.teamStore.currentPerson {
                    LabeledContent(L("My member"), value: person.name)
                    if let allocation = self.teamStore.allocations[person.id] {
                        LabeledContent(L("My planned budget"), value: self.percent(allocation))
                    }
                    HStack {
                        Text(L("Personal budget"))
                        Slider(value: self.$personalBudget, in: 0...100, step: 0.5)
                        Text(self.percent(self.personalBudget)).monospacedDigit().frame(width: 54)
                    }
                    HStack {
                        Button(L("Save my budget")) {
                            guard let plan = self.originalPlan else { return }
                            let value = self.personalBudget
                            Task { await self.teamStore.setPersonalBudget(value, expectedPlan: plan) }
                        }
                        Button(L("Use equal share")) {
                            guard let plan = self.originalPlan else { return }
                            Task { await self.teamStore.setPersonalBudget(nil, expectedPlan: plan) }
                        }
                    }
                    .disabled(self.budgetActionsDisabled)
                } else {
                    Text(L("Assign this device to a member to edit a personal budget."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                if self.teamStore.currentPlan != nil {
                    Divider()
                    HStack {
                        Text(L("Shared risk tolerance"))
                        Slider(value: self.$risk, in: 0...100, step: 1)
                            .help(L("Higher risk tolerance increases today's recommended usage."))
                        Text(self.percent(self.risk)).monospacedDigit().frame(width: 54)
                    }
                    HStack {
                        Button(L("Save risk tolerance")) {
                            guard let plan = self.originalPlan else { return }
                            let value = self.risk
                            Task { await self.teamStore.setRisk(value, expectedPlan: plan) }
                        }
                        Button(L("Use default risk tolerance")) {
                            guard let plan = self.originalPlan else { return }
                            Task { await self.teamStore.setRisk(nil, expectedPlan: plan) }
                        }
                    }
                    .disabled(self.budgetActionsDisabled)
                }
                if self.budgetHasChanges, self.originalPlan != self.teamStore.currentPlan {
                    Label(L("The shared plan changed. Reload before saving."), systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Button(L("Reload plan")) { self.reloadBudget() }
                }
                Text(
                    L(
                        "Overrides do not change other budgets. Their sum may exceed the recommendation."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !self.teamStore.accountMatches {
                    Text(L("Bind the current Codex account in Settings to enable shared quota planning."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(4)
        } label: {
            Text(L("Shared daily plan"))
        }
    }

    private var membersSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if self.draft.groups.isEmpty {
                    Text(L("No members yet. Add a member, then assign their devices below."))
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(self.$draft.groups) { $person in
                    HStack {
                        TextField(L("Member name"), text: $person.name)
                        Text(self.percent(self.teamStore.allocations[person.id]))
                            .monospacedDigit().foregroundStyle(.secondary)
                        Button(role: .destructive) { self.removePerson(person.id) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .help(L("Remove this member and leave their devices unassigned."))
                    }
                }
                HStack {
                    Button(L("Add member"), systemImage: "plus") { self.addPerson() }
                        .disabled(self.draft.groups.count >= 32)
                    Spacer()
                    Button(L("Reload")) { self.reloadDraft() }
                    Button(L("Save members and devices")) {
                        let value = self.draft
                        let revision = self.draftRevision
                        Task {
                            await self.teamStore.saveGroups(value, expectedRevision: revision)
                            if self.teamStore.sharedSettings.value?.groups == value { self.reloadDraft() }
                        }
                    }
                    .disabled(!self.hasChanges || !self.validDraft || self.teamStore.isBusy)
                }
                if self.hasChanges, self.teamStore.sharedSettings.revision != self.draftRevision {
                    Label(
                        L("Another device changed the members. Reload before applying your changes again."),
                        systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(L("Each device belongs to at most one member. Unassigned devices remain separate."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(4)
        } label: {
            Text(L("Members"))
        }
    }

    private var devicesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(self.availableDeviceIDs, id: \.self) { deviceID in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(self.deviceName(deviceID), systemImage: "desktopcomputer")
                            if deviceID == self.teamStore.connection?.deviceID {
                                Text(L("This device")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if self.canRevoke(deviceID) {
                                Button(L("Revoke"), role: .destructive) {
                                    self.revokingDevice = self.teamStore.identity?.members.first {
                                        $0.deviceID == deviceID
                                    }
                                }
                                .disabled(self.teamStore.isBusy)
                            }
                        }
                        Picker(L("Assigned member"), selection: self.assignment(deviceID)) {
                            Text(L("Unassigned")).tag("")
                            ForEach(self.draft.groups) { person in
                                Text(person.name).tag(person.id)
                            }
                        }
                        self.deviceUsage(deviceID)
                    }
                    if deviceID != self.availableDeviceIDs.last { Divider() }
                }
            }
            .padding(4)
        } label: {
            Text(L("Devices"))
        }
    }

    @ViewBuilder
    private var invitationSection: some View {
        if self.teamStore.connection?.role == .owner {
            VStack(alignment: .leading, spacing: 8) {
                Button(L("Invite a member or device")) { Task { await self.teamStore.invite() } }
                    .disabled(self.teamStore.isBusy)
                if let code = self.teamStore.inviteCode {
                    Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                    if let expiry = self.teamStore.inviteExpiresAt {
                        HStack {
                            Text(L("Invitation expires"))
                            Text(expiry, style: .date)
                            Text(expiry, style: .time)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(L("Send the service address and this one-use invitation through a trusted channel."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func deviceUsage(_ deviceID: String) -> some View {
        if let snapshot = self.teamStore.snapshots.first(where: { $0.deviceID == deviceID }) {
            HStack(spacing: 6) {
                Text(L("Updated"))
                Text(Date(timeIntervalSince1970: snapshot.updatedAt), style: .relative)
                if snapshot.payload.metadata?.status != .ready {
                    Text(L("Partial or unavailable usage"))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if let day = self.teamStore.currentPlan?.basis.localDate,
               let usage = snapshot.payload.days[day]
            {
                if let cost = usage.cost {
                    LabeledContent(
                        L("Shared-day estimated cost (USD)"),
                        value: cost.formatted(.currency(code: "USD")))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(L("Shared-day cost is unavailable"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text(L("No shared usage snapshot yet"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var availableDeviceIDs: [String] {
        var ids = Set(self.teamStore.identity?.members.map(\.deviceID) ?? [])
        ids.formUnion(self.teamStore.snapshots.map(\.deviceID))
        ids.formUnion(self.draft.groups.flatMap(\.deviceIDs))
        if let id = self.teamStore.connection?.deviceID { ids.insert(id) }
        return ids.sorted()
    }

    private var hasChanges: Bool {
        self.draft != self.original
    }

    private var validDraft: Bool {
        (try? self.draft.validate()) != nil
    }

    private func reloadDraft() {
        let groups = self.teamStore.sharedSettings.value?.groups ?? CockpitTeamGroups()
        self.draft = groups
        self.original = groups
        self.draftRevision = self.teamStore.sharedSettings.revision
    }

    private var budgetHasChanges: Bool {
        self.personalBudget != self.originalPersonalBudget || self.risk != self.originalRisk
    }

    private var budgetActionsDisabled: Bool {
        self.teamStore.isBusy || self.teamStore.currentPlan == nil || !self.teamStore.accountMatches
            || self.teamStore.connection?.enabled != true || self.originalPlan != self.teamStore.currentPlan
    }

    private func reloadBudget() {
        if let person = self.teamStore.currentPerson {
            self.personalBudget = self.teamStore.allocations[person.id] ?? 0
        }
        self.risk = self.teamStore.currentPlan?.risk.value ?? 0
        self.originalPersonalBudget = self.personalBudget
        self.originalRisk = self.risk
        self.originalPlan = self.teamStore.currentPlan
    }

    private func addPerson() {
        let base = L("New member")
        var name = base
        var suffix = 2
        while self.draft.groups.contains(where: { $0.name == name }) {
            name = "\(base) \(suffix)"
            suffix += 1
        }
        self.draft.groups.append(CockpitTeamPerson(id: UUID().uuidString, name: name))
    }

    private func removePerson(_ id: String) {
        self.draft.groups.removeAll { $0.id == id }
        if self.draft.defaultGroupID == id { self.draft.defaultGroupID = nil }
    }

    private func assignment(_ deviceID: String) -> Binding<String> {
        Binding(
            get: { self.draft.groups.first(where: { $0.deviceIDs.contains(deviceID) })?.id ?? "" },
            set: { personID in
                for index in self.draft.groups.indices {
                    self.draft.groups[index].deviceIDs.removeAll { $0 == deviceID }
                    if self.draft.groups[index].id == personID {
                        self.draft.groups[index].deviceIDs.append(deviceID)
                    }
                }
            })
    }

    private func deviceName(_ id: String) -> String {
        self.teamStore.identity?.members.first(where: { $0.deviceID == id })?.displayName
            ?? self.teamStore.snapshots.first(where: { $0.deviceID == id })?.displayName ?? id
    }

    private func canRevoke(_ id: String) -> Bool {
        self.teamStore.connection?.role == .owner && id != self.teamStore.connection?.deviceID
            && self.teamStore.identity?.members.contains(where: { $0.deviceID == id }) == true
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1))) + "%"
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
