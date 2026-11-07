import CodexBarCore
import Foundation

/// Binds calendar actions to the account shown when the date cells were rendered.
@MainActor
struct CockpitCalendarQuotaFeedback {
    private let store: CockpitPlanStore
    private let provider: UsageProvider
    private let accountID: String
    private let calendar: Calendar

    init(store: CockpitPlanStore, provider: UsageProvider, calendar: Calendar) {
        self.store = store
        self.provider = provider
        self.accountID = store.accountID(for: provider)
        self.calendar = calendar
    }

    func canRecord(on day: Date, now: Date = Date()) -> Bool {
        self.store.availableProviders.contains(self.provider)
            && self.store.accountID(for: self.provider) == self.accountID
            && day.timeIntervalSince1970.isFinite && now.timeIntervalSince1970.isFinite
            && self.calendar.startOfDay(for: day) <= self.calendar.startOfDay(for: now)
    }

    func update(_ feeling: CockpitFeeling?, on day: Date, now: Date = Date()) {
        guard self.canRecord(on: day, now: now) else { return }
        if let feeling {
            self.store.setQuotaComfortFeeling(feeling, for: self.provider, on: day, now: now, calendar: self.calendar)
        } else {
            self.store.clearQuotaComfort(for: self.provider, on: day, calendar: self.calendar)
        }
    }
}
