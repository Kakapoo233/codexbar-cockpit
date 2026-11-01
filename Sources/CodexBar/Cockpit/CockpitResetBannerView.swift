import CodexBarCore
import SwiftUI

enum CockpitResetBannerProjection {
    /// Only a dated, still-pending announcement can appear as a confirmed countdown.
    /// Expired status is retained in the calendar, but cannot keep an old homepage banner alive.
    static func announcement(status: CockpitResetStatus?, now: Date) -> CockpitScheduledReset? {
        guard let status,
              (-300...15 * 60).contains(now.timeIntervalSince(status.generatedAt)),
              let reset = status.scheduledReset, reset.isPending(at: now),
              let date = reset.scheduledFor, date > now else { return nil }
        return reset
    }
}

@MainActor
struct CockpitResetBannerView: View {
    let store: CockpitResetHistoryStore
    let calendar: Calendar
    let showCalendar: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let reset = CockpitResetBannerProjection.announcement(status: self.store.status, now: context.date),
               let date = reset.scheduledFor
            {
                Button(action: self.showCalendar) {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.teal)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("cockpit_reset_banner_title"))
                                .font(.callout.weight(.semibold))
                            Text("\(cockpitResetDateText(date, calendar: self.calendar)) · \(reset.kind.cockpitTitle)")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(L("cockpit_reset_banner_countdown", UsageFormatter.resetCountdownDuration(
                            from: date, now: context.date)))
                            .font(.callout.monospacedDigit().weight(.medium))
                            .fixedSize()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.teal.opacity(0.08))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("cockpit_ui_calendar"))
                .accessibilityIdentifier("cockpit-confirmed-reset-banner")
            }
        }
    }
}
