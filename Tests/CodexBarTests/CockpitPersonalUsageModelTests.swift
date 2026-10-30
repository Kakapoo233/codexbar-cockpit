import Foundation
import Testing
@testable import CodexBarCore

struct CockpitPersonalUsageModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private var now: Date {
        self.calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12))!
    }

    @Test func `stable personal weekday history improves a held out week`() {
        let model = self.model(self.days())
        #expect(model.status == .ready)
        #expect(model.eligibleDayCount == 28)
        #expect(model.activeDayCount == 28)
        #expect(model.validation?.holdoutDayCount == 7)
        #expect((model.validation?.relativeImprovement ?? 0) > 0.01)
        #expect(model.weekdayStats.count == 7)
        #expect(model.weekdayStats.allSatisfy { (0.25...1.75).contains($0.allocationWeight) })
    }

    @Test func `missing partial and ambiguous days never train as measured zero`() {
        let partial = self.days().map { self.copy($0, used: nil, coverage: .partial) }
        let model = self.model(partial)
        #expect(model.status == .collecting)
        #expect(model.plannedDayCount == 28)
        #expect(model.eligibleDayCount == 0)
        #expect(model.activeDayCount == 0)
        #expect(model.validation == nil)
        var ambiguous = self.days()
        ambiguous.append(self.copy(ambiguous[0], used: 0))
        #expect(self.model(ambiguous).eligibleDayCount == 27)
    }

    @Test func `provider account timezone future and malformed dates stay isolated`() {
        let days = self.days()
        let anotherAccount = CockpitPersonalUsageModel.build(
            days: days,
            providerID: "codex",
            accountID: "other",
            now: self.now,
            calendar: self.calendar)
        #expect(anotherAccount.plannedDayCount == 0)
        let anotherProvider = CockpitPersonalUsageModel.build(
            days: days,
            providerID: "claude",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar)
        #expect(anotherProvider.plannedDayCount == 0)
        let invalidDays = ["2026-02-30", "2026-09-01", "2026-09-02"].map {
            self.day(key: $0, used: 10)
        } + [self.day(key: "2026-08-10", used: 10, zone: "America/New_York")]
        #expect(self.model(invalidDays).plannedDayCount == 0)
    }

    @Test func `stale drifting and unimproved history fall back without reference`() throws {
        let stale = try CockpitPersonalUsageModel.build(
            days: self.days(),
            providerID: "codex",
            accountID: "synthetic-person",
            now: #require(self.calendar.date(byAdding: .day, value: 4, to: self.now)),
            calendar: self.calendar)
        #expect(stale.status == .stale)
        var drift = self.days()
        for index in (drift.count - 7)..<drift.count {
            drift[index] = self.copy(drift[index], used: 20)
        }
        #expect(self.model(drift).status == .distributionDrift)
        let unchanged = self.days().map { self.copy($0, used: 10) }
        #expect(self.model(unchanged).status == .noValidationGain)
        #expect(stale.referencePercent(status: self.status(), now: self.now, calendar: self.calendar) == nil)
    }

    @Test func `validation requires seven consecutive complete days`() {
        var days = self.days()
        days.remove(at: days.count - 2)
        #expect(self.model(days).status == .collecting)
    }

    @Test func `reference is bounded by available quota and requires a fresh official window`() throws {
        let model = self.model(self.days())
        let reference = try #require(model.referencePercent(
            status: self.status(), now: self.now, calendar: self.calendar))
        #expect((0...100).contains(reference))
        let bounded = model.referencePercent(
            status: self.status(remaining: 1, used: 2), now: self.now, calendar: self.calendar)
        #expect(bounded == nil)
        #expect(model.referencePercent(
            status: self.status(stale: true), now: self.now, calendar: self.calendar) == nil)
    }

    @Test func `real plan state can reach calibration readiness without changing its frozen plans`() throws {
        var state = CockpitPlanState()
        for offset in -28...(-1) {
            let date = try #require(self.calendar.date(
                byAdding: .day,
                value: offset,
                to: self.calendar.startOfDay(for: self.now)))
            let weekday = self.calendar.component(.weekday, from: date)
            let used = weekday == 1 || weekday == 7 ? 4.3 : 17.1
            for halfHour in 0..<48 {
                let time = date.addingTimeInterval(Double(halfHour) * 1800)
                state.record(CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "synthetic-person",
                    capturedAt: time,
                    remainingPercent: 100 - used * Double(halfHour) / 48,
                    resetsAt: date.addingTimeInterval(7 * 86400)), calendar: self.calendar)
            }
            state.record(CockpitQuotaSnapshot(
                providerID: "codex",
                accountID: "synthetic-person",
                capturedAt: date.addingTimeInterval(86400 - 0.001),
                remainingPercent: 100 - used,
                resetsAt: date.addingTimeInterval(7 * 86400)), calendar: self.calendar)
        }
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        let before = state
        let model = CockpitPersonalUsageModel.build(
            state: state,
            providerID: "codex",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar)
        #expect(model.status == .ready)
        #expect(model.eligibleDayCount == 28)
        #expect(state == before)
    }

    @Test func `ordinary polling away from midnight trains recorded periods and survives raw expiry`() throws {
        var state = self.observedState()
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        #expect(state.observedDaySummaries.count == 28)
        #expect(state.observedDaySummaries.allSatisfy { $0.coverage == .partial && $0.qualifiesForCalibration })
        let model = CockpitPersonalUsageModel.build(
            state: state,
            providerID: "codex",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar)
        #expect(model.status == .ready)
        #expect(model.eligibleDayCount == 28)

        // Raw samples have a shorter retention than summaries; replay persisted state after raw expiry.
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["snapshots"] = []
        let restored = try JSONDecoder().decode(
            CockpitPlanState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.snapshots.isEmpty)
        #expect(restored.observedDaySummaries == state.observedDaySummaries)
        #expect(CockpitPersonalUsageModel.build(
            state: restored,
            providerID: "codex",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar).status == .ready)
    }

    @Test func `old plan files migrate without summaries and can rebuild them locally`() throws {
        let original = self.observedState()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "observedDaySummaries")
        var restored = try JSONDecoder().decode(
            CockpitPlanState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(restored.observedDaySummaries.isEmpty)
        #expect(restored.plans == original.plans)
        #expect(restored.personalCaps == original.personalCaps)
        let rebuilt = restored.summarizeClosedDays(through: self.now, calendar: self.calendar)
        #expect(rebuilt)
        #expect(restored.observedDaySummaries.count == 28)
        #expect(restored.plans == original.plans)
    }

    @Test func `short sparse unreliable and reset drifting observed periods fail qualification`() throws {
        let day = try #require(self.calendar.date(byAdding: .day, value: -1, to: self.now))
        for kind in 0..<4 {
            var state = CockpitPlanState()
            for index in 0..<13 {
                let seconds = Double(index) * (kind == 0 ? 900 : kind == 1 ? 6000 : 1800)
                let time = self.calendar.startOfDay(for: day).addingTimeInterval(3600 + seconds)
                let accepted = state.record(CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "synthetic-person",
                    capturedAt: time,
                    remainingPercent: 100 - Double(index),
                    resetsAt: day.addingTimeInterval(6 * 86400 + (kind == 3 ? Double(index) * 60 : 0)),
                    coverage: kind == 2 && index == 5 ? .partial : .complete), calendar: self.calendar)
                #expect(accepted)
            }
            state.summarizeClosedDays(through: self.now, calendar: self.calendar)
            #expect(!state.observedDaySummaries.isEmpty)
            #expect(state.observedDaySummaries.allSatisfy { !$0.qualifiesForCalibration })
        }
    }

    @Test func `historical sample corrections rebuild their observed summary`() throws {
        var state = self.observedState()
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        let sample = try #require(state.snapshots.last)
        let old = try #require(state.observedDaySummaries.last { $0.localDateKey == "2026-08-31" })
        state.record(CockpitQuotaSnapshot(
            providerID: sample.providerID,
            accountID: sample.accountID,
            capturedAt: sample.capturedAt,
            remainingPercent: sample.remainingPercent - 1,
            resetsAt: sample.resetsAt), calendar: self.calendar)
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        let updated = try #require(state.observedDaySummaries.last { $0.localDateKey == "2026-08-31" })
        #expect((updated.usedPercent ?? 0) > (old.usedPercent ?? 0))
    }

    @Test func `corrections after raw expiry withdraw the unknown measurement and qualification`() throws {
        var state = self.observedState()
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        // Correcting the first sample can lower the aggregate, so the old value is not a safe lower bound.
        let sample = try #require(state.snapshots.first {
            CockpitCalendar.dateKey(for: $0.capturedAt, calendar: self.calendar) == "2026-08-31"
        })
        let old = try #require(state.observedDaySummaries.last { $0.localDateKey == "2026-08-31" })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json["snapshots"] = []
        state = try JSONDecoder().decode(CockpitPlanState.self, from: JSONSerialization.data(withJSONObject: json))
        state.record(CockpitQuotaSnapshot(
            providerID: sample.providerID,
            accountID: sample.accountID,
            capturedAt: sample.capturedAt,
            remainingPercent: sample.remainingPercent - 1,
            resetsAt: sample.resetsAt), calendar: self.calendar)
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        let archived = try #require(state.observedDaySummaries.last { $0.localDateKey == "2026-08-31" })
        #expect(archived.usedPercent == nil)
        #expect(archived.coverage == .unavailable)
        #expect(archived.sampleCount == old.sampleCount)
        #expect(!archived.qualifiesForCalibration)
        #expect(archived.unreconciledCorrection == true)
    }

    @Test func `normal weekly resets and nonmidnight polling can still reach validated readiness`() throws {
        var state = CockpitPlanState()
        let firstDay = try #require(self.calendar.date(
            byAdding: .day, value: -35, to: self.calendar.startOfDay(for: self.now)))
        let firstReset = firstDay.addingTimeInterval(12 * 3600)
        for offset in 0..<35 {
            let date = try #require(self.calendar.date(byAdding: .day, value: offset, to: firstDay))
            for index in 0..<13 {
                let time = date.addingTimeInterval(9 * 3600 + 7 * 60 + Double(index) * 1800)
                let cycles = floor(time.timeIntervalSince(firstReset) / (7 * 86400))
                let cycleStart = firstReset.addingTimeInterval(cycles * 7 * 86400)
                let reset = cycleStart.addingTimeInterval(7 * 86400)
                let used = self.weeklyUse(from: cycleStart, through: time)
                state.record(CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "synthetic-person",
                    capturedAt: time,
                    remainingPercent: 100 - used,
                    resetsAt: reset), calendar: self.calendar)
            }
        }
        state.summarizeClosedDays(through: self.now, calendar: self.calendar)
        #expect(state.observedDaySummaries.count == 35)
        #expect(state.observedDaySummaries.allSatisfy { $0.coverage == .partial && $0.qualifiesForCalibration })
        #expect(CockpitPersonalUsageModel.build(
            state: state,
            providerID: "codex",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar).status == .ready)
    }

    @Test func `experience weights decay by the recorded calendar day rather than the edit timestamp`() throws {
        let records = (1...7).map { index in
            let date = self.calendar.date(byAdding: .day, value: -index, to: self.now)!
            return CockpitComfortRecord(
                providerID: "codex",
                localDateKey: CockpitCalendar.dateKey(for: date, calendar: self.calendar),
                timeZoneIdentifier: self.calendar.timeZone.identifier,
                recordedAt: self.now,
                feeling: index < 4 ? .light : .overloaded,
                totalTokens: index * 100_000,
                coverage: .complete)
        }
        let recent = CockpitComfortModel.build(
            records: records, providerID: "codex", now: self.now, calendar: self.calendar)
        let later = try CockpitComfortModel.build(
            records: records,
            providerID: "codex",
            now: #require(self.calendar.date(byAdding: .day, value: 14, to: self.now)),
            calendar: self.calendar)
        #expect(abs(later.recencyWeightedSampleCount * 2 - recent.recencyWeightedSampleCount) < 0.0001)
        #expect(recent.status == .ready)
        #expect(later.status == .insufficientData)
        #expect(later.points.isEmpty)
    }

    private func model(_ days: [CockpitPersonalUsageDay]) -> CockpitPersonalUsageModel {
        CockpitPersonalUsageModel.build(
            days: days,
            providerID: "codex",
            accountID: "synthetic-person",
            now: self.now,
            calendar: self.calendar)
    }

    private func weeklyUse(from start: Date, through end: Date) -> Double {
        var day = self.calendar.startOfDay(for: start)
        var used = 0.0
        while day <= end {
            guard let interval = self.calendar.dateInterval(of: .day, for: day) else { break }
            let duration = max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
            let weekday = self.calendar.component(.weekday, from: day)
            used += (weekday == 1 || weekday == 7 ? 3 : 12) * duration / interval.duration
            day = interval.end
        }
        return used
    }

    private func observedState() -> CockpitPlanState {
        var state = CockpitPlanState()
        for offset in -28...(-1) {
            let date = self.calendar.date(byAdding: .day, value: offset, to: self.calendar.startOfDay(for: self.now))!
            let weekday = self.calendar.component(.weekday, from: date)
            let used = weekday == 1 || weekday == 7 ? 2.5 : 10
            for halfHour in 0..<13 {
                // Typical polling begins at 09:07 and never lands exactly at midnight.
                let time = date.addingTimeInterval(9 * 3600 + 7 * 60 + Double(halfHour) * 1800)
                state.record(CockpitQuotaSnapshot(
                    providerID: "codex",
                    accountID: "synthetic-person",
                    capturedAt: time,
                    remainingPercent: 100 - used * Double(halfHour) / 12,
                    resetsAt: date.addingTimeInterval(7 * 86400)), calendar: self.calendar)
            }
        }
        return state
    }

    private func days() -> [CockpitPersonalUsageDay] {
        (-28 ... -1).map { offset in
            let date = self.calendar.date(byAdding: .day, value: offset, to: self.now)!
            let weekday = self.calendar.component(.weekday, from: date)
            return self.day(
                key: CockpitCalendar.dateKey(for: date, calendar: self.calendar),
                used: weekday == 1 || weekday == 7 ? 3 : 12)
        }
    }

    private func day(key: String, used: Double?, zone: String? = nil) -> CockpitPersonalUsageDay {
        CockpitPersonalUsageDay(
            providerID: "codex",
            accountID: "synthetic-person",
            timeZoneIdentifier: zone ?? self.calendar.timeZone.identifier,
            localDateKey: key,
            suggestedPercent: 10,
            usedPercent: used,
            coverage: .complete)
    }

    private func copy(
        _ day: CockpitPersonalUsageDay,
        used: Double?,
        coverage: CockpitCoverage = .complete) -> CockpitPersonalUsageDay
    {
        CockpitPersonalUsageDay(
            providerID: day.providerID,
            accountID: day.accountID,
            timeZoneIdentifier: day.timeZoneIdentifier,
            localDateKey: day.localDateKey,
            suggestedPercent: day.suggestedPercent,
            usedPercent: used,
            coverage: coverage)
    }

    private func status(remaining: Double = 50, used: Double = 2, stale: Bool = false) -> CockpitDayStatus {
        CockpitDayStatus(
            localDateKey: CockpitCalendar.dateKey(for: self.now, calendar: self.calendar),
            suggestedPercent: 10,
            manualCapPercent: 15,
            usedPercent: used,
            coverage: .complete,
            remainingPercent: remaining,
            resetsAt: self.now.addingTimeInterval(5 * 86400),
            feeling: nil,
            isStale: stale)
    }
}
