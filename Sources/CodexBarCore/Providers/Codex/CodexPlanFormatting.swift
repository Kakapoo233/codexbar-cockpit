import Foundation

public enum CodexPlanFormatting {
    /// Current Work/Codex plan labels as of 2026-10-29; these never scale measured usage.
    /// Pro 200 retains its higher allowance; only its previously lower allowance doubled.
    static let exactDisplayNames: [String: String] = {
        var names = [
            "pro": "Pro 20x",
            "prolite": "Pro 10x",
            "pro_lite": "Pro 10x",
            "pro-lite": "Pro 10x",
            "pro lite": "Pro 10x",
        ]
        for (price, multiplier) in [(100, 10), (200, 20), (500, 50)] {
            let displayName = "Pro \(multiplier)x"
            // Recognize explicit price-bearing names, without guessing undocumented backend SKUs.
            for alias in ["pro \(price)", "pro_\(price)", "pro-\(price)", "pro\(price)", "pro $\(price)"] {
                names[alias] = displayName
            }
        }
        return names
    }()

    /// Keep share-card values closed and non-identifying, including already formatted snapshots.
    static let sharePlanLabels: [String: String] = {
        var labels = Self.exactDisplayNames
        for (alias, displayName) in Self.exactDisplayNames {
            labels["codex \(alias)"] = displayName
            labels[displayName.lowercased()] = displayName
        }
        return labels
    }()

    private static let uppercaseWords: Set<String> = [
        "cbp",
        "k12",
    ]

    public static func displayName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let lower = raw.lowercased()
        if let exact = Self.exactDisplayNames[lower] {
            return exact
        }

        let cleaned = UsageFormatter.cleanPlanName(raw)
        let candidate = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return raw }

        if let exact = Self.exactDisplayNames[candidate.lowercased()] {
            return exact
        }

        let components = candidate
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return candidate }

        let formatted = components.map(Self.wordDisplayName).joined(separator: " ")
        return formatted.isEmpty ? candidate : formatted
    }

    private static func wordDisplayName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if Self.uppercaseWords.contains(lower) {
            return lower.uppercased()
        }
        if raw == raw.uppercased(), raw.contains(where: \.isLetter) {
            return raw
        }
        if let first = raw.first, first.isLowercase {
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
        return raw
    }
}
