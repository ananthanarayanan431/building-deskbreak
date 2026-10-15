import Foundation
import Testing
@testable import DeskBreakCore

@Suite("ReminderSchedule")
struct ReminderScheduleTests {
    let settings = ReminderSettings.default
    /// Intervals that never come within `minimumGap` of each other in these tests, so one timer
    /// can be checked without the other moving it.
    var apart: ReminderSettings {
        var apart = settings
        apart.walkInterval = 150 * 60
        return apart
    }

    @Test("Water fires after one hour of active time and restarts immediately")
    func waterFiresHourly() {
        var schedule = ReminderSchedule(settings: apart)

        let early = schedule.advance(by: 59 * 60, settings: apart)
        let due = schedule.advance(by: 60, settings: apart)
        #expect(early.isEmpty)
        #expect(due == [.regularDue(.water)])
        #expect(schedule.water.regularRemaining == apart.waterInterval)
    }

    @Test("Water and walk never fire together; the second water waits 15 minutes past the walk")
    func waterAndWalkAreSeparated() {
        var schedule = ReminderSchedule(settings: settings)
        _ = schedule.advance(by: 60 * 60, settings: settings)
        // Both would now be due in one hour; water moves to 15 minutes after the walk.
        #expect(schedule.walk.regularRemaining == 60 * 60)
        #expect(schedule.water.regularRemaining == 75 * 60)

        let walkDue = schedule.advance(by: 60 * 60, settings: settings)
        #expect(walkDue == [.regularDue(.walk)])
        let waterDue = schedule.advance(by: ReminderSchedule.minimumGap, settings: settings)
        #expect(waterDue == [.regularDue(.water)])
    }

    @Test("Over a long day the two kinds always stay at least 15 minutes apart")
    func gapHoldsOverTime() {
        var schedule = ReminderSchedule(settings: settings)
        var fires: [ReminderKind: [TimeInterval]] = [:]
        for minute in 1...(12 * 60) {
            for case .regularDue(let kind) in schedule.advance(by: 60, settings: settings) {
                fires[kind, default: []].append(TimeInterval(minute * 60))
            }
        }
        let water = fires[.water] ?? []
        let walk = fires[.walk] ?? []
        #expect(water.count >= 10)
        #expect(walk.count >= 5)
        for w in walk {
            #expect(water.allSatisfy { abs($0 - w) >= ReminderSchedule.minimumGap })
        }
    }

    @Test("Resetting the walk timer moves it clear of a water reminder due at the same time")
    func resetKeepsGap() {
        var schedule = ReminderSchedule(
            water: .init(regularRemaining: 2 * 60 * 60 - 60),
            walk: .init(regularRemaining: 30 * 60)
        )
        schedule.resetRegular(.walk, settings: settings)
        #expect(abs(schedule.water.regularRemaining - schedule.walk.regularRemaining) >= ReminderSchedule.minimumGap)
    }

    @Test("A separated timer loaded from disk is kept, not reset")
    func sanitizedKeepsSeparatedTimer() {
        let saved = ReminderSchedule(
            water: .init(regularRemaining: 75 * 60),
            walk: .init(regularRemaining: 60 * 60)
        )
        #expect(saved.sanitized(for: settings) == saved)
    }

    @Test("Late wake-ups shorten the next interval by the overshoot")
    func overshootCarriesOver() {
        var schedule = ReminderSchedule(settings: apart)
        _ = schedule.advance(by: 60 * 60 + 30, settings: apart)
        #expect(schedule.water.regularRemaining == apart.waterInterval - 30)
    }

    @Test("A huge gap fires once, not repeatedly")
    func hugeGapFiresOnce() {
        var schedule = ReminderSchedule(settings: settings)
        let events = schedule.advance(by: 10 * 60 * 60, settings: settings)
        #expect(events.filter { $0 == .regularDue(.water) }.count == 1)
        #expect(schedule.water.regularRemaining == settings.waterInterval)
    }

    @Test("A snooze fires after its own length and does not move the regular timer")
    func snoozeIsIndependent() {
        var schedule = ReminderSchedule(settings: apart)
        _ = schedule.advance(by: 60 * 60, settings: apart)
        let record = UUID()

        let replaced = schedule.snooze(.water, recordID: record, length: apart.snoozeLength)
        #expect(replaced == nil)
        let events = schedule.advance(by: apart.snoozeLength, settings: apart)

        #expect(events == [.snoozeDue(.water, recordID: record)])
        #expect(schedule.water.snooze == nil)
        #expect(schedule.water.regularRemaining == apart.waterInterval - apart.snoozeLength)
    }

    @Test("The next regular reminder cancels a pending snooze of the same kind")
    func regularCancelsSnooze() {
        var schedule = ReminderSchedule(settings: settings)
        _ = schedule.advance(by: 55 * 60, settings: settings)
        let record = UUID()
        _ = schedule.snooze(.water, recordID: record, length: settings.snoozeLength)

        let events = schedule.advance(by: 5 * 60, settings: settings)
        #expect(events == [.snoozeCancelled(.water, recordID: record), .regularDue(.water)])
        #expect(schedule.water.snooze == nil)
    }

