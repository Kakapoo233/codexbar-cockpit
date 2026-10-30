import CodexBarCore
import Foundation
import Testing

struct CodexPlanFormattingTests {
    @Test
    func `maps Codex pro plans to usage multiplier names`() {
        #expect(CodexPlanFormatting.displayName("pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("Pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("Codex Pro") == "Pro 20x")
        #expect(CodexPlanFormatting.displayName("prolite") == "Pro 10x")
        #expect(CodexPlanFormatting.displayName("pro_lite") == "Pro 10x")
        #expect(CodexPlanFormatting.displayName("pro-lite") == "Pro 10x")
        #expect(CodexPlanFormatting.displayName("Pro Lite") == "Pro 10x")
        #expect(CodexPlanFormatting.displayName("Codex Pro Lite") == "Pro 10x")
    }

    @Test(arguments: [
        ("Pro 100", "Pro 10x"),
        ("pro_100", "Pro 10x"),
        ("pro-100", "Pro 10x"),
        ("pro100", "Pro 10x"),
        ("Pro $100", "Pro 10x"),
        ("Codex Pro 100", "Pro 10x"),
        ("Pro 200", "Pro 20x"),
        ("pro_200", "Pro 20x"),
        ("pro-200", "Pro 20x"),
        ("pro200", "Pro 20x"),
        ("Pro $200", "Pro 20x"),
        ("Codex Pro 200", "Pro 20x"),
        ("Pro 500", "Pro 50x"),
        ("pro_500", "Pro 50x"),
        ("pro-500", "Pro 50x"),
        ("pro500", "Pro 50x"),
        ("Pro $500", "Pro 50x"),
        ("Codex Pro 500", "Pro 50x"),
    ])
    func `maps explicit Pro prices to current allowance labels`(raw: String, expected: String) {
        #expect(CodexPlanFormatting.displayName(raw) == expected)
        #expect(CodexPlanFormatting.displayName(CodexPlanFormatting.displayName(raw)) == expected)
    }

    @Test(arguments: ["Pro 5x", "Pro 10x", "Pro 20x", "Pro 50x"])
    func `preserves already formatted allowance labels`(raw: String) {
        #expect(CodexPlanFormatting.displayName(raw) == raw)
    }

    @Test
    func `does not infer allowances for unknown Pro tiers`() {
        #expect(CodexPlanFormatting.displayName("Pro 300") == "Pro 300")
        #expect(CodexPlanFormatting.displayName("pro_future") == "Pro Future")
    }

    @Test
    func `returns nil for empty plan values`() {
        #expect(CodexPlanFormatting.displayName(nil) == nil)
        #expect(CodexPlanFormatting.displayName("") == nil)
        #expect(CodexPlanFormatting.displayName("   ") == nil)
    }

    @Test
    func `humanizes machine style plan identifiers`() {
        #expect(
            CodexPlanFormatting.displayName("enterprise_cbp_usage_based")
                == "Enterprise CBP Usage Based")
        #expect(
            CodexPlanFormatting.displayName("self_serve_business_usage_based")
                == "Self Serve Business Usage Based")
        #expect(CodexPlanFormatting.displayName("k12") == "K12")
    }

    @Test
    func `preserves unrelated already readable plan text`() {
        #expect(CodexPlanFormatting.displayName("Enterprise") == "Enterprise")
    }
}
