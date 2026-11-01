import Charts
import CodexBarCore
import SwiftUI

/// Native rendering of Cockpit's fixed quota-comfort curve and subjective feedback positions.
struct CockpitQuotaComfortChartView: View {
    let model: CockpitQuotaComfortModel
    let records: [CockpitComfortRecord]
    @State private var hoveredID: String?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                self.chart
                HStack(spacing: 16) {
                    ForEach([CockpitFeeling.light, .comfortable, .overloaded], id: \.self) { feeling in
                        Label {
                            Text(feeling.calendarTitle)
                        } icon: {
                            Circle().fill(Self.color(feeling)).frame(width: 7, height: 7)
                        }
                    }
                }
                .font(.caption)
                if let sample = self.model.observations.first(where: { $0.id == self.hoveredID }) {
                    Text(L(
                        "cockpit_comfort_curve_sample",
                        sample.localDateKey,
                        cockpitLocalizedPercent(sample.usedPercent),
                        sample.feeling.calendarTitle))
                        .font(.caption).monospacedDigit()
                    if sample.coverage == .partial {
                        Text(L("cockpit_comfort_quota_partial"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if self.model.status == .baseline {
                    Text(L("cockpit_comfort_curve_empty"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup(L(
                    "cockpit_comfort_curve_details",
                    self.model.sampleCount.formatted(.number.locale(codexBarLocalizedLocale()))))
                {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("cockpit_comfort_curve_explanation"))
                        Text(L("cockpit_comfort_curve_weights"))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                ForEach(self.records.prefix(7)) { record in
                    HStack {
                        Text(record.localDateKey).monospacedDigit()
                        Text(record.feeling.calendarTitle)
                        Spacer()
                        Text(record.usedPercent.map(cockpitLocalizedPercent) ?? L("cockpit_ui_unknown"))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .help(record.coverage == .partial ? L("cockpit_comfort_quota_partial") : "")
                }
            }
            .padding(10)
        } label: {
            HStack {
                Text(L("cockpit_comfort_curve_title"))
                Spacer()
                Text(L(
                    self.model.status == .fitted
                        ? "cockpit_comfort_curve_knee" : "cockpit_comfort_curve_default",
                    cockpitLocalizedPercent(self.model.kneePercent)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(self.model.points) { point in
                LineMark(
                    x: .value(L("cockpit_comfort_curve_x"), point.usedPercent),
                    y: .value(L("cockpit_comfort_curve_y"), point.score))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if self.model.status == .fitted {
                RuleMark(
                    x: .value("k", self.model.kneePercent),
                    yStart: .value("", 0),
                    yEnd: .value("", self.model.score(atUsedPercent: self.model.kneePercent)))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            ForEach(self.model.observations) { sample in
                PointMark(
                    x: .value(L("cockpit_comfort_curve_x"), sample.usedPercent),
                    y: .value(L("cockpit_comfort_curve_y"), sample.score))
                    .foregroundStyle(Self.color(sample.feeling).opacity(0.25 + 0.75 * min(1, sample.weight)))
                    .symbolSize(self.hoveredID == sample.id ? 80 : 42)
                    .accessibilityLabel(L(
                        "cockpit_comfort_curve_sample",
                        sample.localDateKey,
                        cockpitLocalizedPercent(sample.usedPercent),
                        sample.feeling.calendarTitle))
            }
        }
        .chartXScale(domain: 0...self.model.axisMaxPercent)
        .chartYScale(domain: 0...1.05)
        .chartXAxis {
            AxisMarks(values: self.model.axisTicks) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text(cockpitLocalizedPercent(percent))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel {
                    if let score = value.as(Double.self) {
                        Text(cockpitLocalizedPercent(score * 100))
                    }
                }
            }
        }
        .chartXAxisLabel(L("cockpit_comfort_curve_x"))
        .chartYAxisLabel(L("cockpit_comfort_curve_y"))
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            self.hoveredID = self.nearestSample(at: location, proxy: proxy, geometry: geometry)
                        case .ended:
                            self.hoveredID = nil
                        }
                    }
            }
        }
        .frame(height: 230)
        .accessibilityLabel(L("cockpit_comfort_curve_title"))
        .accessibilityValue(L("cockpit_comfort_curve_explanation"))
    }

    private func nearestSample(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) -> String? {
        guard let anchor = proxy.plotFrame else { return nil }
        let frame = geometry[anchor]
        guard frame.insetBy(dx: -10, dy: -10).contains(location) else { return nil }
        let matches = self.model.observations.compactMap { sample -> (String, Double)? in
            guard let x = proxy.position(forX: sample.usedPercent), let y = proxy.position(forY: sample.score)
            else { return nil }
            let distance = hypot(location.x - frame.minX - x, location.y - frame.minY - y)
            return distance <= 18 ? (sample.id, Double(distance)) : nil
        }
        return matches.min { $0.1 < $1.1 }?.0
    }

    private static func color(_ feeling: CockpitFeeling) -> Color {
        switch feeling {
        case .light: .green
        case .comfortable: .blue
        case .overloaded: .orange
        }
    }
}