    @Test("Snoozing again replaces the previous snooze and reports it")
    func resnoozeReplaces() {
        var schedule = ReminderSchedule(settings: settings)
        let first = UUID()
        let second = UUID()
        _ = schedule.snooze(.walk, recordID: first, length: 600)
        let replaced = schedule.snooze(.walk, recordID: second, length: 600)
        #expect(replaced == .snoozeCancelled(.walk, recordID: first))
        #expect(schedule.walk.snooze?.recordID == second)
    }

    @Test("Resetting the walk timer restores the full interval")
    func walkReset() {
        var schedule = ReminderSchedule(settings: apart)
        _ = schedule.advance(by: 90 * 60, settings: apart)
        schedule.resetRegular(.walk, settings: apart)
        #expect(schedule.walk.regularRemaining == apart.walkInterval)
        #expect(schedule.water.regularRemaining == 30 * 60)
    }

    @Test("Locking the screen for a few seconds does not restart the walk timer")
    func shortAbsenceKeepsWalkTimer() {
        var schedule = ReminderSchedule(settings: apart)
        _ = schedule.advance(by: 90 * 60, settings: apart)
        let counted = schedule.recordAbsence(17, settings: apart)
        #expect(!counted)
        #expect(schedule.walk.regularRemaining == 60 * 60)
    }

    @Test("An absence as long as the idle threshold counts as a walk break")
    func longAbsenceRestartsWalkTimer() {
        var schedule = ReminderSchedule(settings: apart)
        _ = schedule.advance(by: 90 * 60, settings: apart)
        let counted = schedule.recordAbsence(apart.idleThreshold, settings: apart)
        #expect(counted)
        #expect(schedule.walk.regularRemaining == apart.walkInterval)
        #expect(schedule.water.regularRemaining == 30 * 60)
    }

    @Test("Shorter intervals clamp the remaining time")
    func adaptClamps() {
        var schedule = ReminderSchedule(settings: settings)
        var shorter = settings
        shorter.walkInterval = 30 * 60
        schedule.adapt(to: shorter)
        #expect(schedule.walk.regularRemaining == 30 * 60)
        #expect(schedule.water.regularRemaining == settings.waterInterval)
    }

    @Test("Corrupt persisted values are repaired")
    func sanitize() {
        let broken = ReminderSchedule(
            water: .init(regularRemaining: .nan),
            walk: .init(regularRemaining: -5, snooze: .init(recordID: UUID(), remaining: .infinity))
        )
        let repaired = broken.sanitized(for: settings)
        #expect(repaired.water.regularRemaining == settings.waterInterval)
        #expect(repaired.walk.regularRemaining == settings.walkInterval)
        #expect(repaired.walk.snooze?.remaining == settings.snoozeLength)
    }

    @Test("Zero, negative and non-finite elapsed time is ignored")
    func ignoresBadElapsed() {
        var schedule = ReminderSchedule(settings: settings)
        let before = schedule
        let events = schedule.advance(by: 0, settings: settings)
            + schedule.advance(by: -10, settings: settings)
            + schedule.advance(by: .infinity, settings: settings)
        #expect(events.isEmpty)
        #expect(schedule == before)
    }
}

@Suite("ReminderSettings")
struct ReminderSettingsTests {
    @Test("Validation clamps out-of-range and non-finite values")
    func validation() {
        let settings = ReminderSettings(
            waterInterval: 1,
            walkInterval: 1_000_000,
            snoozeLength: .nan,
            responseWindow: 5,
            idleThreshold: 0
        ).validated()

        #expect(settings.waterInterval == ReminderSettings.intervalRange.lowerBound)
        #expect(settings.walkInterval == ReminderSettings.intervalRange.upperBound)
        #expect(settings.snoozeLength == ReminderSettings.default.snoozeLength)
        #expect(settings.responseWindow == 15)
        #expect(settings.idleThreshold == ReminderSettings.idleThresholdRange.lowerBound)
    }

    @Test("Missing keys decode to defaults")
    func decodesPartialJSON() throws {
        let data = Data(#"{"waterInterval": 1800}"#.utf8)
        let settings = try JSONDecoder().decode(ReminderSettings.self, from: data)
        #expect(settings.waterInterval == 1800)
        #expect(settings.walkInterval == ReminderSettings.default.walkInterval)
    }
}

@Suite("DurationText")
struct DurationTextTests {
    @Test(arguments: [
        (0.0, "now"),
        (30.0, "under 1 min"),
        (60.0, "1 min"),
        (61.0, "2 min"),
        (3600.0, "1 h"),
        (4320.0, "1 h 12 min"),
    ])
    func formatting(seconds: TimeInterval, expected: String) {
        #expect(DurationText.short(seconds) == expected)
    }

    @Test(arguments: [
        (15.0, "15 s"),
        (30.0, "30 s"),
        (60.0, "1 min"),
        (600.0, "10 min"),
    ])
    func settingFormatting(seconds: TimeInterval, expected: String) {
        #expect(DurationText.setting(seconds) == expected)
    }
}
