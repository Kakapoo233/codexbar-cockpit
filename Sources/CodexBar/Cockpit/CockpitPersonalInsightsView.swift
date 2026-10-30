import CodexBarCore
import SwiftUI

struct CockpitPersonalInsightsView: View {
    let model: CockpitPersonalUsageModel
    let status: CockpitDayStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("cockpit_ui_personal_title")).font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                if let reference = self.model.referencePercent(status: self.status) {
                    Text(cockpitLocalizedPercent(reference)).font(.callout.monospacedDigit())
                }
            }
            Text(self.statusText).font(.caption).foregroundStyle(.secondary)
            Text(L(
                "cockpit_ui_personal_coverage",
                self.model.eligibleDayCount.formatted(.number.locale(codexBarLocalizedLocale())),
                self.model.plannedDayCount.formatted(.number.locale(codexBarLocalizedLocale())),
                self.model.activeDayCount.formatted(.number.locale(codexBarLocalizedLocale()))))
                .font(.caption2).foregroundStyle(.secondary)
            if let validation = self.model.validation {
                Text(L(
                    "cockpit_ui_personal_holdout",
                    validation.baselineMeanAbsoluteError.formatted(
                        .number.precision(.fractionLength(1)).locale(codexBarLocalizedLocale())),
                    validation.personalMeanAbsoluteError.formatted(
                        .number.precision(.fractionLength(1)).locale(codexBarLocalizedLocale()))))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Text(L("cockpit_ui_personal_note"))
                .font(.caption2).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .accessibilityIdentifier("cockpit-personal-insights")
    }

    private var statusText: String {
        switch self.model.status {
        case .collecting: L("cockpit_ui_personal_collecting")
        case .stale: L("cockpit_ui_personal_stale")
        case .distributionDrift: L("cockpit_ui_personal_drift")
        case .noValidationGain: L("cockpit_ui_personal_no_gain")
        case .ready: L("cockpit_ui_personal_ready")
        }
    }
}
