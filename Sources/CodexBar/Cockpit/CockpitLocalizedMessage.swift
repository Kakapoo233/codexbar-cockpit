import Foundation

/// Retain the message's meaning until display so stored errors follow application language changes.
struct CockpitLocalizedMessage {
    let key: String
    private let arguments: [String]
    private let date: Date?

    init(_ key: String, _ arguments: String...) {
        self.key = key
        self.arguments = arguments
        self.date = nil
    }

    init(_ key: String, date: Date) {
        self.key = key
        self.arguments = []
        self.date = date
    }

    var text: String {
        let arguments = self.date.map { [Self.dateText($0)] } ?? self.arguments
        return String(format: L(self.key), locale: codexBarLocalizedResourceLocale(), arguments: arguments)
    }

    static func dateText(_ date: Date) -> String {
        let zone = TimeZone.current
        var style = Date.FormatStyle.dateTime.year().month(.abbreviated).day().hour().minute()
            .locale(codexBarLocalizedLocale())
        style.timeZone = zone
        return "\(date.formatted(style)) \(zone.abbreviation(for: date) ?? zone.identifier)"
    }
}

func cockpitLocalizedPercent(_ value: Double) -> String {
    (value / 100).formatted(.percent.precision(.fractionLength(1)).locale(codexBarLocalizedResourceLocale()))
}
