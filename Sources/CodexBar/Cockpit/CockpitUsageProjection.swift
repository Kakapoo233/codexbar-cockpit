import CodexBarCore
import Foundation
import Observation

/// Independent page filters over the existing scanner's publication, without changing statistics preferences.
@MainActor
@Observable
final class CockpitUsageProjection {
    var receiptPeriod = CostReportingPeriod.rolling(days: 30)
    @ObservationIgnored private let controller: SpendDashboardController
    @ObservationIgnored private let nowProvider: @MainActor () -> Date
    @ObservationIgnored private var cacheKey: CacheKey?
    @ObservationIgnored private var models: [CostReportingPeriod: SpendDashboardModel] = [:]

    init(
        controller: SpendDashboardController,
        nowProvider: @escaping @MainActor () -> Date = { Date() })
    {
        self.controller = controller
        self.nowProvider = nowProvider
    }

    var calendar: Calendar {
        self.controller.configuration?.bucketCalendar ?? .current
    }

    var isRefreshing: Bool {
        self.controller.isRefreshing
    }

    var calendarModel: SpendDashboardModel {
        self.model(for: .allTime)
    }

    var receiptModel: SpendDashboardModel {
        self.model(for: self.receiptPeriod)
    }

    private func model(for period: CostReportingPeriod) -> SpendDashboardModel {
        let publication = self.controller.publication
        let configuration = self.controller.configuration
        let calendar = self.calendar
        let now = self.nowProvider()
        let key = CacheKey(
            revision: publication.revision,
            configuration: configuration,
            day: calendar.startOfDay(for: now),
            timeZoneIdentifier: calendar.timeZone.identifier)
        if key != self.cacheKey {
            self.models.removeAll()
            self.cacheKey = key
        }
        if let model = self.models[period] { return model }
        let model = publication.model(
            requestedDays: period.days(now: now, calendar: calendar),
            reportingPeriod: period,
            now: now,
            calendar: calendar,
            preferredCurrencyCode: configuration?.preferredCurrencyCode ?? "auto",
            hiddenSourceIDs: Set(configuration?.hiddenSourceIDs ?? []),
            hideNativeCodexWhenOpenCodexPresent: configuration?.hideNativeCodexCostWhenOpenCodexPresent ?? false,
            selectedDay: nil)
        self.models[period] = model
        return model
    }

    private struct CacheKey: Equatable {
        let revision: UInt64
        let configuration: SpendDashboardConfiguration?
        let day: Date
        let timeZoneIdentifier: String
    }
}
