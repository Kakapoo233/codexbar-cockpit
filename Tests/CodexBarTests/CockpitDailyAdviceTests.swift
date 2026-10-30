import CodexBarCore
import Foundation
import Observation
import Testing
@testable import CodexBar

@MainActor
struct CockpitDailyAdviceTests {
    @Test func `overview recommendations include all eligible scoped providers without duplicates`() {
        #expect(CockpitDailyAdviceProjection.providers(
            in: [.codex, .cursor, .claude, .codex],
            available: [.claude, .codex]) == [.codex, .claude])
        #expect(CockpitDailyAdviceProjection.providers(in: [.cursor], available: [.codex]).isEmpty)
        #expect(CockpitDailyAdviceProjection.providers(in: [], available: [.codex]).isEmpty)
    }

    @Test func `cap edits notify the displayed advice immediately and survive reload`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("plan.json")
        let store = CockpitPlanStore(fileURL: file)
        let snapshot = Self.snapshot()
        store.ingest([.codex: snapshot])
        let suggestion = try #require(store.status(for: .codex).suggestedPercent)
        let invalidated = AdviceObservationFlag()
        withObservationTracking {
            _ = store.status(for: .codex).effectiveCapPercent
        } onChange: {
            invalidated.set()
        }

        store.setPersonalCap(12.5, for: .codex)
        #expect(invalidated.get())
        #expect(store.status(for: .codex).effectiveCapPercent == 12.5)
        #expect(store.status(for: .codex).suggestedPercent == suggestion)

        let reloaded = CockpitPlanStore(fileURL: file)
        reloaded.ingest([.codex: snapshot])
        #expect(reloaded.status(for: .codex).effectiveCapPercent == 12.5)
        reloaded.setPersonalCap(nil, for: .codex)
        #expect(reloaded.status(for: .codex).effectiveCapPercent == suggestion)
    }

    private static func snapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: nil,
            secondary: RateWindow(
                usedPercent: 30,
                windowMinutes: 10080,
                resetsAt: Date().addingTimeInterval(5 * 86400),
                resetDescription: nil),
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .codex,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil,
                accountID: "synthetic-panel-account"))
    }
}

private final class AdviceObservationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.value = true
    }

    func get() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }
}
