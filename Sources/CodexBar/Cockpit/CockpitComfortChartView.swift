import Charts
import CodexBarCore
import SwiftUI

extension CockpitFeeling {
    var cockpitTitle: String {
        switch self {
        case .overloaded: L("cockpit_ui_overloaded")
        case .comfortable: L("cockpit_ui_comfortable")
        case .light: L("cockpit_ui_light")
        }
    }

    var cockpitEmoji: String {
        switch self {
        case .overloaded: "😵‍💫"
        case .comfortable: "🙂"
        case .light: "😌"
        }
    }
}

struct CockpitComfortChartView: View {
    let model: CockpitComfortModel
    let records: [CockpitComfortRecord]

    var body: some View {
        GroupBox(L("cockpit_ui_experience")) {
            VStack(alignment: .leading, spacing: 14) {
                if !self.model.observations.isEmpty {
                    Chart {
                        ForEach(self.model.observations) { sample in
                            PointMark(
                                x: .value(L("cockpit_ui_chart_tokens"), Double(sample.totalTokens)),
                                y: .value(L("cockpit_ui_chart_feeling"), sample.score))
                                .foregroundStyle(sample.coverage == .complete ? Color.accentColor : Color.gray)
                        }
                        ForEach(self.model.points) { point in
                            LineMark(
                                x: .value(L("cockpit_ui_chart_tokens"), point.totalTokens),
                                y: .value(L("cockpit_ui_chart_feeling"), point.score))
                                .foregroundStyle(Color.accentColor.opacity(0.6))
                        }
                    }
                    .chartYScale(domain: 0...1.05)
                    .chartXAxisLabel(L("cockpit_ui_chart_tokens"))
                    .frame(height: 220)
                    .accessibilityLabel(L("cockpit_ui_chart_accessibility"))
                }
                if self.model.status == .insufficientData {
                    Text(L("cockpit_ui_chart_insufficient"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(L(
                    "cockpit_ui_comfort_weighted",
                    self.model.recencyWeightedSampleCount.formatted(
                        .number.precision(.fractionLength(1)).locale(codexBarLocalizedLocale()))))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("cockpit_ui_comfort_recency"))
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(self.records.prefix(7)) { record in
                    HStack {
                        Text(record.localDateKey).monospacedDigit()
                        Text(record.feeling.cockpitTitle)
                        Spacer()
                        Text(record.totalTokens
                            .map(UsageFormatter.tokenCountString) ?? L("cockpit_ui_incomplete_tokens"))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if self.records.isEmpty {
                    Text(L("cockpit_ui_empty_feelings"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
        }
    }
}
