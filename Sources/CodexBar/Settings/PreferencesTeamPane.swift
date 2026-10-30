import CodexBarCore
import SwiftUI

@MainActor
struct PreferencesTeamPane: View {
    @Bindable var teamStore: CockpitTeamStore
    @State private var endpoint = ""
    @State private var spaceName = ""
    @State private var deviceName = ""
    @State private var bootstrapSecret = ""
    @State private var inviteCode = ""
    @State private var createSpace = true
    @State private var confirmedLogOwnership = false
    @State private var confirmsDisconnect = false

    var body: some View {
        Form {
            if self.teamStore.hasPendingEnrollment {
                Section {
                    Text(L("Keep this app open and retry saving the connection to preserve access."))
                    Button(L("Retry saving connection")) { Task { await self.teamStore.retryEnrollment() } }
                        .disabled(self.teamStore.isBusy)
                }
            }
            if let connection = self.teamStore.connection {
                Section {
                    LabeledContent(L("Shared space"), value: connection.spaceName)
                    LabeledContent(L("Service address"), value: connection.endpoint)
                        .textSelection(.enabled)
                    LabeledContent(L("This device"), value: connection.deviceName)
                    Toggle(L("Enable team synchronization"), isOn: Binding(
                        get: { self.teamStore.connection?.enabled ?? false },
                        set: { self.teamStore.setEnabled($0) }))
                    Text(self.teamStore.uploadStatus).foregroundStyle(.secondary)
                    if let date = self.teamStore.lastSyncedAt {
                        LabeledContent {
                            Text(date, style: .relative)
                        } label: {
                            Text(L("Last synchronized"))
                        }
                    }
                    Button(L("Synchronize now")) { Task { await self.teamStore.refresh() } }
                        .disabled(self.teamStore.isBusy || !connection.enabled)
                } header: {
                    Text(L("Team synchronization"))
                }
                self.accountSection
                self.sharingSection
                if connection.role == .owner {
                    Section {
                        Text(L("Pause synchronization to keep this space's owner access recoverable."))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button(L("Disconnect this device"), role: .destructive) { self.confirmsDisconnect = true }
                            .disabled(self.teamStore.isBusy)
                    } footer: {
                        Text(L("Disconnecting removes this Mac's saved connection. Shared server data is retained."))
                    }
                }
            } else {
                self.enrollmentSection
            }
            Section {
                Text(
                    L(
                        "One space represents one Codex account shared by all members."))
                Text(
                    L("Member budgets are cooperative plans. They do not transfer credits or enforce provider limits."))
                Text(L("Shared plans use UTC+8, independently of the calendar's reporting time zone."))
                Text(
                    L(
                        "Members and the server operator can read shared data. Encryption is not end-to-end."))
                Text(L("API keys, provider tokens, prompts, task names, and personal feelings are not uploaded."))
            } header: {
                Text(L("Scope and privacy"))
            }
            if let error = self.teamStore.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
            }
            if self.teamStore.isBusy { ProgressView().controlSize(.small) }
        }
        .formStyle(.grouped)
        .onAppear {
            if self.deviceName.isEmpty { self.deviceName = L("My Mac") }
        }
        .onChange(of: self.endpoint) { _, _ in self.clearEnrollmentSecrets() }
        .onChange(of: self.createSpace) { _, _ in self.clearEnrollmentSecrets() }
        .onDisappear { self.clearEnrollmentSecrets() }
        .confirmationDialog(
            L("Disconnect this device?"),
            isPresented: self.$confirmsDisconnect,
            titleVisibility: .visible)
        {
            Button(L("Disconnect"), role: .destructive) {
                self.teamStore.disconnect()
                self.confirmedLogOwnership = false
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The server keeps previously shared data. Use a new invitation to connect again."))
        }
    }

    private var enrollmentSection: some View {
        PreferencesTeamSetupSection(
            endpoint: self.$endpoint,
            spaceName: self.$spaceName,
            deviceName: self.$deviceName,
            bootstrapSecret: self.$bootstrapSecret,
            inviteCode: self.$inviteCode,
            createSpace: self.$createSpace,
            canEnroll: self.canEnroll,
            isBusy: self.teamStore.isBusy,
            onEnroll: self.enroll)
    }

    private var accountSection: some View {
        Section {
            if self.teamStore.accountMatches {
                Label(L("Current Codex account is bound"), systemImage: "checkmark.circle")
            } else {
                Label(L("Current Codex account is not bound"), systemImage: "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.orange)
            }
            Button(L("Bind current Codex account to this space")) {
                self.teamStore.bindCurrentAccount()
                self.confirmedLogOwnership = false
            }
            .disabled(!self.teamStore.currentAccountAvailable || self.teamStore.isBusy)
            if !self.teamStore.currentAccountAvailable {
                Text(L("Load a valid Codex account and quota observation before binding."))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L("Shared account"))
        } footer: {
            Text(
                L(
                    "Confirm this is the shared account. Switching accounts pauses quota and usage sharing."))
        }
    }

    private var sharingSection: some View {
        Section {
            Toggle(
                L("I confirm this Mac's logs belong to this shared account and were not copied from another device"),
                isOn: self.$confirmedLogOwnership)
                .toggleStyle(.checkbox)
                .disabled(!self.teamStore.accountMatches || self.teamStore.isBusy)
            Toggle(L("Share this device's aggregate usage"), isOn: Binding(
                get: { self.teamStore.connection?.shareUsage ?? false },
                set: { value in
                    guard !value || self.confirmedLogOwnership else { return }
                    self.teamStore.setUsageSharing(value)
                }))
                .disabled(
                    self.teamStore.isBusy || (self.teamStore.connection?.shareUsage != true
                        && (!self.confirmedLogOwnership || !self.teamStore.accountMatches)))
        } header: {
            Text(L("Device usage sharing"))
        } footer: {
            Text(
                L(
                    "Check log ownership before sharing. Budgets still sync when usage sharing is off."))
        }
    }

    private var canEnroll: Bool {
        (try? CockpitTeamClient.normalizeEndpoint(self.endpoint)) != nil
            && !self.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (self.createSpace
                ? !self.spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !self.bootstrapSecret.isEmpty
                : !self.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func clearEnrollmentSecrets() {
        self.bootstrapSecret = ""
        self.inviteCode = ""
    }

    private func enroll() {
        let endpoint = self.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = self.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let space = self.spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let bootstrap = self.bootstrapSecret
        let invitation = self.inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let creating = self.createSpace
        self.bootstrapSecret = ""
        self.inviteCode = ""
        Task {
            if creating {
                await self.teamStore.create(
                    endpoint: endpoint,
                    spaceName: space,
                    deviceName: name,
                    bootstrapSecret: bootstrap)
            } else {
                await self.teamStore.join(endpoint: endpoint, inviteCode: invitation, deviceName: name)
            }
        }
    }
}
