import CodexBarCore
import SwiftUI

@MainActor
struct PreferencesTeamRosterSections: View {
    let teamStore: CockpitTeamStore
    @State private var draft = CockpitTeamGroups()
    @State private var original = CockpitTeamGroups()
    @State private var draftRevision = 0
    @State private var revokingDeviceID: String?

    var body: some View {
        self.membersSection
            .onChange(of: self.teamStore.sharedSettings, initial: true) { _, _ in
                if !self.hasChanges { self.reloadDraft() }
            }
        self.devicesSection
            .confirmationDialog(
                L("Revoke device access?"),
                isPresented: Binding(
                    get: { self.revokingDeviceID != nil },
                    set: { if !$0 { self.revokingDeviceID = nil } }),
                titleVisibility: .visible)
            {
                if let id = self.revokingDeviceID {
                    Button(L("Revoke access"), role: .destructive) {
                        Task { await self.teamStore.revoke(deviceID: id) }
                        self.revokingDeviceID = nil
                    }
                }
                Button(L("Cancel"), role: .cancel) { self.revokingDeviceID = nil }
            } message: {
                Text(L("This device will lose access. Previously shared data and other devices' caches are retained."))
            }
        if self.teamStore.connection?.role == .owner {
            self.invitationSection
        }
    }

    private var membersSection: some View {
        Section {
            if self.draft.groups.isEmpty {
                Text(L("No members yet. Add a member, then assign their devices below."))
                    .foregroundStyle(.secondary)
            }
            ForEach(self.$draft.groups) { $person in
                HStack {
                    TextField(L("Member name"), text: $person.name)
                    Button(role: .destructive) { self.removePerson(person.id) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .help(L("Remove this member and leave their devices unassigned."))
                    .accessibilityLabel(L("Remove this member and leave their devices unassigned."))
                }
            }
            Button(L("Add member"), systemImage: "plus") { self.addPerson() }
                .disabled(self.draft.groups.count >= 32)
        } header: {
            Text(L("Members"))
        }
    }

    private var devicesSection: some View {
        Section {
            ForEach(self.availableDeviceIDs, id: \.self) { deviceID in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(self.deviceName(deviceID), systemImage: "desktopcomputer")
                        if deviceID == self.teamStore.connection?.deviceID {
                            Text(L("This device")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if self.canRevoke(deviceID) {
                            Button(L("Revoke"), role: .destructive) { self.revokingDeviceID = deviceID }
                                .disabled(self.mutationDisabled)
                        }
                    }
                    Picker(L("Assigned member"), selection: self.assignment(deviceID)) {
                        Text(L("Unassigned")).tag("")
                        ForEach(self.draft.groups) { person in
                            Text(person.name).tag(person.id)
                        }
                    }
                }
            }
            if self.hasChanges, self.draftIsStale {
                Label(
                    L("Another device changed the members. Reload before applying your changes again."),
                    systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(L("Reload")) { self.reloadDraft() }
                Button(L("Save members and devices"), action: self.saveDraft)
                    .disabled(!self.hasChanges || !self.validDraft || self.draftIsStale || self.mutationDisabled)
            }
        } header: {
            Text(L("Devices"))
        } footer: {
            Text(L("Each device belongs to at most one member. Unassigned devices remain separate."))
        }
    }

    private var invitationSection: some View {
        Section {
            Button(L("Invite a member or device")) { Task { await self.teamStore.invite() } }
                .disabled(self.mutationDisabled)
            if let code = self.teamStore.inviteCode {
                Text(code).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                if let expiry = self.teamStore.inviteExpiresAt {
                    LabeledContent(L("Invitation expires")) {
                        Text(expiry, format: .dateTime)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Text(L("Send the service address and this one-use invitation through a trusted channel."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Invitations"))
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

    private var draftIsStale: Bool {
        self.draftRevision != self.teamStore.sharedSettings.revision
    }

    private var mutationDisabled: Bool {
        self.teamStore.isBusy || self.teamStore.connection?.enabled != true
    }

    private func reloadDraft() {
        let groups = self.teamStore.sharedSettings.value?.groups ?? CockpitTeamGroups()
        self.draft = groups
        self.original = groups
        self.draftRevision = self.teamStore.sharedSettings.revision
    }

    private func saveDraft() {
        let value = self.draft
        let revision = self.draftRevision
        Task {
            await self.teamStore.saveGroups(value, expectedRevision: revision)
            if self.teamStore.sharedSettings.value?.groups == value {
                self.original = value
                self.draftRevision = self.teamStore.sharedSettings.revision
            }
        }
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
}
