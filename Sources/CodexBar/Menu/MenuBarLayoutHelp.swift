import CodexBarCore
import Foundation

extension MenuBarLayoutToken {
    // Keep this exhaustive so new layout tokens must receive an explanation.
    // swiftlint:disable:next cyclomatic_complexity
    func editorHelp(provider: UsageProvider? = nil, snapshot: UsageSnapshot? = nil) -> String {
        let description = switch self {
        case .icon: L("menu_bar_help_icon")
        case .providerName: L("menu_bar_help_provider")
        case .accountLabel: L("menu_bar_help_account")
        case .percent(window: .scopedWeekly): L("menu_bar_help_scoped_weekly")
        case .percent(window: .automatic): L("menu_bar_help_automatic")
        case .percent, .lanePercent, .extraPercent: L("menu_bar_help_percent")
        case .pace: L("menu_bar_help_pace")
        case .usageBar: L("menu_bar_help_usage_bar")
        case .progressBar: L("menu_bar_help_progress")
        case .resetCountdown, .windowResetCountdown: L("menu_bar_help_reset_countdown")
        case .resetAbsolute, .windowResetAbsolute: L("menu_bar_help_reset_absolute")
        case .runsOut: L("menu_bar_help_runs_out")
        case .runsOutCompact: L("menu_bar_help_runs_out_compact")
        case .balance: L("menu_bar_help_balance")
        case .costToday: L("menu_bar_help_cost_today")
        case .costWindow: L("menu_bar_help_cost_window")
        case .tokensPerMinute: L("Latest tokens per minute (OpenAI Admin API)")
        case .tokensSparkline: L("Last hour of tokens per minute (OpenAI Admin API)")
        case .spendAmount: L("menu_bar_help_spend_amount")
        case .spendBudget: L("menu_bar_help_spend_budget")
        case .separatorDot: L("menu_bar_help_separator")
        case .space: L("menu_bar_help_space")
        case .hidden: L("menu_bar_help_hidden")
        case .conditional: L("menu_bar_help_conditional")
        }
        return self.editorLabel(provider: provider, snapshot: snapshot) + "\n" + description
    }
}

extension MenuBarLayoutPreset {
    func editorHelp(provider: UsageProvider? = nil) -> String {
        guard let layout = self.layout else { return L("menu_bar_help_preset_custom") }
        let lines = layout.lines.map { line in
            line.map { $0.editorLabel(provider: provider) }.joined(separator: ", ")
        }
        return L("menu_bar_help_preset") + "\n" + lines.joined(separator: "\n")
    }
}

extension MenuBarConditionalMetric {
    func editorHelp(provider: UsageProvider? = nil) -> String {
        let description: String
        switch self.kind {
        case .signedPercent:
            description = L("menu_bar_help_conditional_pace")
        case .hours:
            let meaning = self == .runsOutIn ? L("menu_bar_help_conditional_runout") :
                L("menu_bar_help_reset_countdown")
            description = meaning + "\n" + L("menu_bar_help_conditional_hours")
        case .currencyUSD:
            let meaning = switch self {
            case .balance: L("menu_bar_help_balance")
            case .costToday: L("menu_bar_help_cost_today")
            case .costWindow: L("menu_bar_help_cost_window")
            default: L("menu_bar_help_spend_amount")
            }
            description = meaning + "\n" + L("menu_bar_help_conditional_currency")
        case .percent:
            description = L("menu_bar_help_conditional_direction")
                + "\n" + L("menu_bar_help_conditional_threshold", self.thresholdUnit)
        }
        return self.editorLabel(provider: provider) + "\n" + description
    }
}
