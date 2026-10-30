import AppKit
import CodexBarCore
import Observation
import SwiftUI

enum CockpitPanelPage: String, CaseIterable, Identifiable {
    case usage, statistics, calendar, receipt

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .usage: L("Usage")
        case .statistics: L("cockpit_ui_statistics")
        case .calendar: L("cockpit_ui_calendar")
        case .receipt: L("cockpit_ui_receipt")
        }
    }

    var symbol: String {
        switch self {
        case .usage: "gauge.with.dots.needle.50percent"
        case .statistics: "chart.xyaxis.line"
        case .calendar: "calendar"
        case .receipt: "receipt"
        }
    }
}

@MainActor
@Observable
final class CockpitPanelNavigation {
    var page: CockpitPanelPage = .usage
    var planningProviders: [UsageProvider] = []
}

extension EnvironmentValues {
    @Entry var cockpitPageActive: Bool = true
}

/// One menu-bar surface. Pages retain their controls while switching, without creating more windows.
@MainActor
struct CockpitPanelView: View {
    @Bindable var settings: SettingsStore
    @Bindable var store: UsageStore
    @Bindable var planStore: CockpitPlanStore
    @Bindable var navigation: CockpitPanelNavigation
    let usageContent: AnyView
    let onSettings: () -> Void
    let onRefresh: () -> Void
    @State private var visitedPages: Set<CockpitPanelPage> = [.usage]

    var body: some View {
        VStack(spacing: 0) {
            self.navigationBar
            Divider()
            ZStack(alignment: .top) {
                ForEach(CockpitPanelPage.allCases) { page in
                    if self.visitedPages.contains(page) || self.navigation.page == page {
                        self.content(for: page)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .environment(\.cockpitPageActive, self.navigation.page == page)
                            .opacity(self.navigation.page == page ? 1 : 0)
                            .allowsHitTesting(self.navigation.page == page)
                            .accessibilityHidden(self.navigation.page != page)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(CockpitPageFocusReset(page: self.navigation.page))
        .onAppear { self.updateData() }
        .onChange(of: self.navigation.page) { oldPage, newPage in
            self.visitedPages.formUnion([oldPage, newPage])
        }
        .onChange(of: self.configuration) { _, _ in self.updateData() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in self.refreshDate() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in self.refreshDate() }
    }

    private var navigationBar: some View {
        ViewThatFits(in: .horizontal) {
            self.navigationButtons(showsTitles: true)
            self.navigationButtons(showsTitles: false)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func navigationButtons(showsTitles: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(CockpitPanelPage.allCases) { page in
                Button {
                    self.navigation.page = page
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: page.symbol)
                        if showsTitles { Text(page.title) }
                    }
                    .font(.system(size: 13, weight: self.navigation.page == page ? .semibold : .regular))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        self.navigation.page == page ? Color.accentColor.opacity(0.15) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(page.title)
                .accessibilityLabel(page.title)
                .accessibilityIdentifier("cockpit-panel-page-\(page.rawValue)")
                .accessibilityAddTraits(self.navigation.page == page ? .isSelected : [])
            }
            Divider().frame(height: 22)
            Button(action: self.onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("Refresh"))
            .accessibilityLabel(L("Refresh"))
            .disabled(self.navigation
                .page != .usage && (!self.settings.costUsageEnabled || self.controller.isRefreshing))
            Button(action: self.onSettings) {
                Image(systemName: "gearshape")
            }
            .help(L("Settings..."))
            .accessibilityLabel(L("Settings..."))
        }
    }

    @ViewBuilder
    private func content(for page: CockpitPanelPage) -> some View {
        switch page {
        case .usage:
            GeometryReader { geometry in
                self.usagePage(layout: CockpitPanelLayout(width: geometry.size.width))
            }
        case .statistics:
            SpendDashboardPane(settings: self.settings, store: self.store)
        case .calendar:
            CockpitCalendarView(controller: self.controller, planStore: self.planStore, todayTokens: self.todayTokens)
        case .receipt:
            CockpitReceiptBrowserView(controller: self.controller, hidePersonalInfo: self.settings.hidePersonalInfo)
        }
    }

    @ViewBuilder
    private func usagePage(layout: CockpitPanelLayout) -> some View {
        if layout.usesSidebar {
            HStack(alignment: .top, spacing: CockpitPanelLayout.columnSpacing) {
                ScrollView {
                    self.usageContent.padding(.bottom, 12)
                }
                .frame(width: layout.mainColumnWidth)
                .accessibilityIdentifier("cockpit-usage-main-column")
                ScrollView {
                    CockpitDailyAdviceView(
                        planStore: self.planStore,
                        providers: self.navigation.planningProviders,
                        layout: .sidebar)
                        .padding(.bottom, 12)
                }
                .frame(width: CockpitPanelLayout.sidebarWidth)
                .accessibilityIdentifier("cockpit-usage-advice-column")
            }
            .padding(.horizontal, CockpitPanelLayout.contentInset)
            .padding(.top, 14)
            .accessibilityIdentifier("cockpit-usage-wide-layout")
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    CockpitDailyAdviceView(planStore: self.planStore, providers: self.navigation.planningProviders)
                    self.usageContent
                }
                .padding(.horizontal, CockpitPanelLayout.contentInset)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            .accessibilityIdentifier("cockpit-usage-compact-layout")
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

    private func refreshDate() {
        self.controller.refreshDateWindow()
        self.planStore.ingest(self.store)
    }

    private func todayTokens(for provider: UsageProvider, calendar: Calendar) -> Int? {
        let expected = provider == .codex ? "codex:ambient" : "claude"
        return CockpitLocalComfortProjection.tokens(
            snapshot: self.store.tokenSnapshotForCurrentProviderConfig(for: provider)?.snapshot,
            isAmbient: self.store.tokenCostScope(for: provider).signature == expected,
            bucketCalendar: self.settings.costUsageBucketCalendar,
            calendar: calendar)
    }
}

/// A retained hidden page must not keep its search field as the keyboard destination.
private struct CockpitPageFocusReset: NSViewRepresentable {
    let page: CockpitPanelPage

    func makeCoordinator() -> Coordinator { Coordinator(page: self.page) }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.page != self.page else { return }
        context.coordinator.page = self.page
        view.window?.makeFirstResponder(nil)
    }

    final class Coordinator {
        var page: CockpitPanelPage

        init(page: CockpitPanelPage) { self.page = page }
    }
}
