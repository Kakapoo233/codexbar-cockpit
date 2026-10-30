import CodexBarCore
import SwiftUI

@MainActor
struct CockpitReceiptBrowserView: View {
    @State private var usage: CockpitUsageProjection
    let hidePersonalInfo: Bool
    @State private var selectedIDs = Set<String>()
    @State private var query = ""
    @State private var receipt: CockpitReceiptModel?
    @State private var metadata: [CockpitTaskIdentity: CockpitTaskLineageMetadata] = [:]
    @State private var conflicting = Set<CockpitTaskIdentity>()
    @State private var isLoadingLineage = true
    @State private var lineageMessageKey: String?

    init(controller: SpendDashboardController, hidePersonalInfo: Bool) {
        self._usage = State(initialValue: CockpitUsageProjection(controller: controller))
        self.hidePersonalInfo = hidePersonalInfo
    }

    private var items: [CockpitReceiptLine] {
        CockpitReceiptModel.items(
            model: self.usage.receiptModel,
            hidePersonalInfo: self.hidePersonalInfo,
            metadata: self.metadata,
            conflicting: self.conflicting)
    }

    private var visibleItems: [CockpitReceiptLine] {
        guard !self.query.isEmpty else { return self.items }
        return self.items.filter {
            $0.title.localizedStandardContains(self.query) || $0.providerName.localizedStandardContains(self.query)
        }
    }

    private var selectedItems: [CockpitReceiptLine] {
        self.items.filter { self.selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            self.header
            Text(L("cockpit_ui_receipt_grouping"))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("cockpit_ui_receipt_scope_note"))
                .font(.caption).foregroundStyle(.secondary)
            if self.isLoadingLineage {
                Label(L("cockpit_ui_loading_lineage"), systemImage: "hourglass").font(.caption)
            } else if let key = self.lineageMessageKey {
                Label(L(key), systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                TextField(L("cockpit_ui_search"), text: self.$query).textFieldStyle(.roundedBorder)
                Button(L("cockpit_ui_select_visible")) { self.selectedIDs.formUnion(self.visibleItems.map(\.id)) }
                    .disabled(self.visibleItems.isEmpty || self.isLoadingLineage)
                Button(L("cockpit_ui_clear_selection")) { self.selectedIDs.removeAll() }
                    .disabled(self.selectedIDs.isEmpty)
            }
            List {
                ForEach(self.visibleItems) { item in
                    Toggle(isOn: self.selectionBinding(item.id)) {
                        self.itemRow(item)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, 5)
                }
            }
            .listStyle(.inset)
            .disabled(self.isLoadingLineage)
            .overlay {
                if self.visibleItems.isEmpty {
                    ContentUnavailableView(
                        self.usage.isRefreshing ? L("cockpit_ui_loading_sessions") : L("cockpit_ui_no_sessions"),
                        systemImage: "text.bubble",
                        description: Text(L("cockpit_ui_no_sessions_detail")))
                }
            }
            HStack {
                Text(L("cockpit_ui_selected_tasks", self.selectedItems.count)).font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    self.receipt = CockpitReceiptModel(items: self.selectedItems, scopeLabel: self.scopeLabel)
                } label: {
                    Label(L("cockpit_ui_preview"), systemImage: "receipt")
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.selectedItems.isEmpty || self.isLoadingLineage)
            }
        }
        .padding(24)
        .task(id: self.lineageSources) { await self.loadLineage() }
        .onChange(of: self.items.map(\.id)) { _, ids in
            self.selectedIDs.formIntersection(ids)
        }
        .onChange(of: self.hidePersonalInfo) { _, _ in
            self.query = ""
            self.receipt = nil
        }
        .sheet(isPresented: Binding(
            get: { self.receipt != nil },
            set: { if !$0 { self.receipt = nil } }))
        {
            if let receipt = self.receipt {
                CockpitReceiptPreview(receipt: receipt)
            }
        }
    }

    private var header: some View {
        HStack {
            Text(L("cockpit_ui_receipt")).font(.title2.weight(.semibold))
            Spacer()
            Picker(L("cockpit_ui_period"), selection: Binding(
                get: { self.usage.receiptPeriod },
                set: { self.usage.receiptPeriod = $0 }))
            {
                Text(L("cockpit_ui_last_7")).tag(CostReportingPeriod.rolling(days: 7))
                Text(L("cockpit_ui_last_30")).tag(CostReportingPeriod.rolling(days: 30))
                Text(L("cockpit_ui_last_90")).tag(CostReportingPeriod.rolling(days: 90))
                Text(L("cockpit_ui_current_month")).tag(CostReportingPeriod.monthToDate)
                Text(L("cockpit_ui_all")).tag(CostReportingPeriod.allTime)
                if case let .rolling(days) = self.usage.receiptPeriod, ![7, 30, 90].contains(days) {
                    Text(L("cockpit_ui_last_days", days)).tag(self.usage.receiptPeriod)
                }
            }
            .frame(width: 180)
        }
    }

    private var scopeLabel: String {
        CockpitReceiptModel.scopeLabel(
            for: self.usage.receiptPeriod,
            timeZone: self.usage.calendar.timeZone)
    }

    private func selectionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { self.selectedIDs.contains(id) },
            set: { selected in
                if selected { self.selectedIDs.insert(id) } else { self.selectedIDs.remove(id) }
            })
    }

    private func itemRow(_ item: CockpitReceiptLine) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).fontWeight(.medium).lineLimit(1)
                Text(item.providerName + (item.sessionCount > 1 ? L(
                    "cockpit_ui_subsession_count",
                    item.sessionCount - 1) : ""))
                    .font(.caption).foregroundStyle(.secondary)
                if item.lineageIsPartial {
                    Text(L("cockpit_ui_partial_lineage")).font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(spendDashboardBreakdownMetricText(
                cost: item.estimatedCost,
                tokens: item.tokens,
                currencyCode: item.currencyCode,
                hasPartialCost: item.costIsPartial,
                hasPartialTokens: item.tokensArePartial))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var lineageSources: [CockpitTaskLineageSource] {
        self.usage.receiptModel.groups.filter { !$0.detailsExcludedFromTotals }.flatMap { group in
            group.sessions.compactMap { row in
                row.toolActivitySource.map { source in
                    CockpitTaskLineageSource(
                        identity: CockpitTaskIdentity(sourceID: row.sourceID, sessionID: row.sessionID),
                        source: source)
                }
            }
        }
    }

    private func loadLineage() async {
        self.isLoadingLineage = true
        self.metadata = [:]
        self.conflicting = []
        self.lineageMessageKey = nil
        do {
            let result = try await CockpitTaskLineageLoader.load(sources: self.lineageSources)
            try Task.checkCancellation()
            self.metadata = result.metadata
            self.conflicting = result.conflicting
            if result.wasLimited || !result.unavailable.isEmpty || !result.conflicting.isEmpty {
                self.lineageMessageKey = "cockpit_ui_lineage_warning"
            }
            self.isLoadingLineage = false
        } catch is CancellationError {
            // The new selection owns loading state; cancelled work cannot publish into it.
        } catch {
            guard !Task.isCancelled else { return }
            self.lineageMessageKey = "cockpit_ui_lineage_error"
            self.isLoadingLineage = false
        }
    }
}
