import AppKit
import SwiftUI

@MainActor
struct CockpitDashboardView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var planStore: CockpitPlanStore
    @State private var selection = CockpitTab.overview
    @State private var migrationMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("cockpit_ui_brand")).font(.title2.weight(.semibold))
                    Text(L("cockpit_ui_subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("cockpit_ui_import")) {
                    do {
                        let count = try CockpitSettingsMigration.importFromInstalledCodexBar(into: self.settings)
                        self.migrationMessage = L("cockpit_ui_import_success", count)
                    } catch {
                        self.migrationMessage = L("cockpit_ui_import_error", error.localizedDescription)
                    }
                }
                if self.controller.isRefreshing {
                    ProgressView().controlSize(.small)
                    Text(L("cockpit_ui_updating")).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    self.store.refreshSpendDashboard(accounts: SpendDashboardSource.codexRequests(
                        settings: self.settings,
                        store: self.store))
                } label: {
                    Label(L("cockpit_ui_refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(self.controller.isRefreshing || !self.settings.costUsageEnabled)
            }
            .padding(20)
            Divider()
            TabView(selection: self.$selection) {
                CockpitOverviewView(settings: self.settings, store: self.store, planStore: self.planStore)
                    .tabItem { Label(L("cockpit_ui_plan"), systemImage: "gauge.with.dots.needle.50percent") }
                    .tag(CockpitTab.overview)
                SpendDashboardPane(settings: self.settings, store: self.store)
                    .tabItem { Label(L("cockpit_ui_statistics"), systemImage: "chart.xyaxis.line") }
                    .tag(CockpitTab.statistics)
                CockpitCalendarView(controller: self.controller, planStore: self.planStore)
                    .tabItem { Label(L("cockpit_ui_calendar"), systemImage: "calendar") }
                    .tag(CockpitTab.calendar)
                CockpitReceiptBrowserView(controller: self.controller, hidePersonalInfo: self.settings.hidePersonalInfo)
                    .tabItem { Label(L("cockpit_ui_receipt"), systemImage: "receipt") }
                    .tag(CockpitTab.receipt)
            }
            .padding(.top, 12)
        }
        .frame(minWidth: 840, minHeight: 620)
        .alert(L("cockpit_ui_import_title"), isPresented: Binding(
            get: { self.migrationMessage != nil },
            set: { if !$0 { self.migrationMessage = nil } }))
        {
            Button(L("cockpit_ui_ok")) { self.migrationMessage = nil }
        } message: {
            Text(self.migrationMessage ?? "")
        }
        .onAppear { self.updateData() }
            .onChange(of: self.configuration) { _, _ in self.updateData() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                self.controller.refreshDateWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                self.controller.refreshDateWindow()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                self.controller.refreshDateWindow()
                self.controller.refreshIfStale()
            }
    }

    private var controller: SpendDashboardController {
        self.store.sharedSpendDashboardController()
    }

    private var configuration: SpendDashboardConfiguration {
        SpendDashboardSource.configuration(settings: self.settings, store: self.store)
    }

    private func updateData() {
        self.controller.update(configuration: self.configuration)
        self.controller.refreshIfStale()
    }
}

private enum CockpitTab: Hashable {
    case overview, statistics, calendar, receipt
}
