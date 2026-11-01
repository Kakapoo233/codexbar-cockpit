import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct CockpitResetBannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `banner appears immediately for a dated announcement and disappears at its deadline`() throws {
        let date = self.now.addingTimeInterval(600)
        let status = try self.status(date: date)
        #expect(CockpitResetBannerProjection.announcement(status: status, now: self.now)?.scheduledFor == date)
        #expect(CockpitResetBannerProjection.announcement(status: status, now: date.addingTimeInterval(-1)) != nil)
        #expect(CockpitResetBannerProjection.announcement(status: status, now: date) == nil)
        #expect(CockpitResetBannerProjection.announcement(status: status, now: date.addingTimeInterval(1)) == nil)
    }

    @Test(arguments: ["cancelled", "completed", "unknown"])
    func `withdrawn and nonpending announcements never produce a countdown`(state: String) throws {
        #expect(try CockpitResetBannerProjection.announcement(
            status: self.status(date: self.now.addingTimeInterval(3600), state: state), now: self.now) == nil)
    }

    @Test
    func `undated missing stale or future generated metadata cannot imply a confirmed date`() throws {
        #expect(CockpitResetBannerProjection.announcement(status: nil, now: self.now) == nil)
        #expect(try CockpitResetBannerProjection.announcement(status: self.status(date: nil), now: self.now) == nil)
        for offset in [-901.0, 301.0] {
            #expect(try CockpitResetBannerProjection.announcement(
                status: self.status(date: self.now.addingTimeInterval(3600), generatedOffset: offset),
                now: self.now) == nil)
        }
        let watch = try CockpitResetWatch(
            id: "watch",
            level: "strong",
            resetChancePercent: 90,
            forecastWindow: "Tomorrow",
            observedAt: self.now,
            expiresAt: self.now.addingTimeInterval(3600),
            text: "Synthetic estimate",
            sourceURL: CockpitResetHistoryClient.websiteURL)
        #expect(CockpitResetBannerProjection.announcement(
            status: CockpitResetStatus(generatedAt: self.now, activeWatch: watch), now: self.now) == nil)
    }

    @Test
    func `replacement status immediately changes or removes the announced date`() throws {
        let first = try self.status(date: self.now.addingTimeInterval(300))
        let revised = try self.status(date: self.now.addingTimeInterval(600))
        #expect(CockpitResetBannerProjection.announcement(status: first, now: self.now)?.scheduledFor
            != CockpitResetBannerProjection.announcement(status: revised, now: self.now)?.scheduledFor)
        #expect(CockpitResetBannerProjection.announcement(
            status: CockpitResetStatus(generatedAt: self.now), now: self.now) == nil)
    }

    private func status(date: Date?, state: String = "scheduled", generatedOffset: TimeInterval = 0) throws
        -> CockpitResetStatus
    {
        try CockpitResetStatus(
            generatedAt: self.now.addingTimeInterval(generatedOffset),
            scheduledReset: CockpitScheduledReset(
                id: "synthetic",
                status: state,
                announcedAt: self.now,
                scheduledFor: date,
                text: "Synthetic announcement",
                sourceURL: CockpitResetHistoryClient.websiteURL))
    }
}
