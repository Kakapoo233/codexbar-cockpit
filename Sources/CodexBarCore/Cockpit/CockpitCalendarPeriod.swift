import Foundation

public enum CockpitCalendarScale: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case quarter
    case year

    public var id: String {
        self.rawValue
    }

    fileprivate var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .quarter: .quarter
        case .year: .year
        }
    }
}

/// A half-open local-calendar interval. Never derives day boundaries by adding fixed seconds.
public struct CockpitCalendarPeriod: Equatable, Sendable {
    public let scale: CockpitCalendarScale
    public let start: Date
    public let end: Date

    public init(containing date: Date, scale: CockpitCalendarScale, calendar: Calendar) {
        let interval = calendar.dateInterval(of: scale.component, for: date)
            ?? calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: date, duration: 0)
        self.scale = scale
        self.start = interval.start
        self.end = interval.end
    }

    public func contains(_ date: Date) -> Bool {
        date >= self.start && date < self.end
    }

    public func days(calendar: Calendar, through lastDate: Date? = nil) -> [Date] {
        let limit = lastDate.map { min(calendar.startOfDay(for: $0), self.end) }
        var days: [Date] = []
        var cursor = self.start
        while cursor < self.end, limit.map({ cursor <= $0 }) ?? true {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return days
    }

    public func shifted(by offset: Int, calendar: Calendar) -> Self {
        // Calendar quarter arithmetic is not supported consistently across Foundation versions.
        let component: Calendar.Component = self.scale == .quarter ? .month : self.scale.component
        let amount = self.scale == .quarter ? offset.multipliedReportingOverflow(by: 3) : (
            partialValue: offset,
            overflow: false)
        guard !amount.overflow,
              let date = calendar.date(byAdding: component, value: amount.partialValue, to: self.start)
        else { return self }
        return Self(containing: date, scale: self.scale, calendar: calendar)
    }
}
