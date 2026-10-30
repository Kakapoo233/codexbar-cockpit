import CodexBarCore
import SwiftUI

/// User-owned service configuration stays in Settings; checks never send enrollment credentials.
@MainActor
struct PreferencesTeamSetupSection: View {
    @Binding var endpoint: String
    @Binding var spaceName: String
    @Binding var deviceName: String
    @Binding var bootstrapSecret: String
    @Binding var inviteCode: String
    @Binding var createSpace: Bool
    let canEnroll: Bool
    let isBusy: Bool
    let onEnroll: () -> Void
    @State private var isChecking = false
    @State private var checkMessage: String?
    @State private var checkSucceeded = false
    @State private var checkID = UUID()
    @State private var checkTask: Task<Void, Never>?

    private var validEndpoint: String? {
        try? CockpitTeamClient.normalizeEndpoint(self.endpoint)
    }

    var body: some View {
        Section {
            Picker(L("Connection method"), selection: self.$createSpace) {
                Text(L("Use my Cloudflare")).tag(true)
                Text(L("Join an existing space")).tag(false)
            }
            .pickerStyle(.segmented)
            Text(self.createSpace
                ? L("Connect to the sync service deployed in your own Cloudflare account.")
                : L("Use the service address and invitation supplied by your team administrator."))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(
                L("Cloudflare Worker URL"),
                text: self.$endpoint,
                prompt: Text(verbatim: "https://your-worker.your-subdomain.workers.dev"))
                .textContentType(.URL)
                .help(L("Paste the deployed Worker's HTTPS address or custom domain, without an API path."))
            if !self.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, self.validEndpoint == nil {
                Label(
                    L("Enter an HTTPS server address without a path, query or credentials."),
                    systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(L("Check service address"), action: self.checkService)
                    .disabled(self.validEndpoint == nil || self.isChecking || self.isBusy)
                    .help(L("Checks service reachability without sending keys, invitations or usage data."))
                if self.isChecking { ProgressView().controlSize(.small) }
            }
            if let checkMessage {
                Label(checkMessage, systemImage: self.checkSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(self.checkSucceeded ? Color.secondary : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField(L("Device display name"), text: self.$deviceName, prompt: Text(L("My Mac")))
                .help(L("A name your teammates can recognize, such as Work Mac or Home Mac."))
            if self.createSpace {
                TextField(L("Shared space name"), text: self.$spaceName, prompt: Text(L("My team")))
                    .help(L("Choose a name for the members sharing this Codex account."))
                SecureField(
                    L("Space creation secret"),
                    text: self.$bootstrapSecret,
                    prompt: Text(verbatim: "BOOTSTRAP_SECRET"))
                    .help(L("Enter the BOOTSTRAP_SECRET you configured for this Worker, not a Cloudflare API token."))
                Text(L("The creation secret is used once to create your space and is not saved by the app."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SecureField(L("Invitation code"), text: self.$inviteCode, prompt: Text(verbatim: "CCI-…"))
                    .help(L("Ask the space owner to generate a new invitation in Members & Devices."))
            }
            Button(self.createSpace ? L("Create and connect") : L("Join shared space"), action: self.onEnroll)
                .disabled(!self.canEnroll || self.isBusy)
        } header: {
            Text(L("Cloudflare synchronization"))
        } footer: {
            Text(
                L(
                    "Each user can connect to their own service. Details are saved on this Mac after joining."))
        }

        Section {
            DisclosureGroup(L("Where do I get these settings?")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("1. Deploy the sync service and its database in your Cloudflare account using the guide."))
                    Text(
                        L(
                            "2. Copy the deployed HTTPS URL: use a workers.dev address or your custom domain."))
                    Text(L("3. Use your configured BOOTSTRAP_SECRET to create a space, or an invitation to join one."))
                    Link(
                        L("Cloudflare deployment guide"),
                        destination: URL(
                            string: "https://github.com/Kakapoo233/codexbar-cockpit/blob/main/cloud/usage-sync-worker/README.md")!)
                    Link(L("Open Cloudflare dashboard"), destination: URL(string: "https://dash.cloudflare.com/")!)
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
            }
        }
        .onChange(of: self.endpoint) { _, _ in self.cancelCheck() }
        .onDisappear { self.cancelCheck() }
    }

    private func checkService() {
        guard let endpoint = self.validEndpoint else { return }
        self.cancelCheck()
        let requestID = self.checkID
        self.isChecking = true
        self.checkTask = Task { @MainActor in
            do {
                try await CockpitTeamClient(endpoint: endpoint).checkService()
                guard !Task.isCancelled, self.checkID == requestID else { return }
                self.checkSucceeded = true
                self
                    .checkMessage =
                    L("Sync service detected. Database access and credentials are checked when joining.")
            } catch {
                guard !Task.isCancelled, self.checkID == requestID else { return }
                self.checkSucceeded = false
                self.checkMessage = error as? CockpitTeamError == .unsupportedProtocol
                    ? L("This address does not identify a supported Codex Cockpit sync service.")
                    : L("The service could not be verified. Check the address, deployment and network, then try again.")
            }
            self.isChecking = false
            self.checkTask = nil
        }
    }

    private func cancelCheck() {
        self.checkID = UUID()
        self.checkTask?.cancel()
        self.checkTask = nil
        self.isChecking = false
        self.checkMessage = nil
    }
}
