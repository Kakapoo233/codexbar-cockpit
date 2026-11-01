import AppKit
import SwiftUI

@MainActor
struct ICloudSyncPane: View {
    @Bindable var settings: SettingsStore
    @Bindable var state: CloudSyncState

    private static let privacyNote =
        "API keys, cookies, login tokens, session transcripts and team credentials never enter these files."
    private static let transferNote =
        "Apple handles upload and download. " +
        "A local file exchange does not confirm delivery to another device."
    private static let planningNote =
        "Daily recommendations are calculated locally. " +
        "Local token totals and raw usage logs are not synchronized."

    var body: some View {
        Form {
            Section {
                Toggle(
                    L("Sync settings, calendar feedback, and personal caps"),
                    isOn: Binding(
                        get: { self.state.drive.enabled },
                        set: { self.state.drive.setEnabled($0) }))
                    .toggleStyle(.checkbox)
                HStack {
                    Button(L("Sync now")) { self.state.drive.synchronize() }
                        .disabled(!self.state.drive.enabled || self.state.drive.isSynchronizing)
                    Button(L("Open sync folder")) { self.openSyncFolder() }
                        .disabled(self.state.drive.directoryURL == nil)
                    if self.state.drive.isSynchronizing {
                        ProgressView().controlSize(.small)
                    }
                }
                if let directory = self.state.drive.directoryURL {
                    LabeledContent(L("Sync folder")) {
                        Text(directory.path).font(.caption).textSelection(.enabled)
                    }
                }
            } header: {
                Text(L("iCloud Drive"))
            } footer: {
                SettingsSectionFooter(L(Self.privacyNote))
            }

            Section {
                if let error = self.state.drive.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                } else {
                    Text(self.statusText)
                }
                LabeledContent(
                    L("Last local file exchange"),
                    value: self.state.drive.lastSynchronizedAt?.relativeDescription() ?? L("Never"))
                LabeledContent(L("Devices with sync files"), value: String(self.state.drive.deviceCount))
                if self.state.drive.lastSynchronizedAt != nil {
                    Text(self.uploadStatusText).foregroundStyle(.secondary)
                }
            } header: {
                Text(L("Status"))
            } footer: {
                SettingsSectionFooter(L(Self.transferNote))
            }

            Section {
                Text(L(Self.planningNote))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        if !self.state.drive.enabled { return L("iCloud Drive is off.") }
        if self.state.drive.isSynchronizing { return L("File sync in progress…") }
        return self.state.drive.lastSynchronizedAt == nil
            ? L("Waiting for the first file exchange.") : L("Files are up to date on this Mac.")
    }

    private var uploadStatusText: String {
        switch self.state.drive.uploadedToICloud {
        case true: L("iCloud upload confirmed")
        case false: L("Waiting for iCloud upload")
        case nil: L("Cloud upload status unavailable")
        }
    }

    private func openSyncFolder() {
        guard var directory = self.state.drive.directoryURL else { return }
        while !FileManager.default.fileExists(atPath: directory.path), directory.path != "/" {
            directory.deleteLastPathComponent()
        }
        if directory.path != "/" { NSWorkspace.shared.open(directory) }
    }
}
