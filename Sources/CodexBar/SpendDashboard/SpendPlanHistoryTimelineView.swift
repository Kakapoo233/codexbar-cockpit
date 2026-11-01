import Charts
import CodexBarCore
import SwiftUI

/// Statistics uses captured calendar time; compact menu charts retain their reset-cycle presentation.
@MainActor
struct SpendPlanHistoryTimelineView: View {
    private let provider: UsageProvider
    private let visibleSeries: [PlanUtilizationHistoryChartMenuView.VisibleSeries]
    private let models: [String: SpendPlanHistoryTimelineModel]
    private let emptyModel: SpendPlanHistoryTimelineModel
    private let calendar: Calendar
    @State private var selectedSeriesID: String?
    @State private var inspectedDate: Date?

    init(
        provider: UsageProvider,
        histories: [PlanUtilizationSeriesHistory],
        snapshot: UsageSnapshot? = nil,
        period: CostReportingPeriod,
        referenceDate: Date,
        calendar: Calendar)
    {
        self.provider = provider
        self.calendar = calendar
        let series = PlanUtilizationHistoryChartMenuView.visibleSeries(
            histories: histories, provider: provider, snapshot: snapshot)
        self.visibleSeries = series
        self.models = Dictionary(uniqueKeysWithValues: series.map {
            ($0.id, SpendPlanHistoryTimelineModel.build(
                history: $0.history, period: period, now: referenceDate, calendar: calendar))
        })
        self.emptyModel = SpendPlanHistoryTimelineModel.build(
            history: nil, period: period, now: referenceDate, calendar: calendar)
    }

    private var selection: PlanUtilizationHistoryChartMenuView.VisibleSeries? {
        self.visibleSeries.first { $0.id == self.selectedSeriesID } ?? self.visibleSeries.first
    }

    var model: SpendPlanHistoryTimelineModel {
        self.selection.flatMap { self.models[$0.id] } ?? self.emptyModel
    }

    private var color: Color {
        let accent = ProviderAccentPalette.color(for: self.provider)
        return Color(red: accent.red, green: accent.green, blue: accent.blue)
    }

    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: 10) {
            Text(L("cockpit_plan_history_title")).font(.subheadline.weight(.semibold))
            Text(self.rangeText(model.domain)).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("spend-plan-history-range")
            if self.visibleSeries.count > 1 {
                Picker(selection: Binding(
                    get: { self.selection?.id ?? "" },
                    set: { self.selectedSeriesID = $0; self.inspectedDate = nil }))
                {
                    ForEach(self.visibleSeries) { series in Text(series.title).tag(series.id) }
                } label: { Text(L("Plan Usage")) }
                    .labelsHidden()
                    .pickerStyle(.segmented)
            }
            self.chart(model)
            if let date = self.inspectedDate, let point = model.point(nearestTo: date) {
                Text("\(self.dateText(point.capturedAt, includesTime: true)) · "
                    + "\(cockpitLocalizedPercent(point.remainingPercent)) \(L("Usage remaining"))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let range = model.recordedRange {
                Text(L(
                    "cockpit_plan_history_coverage",
                    self.dateText(range.lowerBound, includesTime: true),
                    self.dateText(range.upperBound, includesTime: true),
                    model.sampleCount))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(L("cockpit_plan_history_partial")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .environment(\.timeZone, self.calendar.timeZone)
        .environment(\.calendar, self.calendar)
        .onChange(of: self.model.domain) { _, _ in self.inspectedDate = nil }
        .accessibilityIdentifier("spend-plan-history-timeline")
    }

    private func chart(_ model: SpendPlanHistoryTimelineModel) -> some View {
        Chart {
            ForEach(model.drawingPoints) { point in
                LineMark(
                    x: .value("Time", point.capturedAt),
                    y: .value(L("Usage remaining"), point.remainingPercent),
                    series: .value("Recorded segment", point.segmentID))
                    .foregroundStyle(self.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                PointMark(
                    x: .value("Time", point.capturedAt),
                    y: .value(L("Usage remaining"), point.remainingPercent))
                    .foregroundStyle(self.color)
                    .symbolSize(12)
            }
        }
        .chartXScale(domain: model.domain)
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let percent = value.as(Double.self) { Text(cockpitLocalizedPercent(percent)) }
                }
            }
        }
        .chartYAxisLabel(L("Usage remaining"))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(self.axisDateText(date, domain: model.domain))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: 180)
        .overlay {
            if model.points.isEmpty {
                Text(L("cockpit_plan_history_empty"))
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(24)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let frame = proxy.plotFrame.map({ geometry[$0] }), frame.contains(location),
                                  let date = proxy.value(atX: location.x - frame.minX, as: Date.self)
                            else { self.inspectedDate = nil; return }
                            self.inspectedDate = date
                        case .ended:
                            self.inspectedDate = nil
                        }
                    }
            }
        }
        .accessibilityLabel(L("cockpit_plan_history_title"))
        .accessibilityValue(self.rangeText(model.domain) + " · " + codexBarLocalizedInteger(model.sampleCount))
    }

    private func rangeText(_ range: ClosedRange<Date>) -> String {
        self.dateText(range.lowerBound) + " – " + self.dateText(range.upperBound.addingTimeInterval(-0.001))
    }

    private func axisDateText(_ date: Date, domain: ClosedRange<Date>) -> String {
        let isSingleDay = self.calendar.isDate(
            domain.lowerBound, inSameDayAs: domain.upperBound.addingTimeInterval(-0.001))
        var style = isSingleDay
            ? Date.FormatStyle.dateTime.hour().minute()
            : Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.locale = codexBarLocalizedLocale()
        style.timeZone = self.calendar.timeZone
        return date.formatted(style)
    }

    private func dateText(_ date: Date, includesTime: Bool = false) -> String {
        var style = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        if includesTime { style = style.hour().minute() }
        style.locale = codexBarLocalizedLocale()
        style.timeZone = self.calendar.timeZone
        return date.formatted(style)
    }
}
