import Foundation
import Testing
@testable import CodexBarCore

struct CockpitQuotaComfortTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(
        _ day: Int,
        hour: Int = 12,
        calendar: Calendar? = nil) -> Date
    {
        let calendar = calendar ?? self.calendar
        return calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: day,
            hour: hour))!
    }

    private func record(
        day: Int,
        used: Double?,
        feeling: CockpitFeeling = .comfortable,
        coverage: CockpitCoverage = .complete,
        provider: String = "codex",
        account: String = "account-a",
        calendar: Calendar? = nil) -> CockpitComfortRecord
    {
        let calendar = calendar ?? self.calendar
        let date = self.date(
            day,
            calendar: calendar)
        return CockpitComfortRecord(
            providerID: provider,
            accountID: account,
            localDateKey: CockpitCalendar.dateKey(
                for: date,
                calendar: calendar),
            timeZoneIdentifier: calendar.timeZone.identifier,
            recordedAt: date,
            feeling: feeling,
            totalTokens: nil,
            coverage: coverage,
            usedPercent: used)
    }

    private func model(
        _ records: [CockpitComfortRecord],
        now: Date? = nil) -> CockpitQuotaComfortModel
    {
        CockpitQuotaComfortModel.build(
            records: records,
            providerID: "codex",
            accountID: "account-a",
            now: now ?? self.date(30),
            calendar: self.calendar)
    }

    @Test(arguments: [
        (10.0, 25.0, 0.9999998653159792),
        (25.0, 25.0, 0.9940397495510607),
        (40.0, 25.0, 0.811605886166427),
        (65.0, 25.0, 0.4349551112831438),
        (75.0, 25.0, 0.3341425599306709),
        (50.0, 50.0, 0.9928390070736886),
        (10.0, 0.1, 0.902840617530136),
        (90.0, 100.0, 0.9992344450712254),
    ])
    func `original smooth knee family matches upstream golden values`(
        used: Double,
        knee: Double,
        expected: Double)
    {
        #expect(abs(CockpitQuotaComfortModel.score(
            atUsedPercent: used,
            kneePercent: knee) - expected) < 1e-12)
    }

    @Test
    func `default curve remains visible without usable quota measurements`() {
        let model = self.model([
            self.record(
                day: 1,
                used: nil),
            self.record(
                day: 2,
                used: 40,
                coverage: .unavailable),
        ])
        #expect(model.status == .baseline)
        #expect(model.kneePercent == 25)
        #expect(model.sampleCount == 0)
        #expect(model.confidence == 0)
        #expect(model.points.count == 201)
        #expect(model.axisMaxPercent == 125)
        #expect(model.axisTicks == [0, 25, 50, 75, 100, 125])
    }

    @Test
    func `fitted knee minimizes all grid candidates with fixed subjective scores`() {
        let records = [
            self.record(
                day: 27,
                used: 10,
                feeling: .light),
            self.record(
                day: 28,
                used: 40,
                feeling: .comfortable),
            self.record(
                day: 29,
                used: 65,
                feeling: .overloaded,
                coverage: .partial),
        ]
        let model = self.model(records)
        func loss(_ knee: Double) -> Double {
            model.observations.reduce(0) { sum, observation in
                let residual = CockpitQuotaComfortModel.score(
                    atUsedPercent: observation.usedPercent,
                    kneePercent: knee) - observation.score
                return sum + observation.weight * residual * residual
            }
        }
        #expect(model.status == .fitted)
        #expect(model.sampleCount == 3)
        #expect(model.observations.map(\.score) == [1, 0.8, 0.25])
        #expect(loss(model.kneePercent) < loss(25))
        for index in 1...1000 {
            #expect(loss(model.kneePercent) <= loss(Double(index) / 10) + 1e-9)
        }
        #expect(model.points.allSatisfy { (0.2...1).contains($0.score) })
    }

    @Test
    func `one observation can fit and measured zero is not missing`() {
        let absent = self.model([self.record(
            day: 29,
            used: nil)])
        let zero = self.model([self.record(
            day: 29,
            used: 0,
            feeling: .light)])
        let one = self.model([self.record(
            day: 29,
            used: 50,
            feeling: .overloaded)])
        #expect(absent.sampleCount == 0)
        #expect(zero.sampleCount == 1)
        #expect(zero.status == .fitted)
        #expect(zero.kneePercent == 25)
        #expect(one.sampleCount == 1)
        #expect(one.kneePercent != 25)
    }

    @Test
    func `cumulative quota above one hundred expands the axis and preserves the floor`() {
        for knee in [0.1, 25, 50, 80, 100] {
            #expect(abs(CockpitQuotaComfortModel.score(
                atUsedPercent: 0,
                kneePercent: knee) - 1) < 1e-12)
            #expect(abs(CockpitQuotaComfortModel.score(
                atUsedPercent: 100,
                kneePercent: knee) - 0.2) < 1e-12)
            #expect(abs(CockpitQuotaComfortModel.score(
                atUsedPercent: 200,
                kneePercent: knee) - 0.2) < 1e-12)
        }
        let model = self.model([self.record(
            day: 29,
            used: 200,
            feeling: .overloaded)])
        #expect(model.kneePercent == 25)
        #expect(model.observations.first?.usedPercent == 200)
        #expect(model.axisMaxPercent == 250)
        #expect(model.axisTicks == [0, 50, 100, 150, 200, 250])
        let maximum = self.model([self.record(
            day: 29,
            used: 10000)])
        #expect(maximum.axisMaxPercent == 12500)
        let finiteScores = maximum.points.allSatisfy(\.score.isFinite)
        #expect(finiteScores)
        for value in [-1.0, .nan, .infinity, 10001] {
            #expect(self.model([self.record(
                day: 29,
                used: value)]).observations.isEmpty)
        }
    }

    @Test
    func `experience age controls recency across daylight saving and later edits`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let model = CockpitQuotaComfortModel.build(
            records: [
                self.record(
                    day: 1,
                    used: 35,
                    coverage: .partial,
                    calendar: calendar),
                self.record(
                    day: 15,
                    used: 35,
                    calendar: calendar),
            ],
            providerID: "codex",
            accountID: "account-a",
            now: self.date(
                15,
                calendar: calendar),
            calendar: calendar)
        #expect(model.observations.map(\.weight) == [0.375, 1])
        #expect(model.effectiveSampleCount == 1.375)
        let old = self.record(
            day: 1,
            used: 35)
        let edited = CockpitComfortRecord(
            providerID: old.providerID,
            accountID: old.accountID,
            localDateKey: old.localDateKey,
            timeZoneIdentifier: old.timeZoneIdentifier,
            recordedAt: self.date(15),
            feeling: old.feeling,
            totalTokens: nil,
            coverage: old.coverage,
            usedPercent: old.usedPercent)
        #expect(self.model(
            [edited],
            now: self.date(15)).observations.first?.weight == 0.5)
    }

    @Test
    func `recent contradictory experience outweighs old feedback without mutating inputs`() {
        let higher = self.model([
            self.record(
                day: 1,
                used: 35,
                feeling: .overloaded),
            self.record(
                day: 29,
                used: 35,
                feeling: .light),
        ])
        let lower = self.model([
            self.record(
                day: 1,
                used: 35,
                feeling: .light),
            self.record(
                day: 29,
                used: 35,
                feeling: .overloaded),
        ])
        #expect(higher.kneePercent > lower.kneePercent)
        let later = self.model(
            [
                self.record(
                    day: 1,
                    used: 35),
                self.record(
                    day: 2,
                    used: 55,
                    feeling: .overloaded),
            ],
            now: self.date(30))
        let earlier = self.model(
            [
                self.record(
                    day: 1,
                    used: 35),
                self.record(
                    day: 2,
                    used: 55,
                    feeling: .overloaded),
            ],
            now: self.date(16))
        #expect(abs(later.effectiveSampleCount * 2 - earlier.effectiveSampleCount) < 1e-12)
        #expect(later.confidence < earlier.confidence)
    }

    @Test
    func `providers accounts timezones future and invalid dates cannot train another curve`() throws {
        let valid = self.record(
            day: 1,
            used: 30)
        let records = [
            valid,
            self.record(
                day: 2,
                used: 30,
                provider: "claude"),
            self.record(
                day: 3,
                used: 30,
                account: "account-b"),
            self.record(
                day: 4,
                used: 30,
                account: "local-machine"),
            self.record(
                day: 30,
                used: 30),
            CockpitComfortRecord(
                providerID: "codex",
                accountID: "account-a",
                localDateKey: "2026-02-30",
                timeZoneIdentifier: self.calendar.timeZone.identifier,
                recordedAt: self.date(1),
                feeling: .light,
                totalTokens: nil,
                coverage: .complete,
                usedPercent: 30),
            CockpitComfortRecord(
                providerID: "codex",
                accountID: "account-a",
                localDateKey: "2026-11-05",
                timeZoneIdentifier: "America/New_York",
                recordedAt: self.date(5),
                feeling: .light,
                totalTokens: nil,
                coverage: .complete,
                usedPercent: 30),
        ]
        #expect(self.model(
            records,
            now: self.date(15)).observations.map(\.id) == [valid.id])
        for account in ["unidentified", "local-machine", ""] {
            #expect(CockpitQuotaComfortModel.build(
                records: records,
                providerID: "codex",
                accountID: account,
                now: self.date(15),
                calendar: self.calendar).observations.isEmpty)
        }
        let encoded = try JSONEncoder().encode(self.record(
            day: 2,
            used: 30))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["usedPercent"] = 10001
        let invalid = try JSONDecoder().decode(
            CockpitComfortRecord.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(self.model([invalid]).observations.isEmpty)
    }

    @Test
    func `newest record for each day wins and ninety feedback records precede measurement filtering`() throws {
        let old = self.record(
            day: 1,
            used: 30,
            feeling: .light)
        let newer = CockpitComfortRecord(
            providerID: old.providerID,
            accountID: old.accountID,
            localDateKey: old.localDateKey,
            timeZoneIdentifier: old.timeZoneIdentifier,
            recordedAt: self.date(2),
            feeling: .overloaded,
            totalTokens: nil,
            coverage: .complete,
            usedPercent: 55)
        #expect(self.model([newer, old]).observations.map(\.usedPercent) == [55])
        let cleared = CockpitComfortRecord(
            providerID: old.providerID,
            accountID: old.accountID,
            localDateKey: old.localDateKey,
            timeZoneIdentifier: old.timeZoneIdentifier,
            recordedAt: self.date(3),
            feeling: .comfortable,
            totalTokens: nil,
            coverage: .unavailable)
        #expect(self.model([old, cleared]).observations.isEmpty)
        let now = self.date(30)
        let records = try (0..<100).map { offset in
            let date = try #require(self.calendar.date(
                byAdding: .day,
                value: -offset,
                to: now))
            return CockpitComfortRecord(
                providerID: "codex",
                accountID: "account-a",
                localDateKey: CockpitCalendar.dateKey(
                    for: date,
                    calendar: self.calendar),
                timeZoneIdentifier: self.calendar.timeZone.identifier,
                recordedAt: date,
                feeling: .comfortable,
                totalTokens: nil,
                coverage: .complete,
                usedPercent: 30)
        }
        #expect(self.model(records).sampleCount == 90)
        let recentMissing = records.prefix(90).map { record in
            CockpitComfortRecord(
                providerID: record.providerID,
                accountID: record.accountID,
                localDateKey: record.localDateKey,
                timeZoneIdentifier: record.timeZoneIdentifier,
                recordedAt: record.recordedAt,
                feeling: record.feeling,
                totalTokens: nil,
                coverage: .unavailable)
        }
        #expect(self.model(Array(records.suffix(10)) + recentMissing).sampleCount == 0)
    }

    @Test
    func `old token only state decodes without inventing quota and round trips new quota records`() throws {
        var state = CockpitPlanState()
        state.recordComfort(
            .comfortable,
            providerID: "codex",
            accountID: "local-machine",
            on: self.date(1),
            totalTokens: 500_000,
            coverage: .complete,
            calendar: self.calendar)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        let oldData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(
            CockpitPlanState.self,
            from: oldData)
        #expect(decoded.comfortRecords.first?.usedPercent == nil)
        #expect(decoded.comfortRecords.first?.totalTokens == 500_000)
        #expect(self.model(decoded.comfortRecords).sampleCount == 0)
        state.recordComfort(
            .light,
            providerID: "codex",
            accountID: "account-a",
            on: self.date(2),
            coverage: .partial,
            calendar: self.calendar,
            usedPercent: 20)
        #expect(try JSONDecoder().decode(
            CockpitPlanState.self,
            from: JSONEncoder().encode(state)) == state)
    }

    @Test
    func `quota recording preserves actual measurements and frozen plans across corrections`() throws {
        var state = CockpitPlanState()
        let start = self.date(
            15,
            hour: 8)
        let now = start.addingTimeInterval(3600)
        state.record(
            CockpitQuotaSnapshot(
                providerID: "codex",
                accountID: "account-a",
                capturedAt: start,
                remainingPercent: 80,
                resetsAt: self.date(20)),
            calendar: self.calendar)
        state.record(
            CockpitQuotaSnapshot(
                providerID: "codex",
                accountID: "account-a",
                capturedAt: now,
                remainingPercent: 70,
                resetsAt: self.date(20)),
            calendar: self.calendar)
        state.setPersonalCap(
            25,
            providerID: "codex",
            accountID: "account-a",
            on: now,
            calendar: self.calendar)
        let plans = state.plans
        let caps = state.personalCaps
        let usage = state.quotaComfortUsage(
            providerID: "codex",
            accountID: "account-a",
            on: now,
            now: now,
            calendar: self.calendar)
        #expect(usage.usedPercent == 10)
        #expect(usage.coverage == .partial)
        let accepted = state.recordQuotaComfort(
            .comfortable,
            providerID: "codex",
            accountID: "account-a",
            on: now,
            now: now,
            calendar: self.calendar)
        #expect(accepted)
        let captured = try #require(state.comfortRecords.first)
        #expect(captured.usedPercent == 10)
        #expect(captured.totalTokens == nil)
        let later = now.addingTimeInterval(3600)
        state.record(
            CockpitQuotaSnapshot(
                providerID: "codex",
                accountID: "account-a",
                capturedAt: later,
                remainingPercent: 60,
                resetsAt: self.date(20)),
            calendar: self.calendar)
        state.recordQuotaComfort(
            .overloaded,
            providerID: "codex",
            accountID: "account-a",
            on: now,
            now: later,
            calendar: self.calendar)
        #expect(state.comfortRecords.count == 1)
        #expect(state.comfortRecords.first?.usedPercent == 10)
        #expect(state.comfortRecords.first?.feeling == .overloaded)
        #expect(state.comfortRecords.first?.recordedAt == later)
        #expect(state.plans == plans)
        #expect(state.personalCaps == caps)
    }

    @Test
    func `missing quota may fill later but historical ratings never capture todays usage`() {
        var state = CockpitPlanState()
        let now = self.date(15)
        state.recordQuotaComfort(
            .comfortable,
            providerID: "codex",
            accountID: "account-a",
            on: now,
            now: now,
            calendar: self.calendar)
        #expect(state.comfortRecords.first?.usedPercent == nil)
        #expect(state.comfortRecords.first?.coverage == .unavailable)
        for (hour, remaining) in [(8, 80.0), (12, 70.0)] {
            state.record(
                CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "account-a",
                    capturedAt: self.date(
                        15,
                        hour: hour),
                    remainingPercent: remaining,
                    resetsAt: self.date(20)),
                calendar: self.calendar)
        }
        state.recordQuotaComfort(
            .light,
            providerID: "codex",
            accountID: "account-a",
            on: now,
            now: now,
            calendar: self.calendar)
        #expect(state.comfortRecords.first?.usedPercent == 10)
        state.recordQuotaComfort(
            .overloaded,
            providerID: "codex",
            accountID: "account-a",
            on: self.date(14),
            now: now,
            calendar: self.calendar)
        #expect(state.comfortRecords.last?.usedPercent == nil)
        #expect(state.comfortRecords.last?.localDateKey == "2026-11-14")
        for account in ["unidentified", "local-machine", ""] {
            let accepted = state.recordQuotaComfort(
                .light,
                providerID: "codex",
                accountID: account,
                on: now,
                now: now,
                calendar: self.calendar)
            #expect(!accepted)
        }
        let future = state.recordQuotaComfort(
            .light,
            providerID: "codex",
            accountID: "account-a",
            on: self.date(16),
            now: now,
            calendar: self.calendar)
        #expect(!future)
        #expect(state.comfortRecords.count == 2)
    }

    @Test
    func `archived quota remains scoped and withdrawn aggregates never revive after retention`() throws {
        var state = CockpitPlanState()
        for (hour, remaining) in [(8, 80.0), (12, 70.0)] {
            state.record(
                CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "account-a",
                    capturedAt: self.date(
                        1,
                        hour: hour),
                    remainingPercent: remaining,
                    resetsAt: self.date(5)),
                calendar: self.calendar)
        }
        state.summarizeClosedDays(
            through: self.date(2),
            calendar: self.calendar)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        object["snapshots"] = []
        let retained = try JSONDecoder().decode(
            CockpitPlanState.self,
            from: JSONSerialization.data(withJSONObject: object))
        let usage = retained.quotaComfortUsage(
            providerID: "codex",
            accountID: "account-a",
            on: self.date(1),
            now: self.date(15),
            calendar: self.calendar)
        #expect(usage.usedPercent == 10)
        #expect(usage.coverage == .partial)
        #expect(retained.quotaComfortUsage(
            providerID: "codex",
            accountID: "account-b",
            on: self.date(1),
            now: self.date(15),
            calendar: self.calendar).usedPercent == nil)
        var otherZone = self.calendar
        otherZone.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(retained.quotaComfortUsage(
            providerID: "codex",
            accountID: "account-a",
            on: self.date(1),
            now: self.date(15),
            calendar: otherZone).usedPercent == nil)
        var summaries = try #require(object["observedDaySummaries"] as? [[String: Any]])
        summaries[0]["unreconciledCorrection"] = true
        object["observedDaySummaries"] = summaries
        let withdrawn = try JSONDecoder().decode(
            CockpitPlanState.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(withdrawn.quotaComfortUsage(
            providerID: "codex",
            accountID: "account-a",
            on: self.date(1),
            now: self.date(15),
            calendar: self.calendar).coverage == .unavailable)
    }
}
