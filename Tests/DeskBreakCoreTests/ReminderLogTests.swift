import Foundation
import Testing
@testable import DeskBreakCore

@Suite("ReminderLog")
struct ReminderLogTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test("Overdue awaiting records become missed; others are untouched")
    func expiry() {
        let overdue = ReminderRecord(kind: .water, firedAt: date(10, 9), respondBy: date(10, 9, 10))
        let open = ReminderRecord(kind: .walk, firedAt: date(10, 9, 5), respondBy: date(10, 9, 15))
        let done = ReminderRecord(kind: .water, firedAt: date(10, 8), status: .done, respondBy: nil)
        var log = ReminderLog(records: [overdue, open, done])

        let expired = log.expireOverdue(now: date(10, 9, 12))

        #expect(expired.map(\.id) == [overdue.id])
        #expect(log.record(id: overdue.id)?.status == .missed)
        #expect(log.record(id: open.id)?.status == .awaiting)
        #expect(log.nextResponseDeadline == date(10, 9, 15))
    }

    @Test("Final records cannot be resolved again")
    func resolveOnce() {
        let record = ReminderRecord(kind: .water, firedAt: date(10, 9), respondBy: date(10, 9, 10))
        var log = ReminderLog(records: [record])

        let first = log.resolve(id: record.id, as: .done, at: date(10, 9, 1))
        let second = log.resolve(id: record.id, as: .missed, at: date(10, 9, 2))
        #expect(first)
        #expect(!second)
        #expect(log.record(id: record.id)?.status == .done)
    }

    @Test("Daily counts are attributed to the day the reminder fired")
    func summaryUsesFireDay() {
        let lateNight = ReminderRecord(
            kind: .water, firedAt: date(10, 23, 55), status: .done, respondBy: nil, resolvedAt: date(11, 0, 2)
        )
        let morning = ReminderRecord(kind: .water, firedAt: date(11, 9), status: .skipped, respondBy: nil)
        let walk = ReminderRecord(kind: .walk, firedAt: date(11, 10), status: .done, respondBy: nil)
        let log = ReminderLog(records: [lateNight, morning, walk])

        let day10 = log.summary(for: date(10, 12), calendar: calendar)
        let day11 = log.summary(for: date(11, 12), calendar: calendar)

        #expect(day10.water == .init(done: 1, fired: 1))
        #expect(day11.water == .init(done: 0, fired: 1))
        #expect(day11.walk == .init(done: 1, fired: 1))
    }

    @Test("Pruning keeps unresolved records")
    func pruneKeepsOpenRecords() {
        let oldDone = ReminderRecord(kind: .water, firedAt: date(1, 9), status: .done, respondBy: nil)
        let oldSnoozed = ReminderRecord(kind: .walk, firedAt: date(1, 9), status: .snoozed, respondBy: nil)
        var log = ReminderLog(records: [oldDone, oldSnoozed])

        log.prune(firedBefore: date(5, 0))
        #expect(log.records.map(\.id) == [oldSnoozed.id])
    }
}

@Suite("LogFileStore")
struct LogFileStoreTests {
    func makeStore() throws -> (LogFileStore, URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeskBreakTests-\(UUID().uuidString)", isDirectory: true)
        return (LogFileStore(applicationSupportDirectory: base), base)
    }

    @Test("A missing file loads as an empty log")
    func missingFile() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(try store.load().records.isEmpty)
    }

    @Test("Saved records round-trip")
    func roundTrip() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        let record = ReminderRecord(
            kind: .walk,
            firedAt: Date(timeIntervalSince1970: 1_800_000_000),
            status: .done,
            respondBy: nil,
            snoozeCount: 2,
            resolvedAt: Date(timeIntervalSince1970: 1_800_000_060)
        )
        try store.save(ReminderLog(records: [record]))

        #expect(try store.load().records == [record])
    }

    @Test("An unreadable file is set aside and replaced by an empty log")
    func corruptFile() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        #expect(try store.load().records.isEmpty)
        #expect(try Data(contentsOf: store.quarantineURL) == Data("not json".utf8))
    }

    @Test("A log from a newer schema is not overwritten")
    func newerSchema() throws {
        let (store, base) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }

        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 99, "records": []}"#.utf8).write(to: store.fileURL)

        #expect(throws: LogFileStore.StoreError.self) { try store.load() }
    }
}
