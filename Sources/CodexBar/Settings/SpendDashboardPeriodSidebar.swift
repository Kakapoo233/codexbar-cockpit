import CodexBarCore
import SwiftUI

/// The reporting range stays outside the statistics scroll view so it is always reachable.
struct SpendDashboardPeriodSidebar: View {
    static let width: CGFloat = 144
    @Binding var selection: CostReportingPeriod

    private var periods: [CostReportingPeriod] {
        var periods: [CostReportingPeriod] = [
            .rolling(days: 7), .rolling(days: 30), .rolling(days: 90), .monthToDate, .allTime,
        ]
        if !periods.contains(self.selection) {
            periods.append(self.selection)
        }
        return periods
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Time range"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(self.periods, id: \.self) { period in
                let selected = self.selection == period
                Button {
                    self.selection = period
                } label: {
                    HStack(spacing: 6) {
                        Text(Self.title(for: period))
                            .font(.system(size: 13, weight: selected ? .semibold : .regular))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(selected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(selected ? Color.accentColor : Color.secondary)
                .help("\(L("Time range")): \(Self.title(for: period))")
                .accessibilityLabel(Self.title(for: period))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("spend-dashboard-period-\(period.rawValue)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.primary.opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spend-dashboard-range-sidebar")
    }

    private static func title(for period: CostReportingPeriod) -> String {
        switch period {
        case let .rolling(days): spendDashboardDayRangeText(days)
        case .monthToDate: L("Month to date")
        case .allTime: L("All")
        }
    }
}
