import Foundation

/// One fired reminder. Snoozes reuse the same record, so its final status is the follow-up's answer.
public struct ReminderRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ReminderKind
    /// When the regular reminder fired. The record counts toward this day, even if answered after midnight.
    public let firedAt: Date
    public var status: ReminderStatus
    /// Deadline for an answer while `status == .awaiting`.
    public var respondBy: Date?
    public var snoozeCount: Int
    public var resolvedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ReminderKind,
        firedAt: Date,
        status: ReminderStatus = .awaiting,
        respondBy: Date?,
        snoozeCount: Int = 0,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.firedAt = firedAt
        self.status = status
        self.respondBy = respondBy
        self.snoozeCount = snoozeCount
        self.resolvedAt = resolvedAt
    }
}

/// Done-out-of-fired counts for one day.
public struct DailySummary: Equatable, Sendable {
    public struct Count: Equatable, Sendable {
        public var done: Int
        public var fired: Int

        public init(done: Int = 0, fired: Int = 0) {
            self.done = done
            self.fired = fired
        }
    }

    public var water = Count()
    public var walk = Count()

    public init() {}

    public subscript(kind: ReminderKind) -> Count {
        get {
            switch kind {
            case .water: water
            case .walk: walk
            }
        }
        set {
            switch kind {
            case .water: water = newValue
            case .walk: walk = newValue
            }
        }
    }
}

/// The in-memory reminder history, ordered by fire time.
public struct ReminderLog: Equatable, Sendable {
    public private(set) var records: [ReminderRecord]

    public init(records: [ReminderRecord] = []) {
        self.records = records.sorted { $0.firedAt < $1.firedAt }
    }

    public func record(id: UUID) -> ReminderRecord? {
        records.first { $0.id == id }
    }

    public func records(kind: ReminderKind, status: ReminderStatus) -> [ReminderRecord] {
        records.filter { $0.kind == kind && $0.status == status }
    }

    public mutating func append(_ record: ReminderRecord) {
        records.append(record)
    }

    /// Applies `change` to the record with `id`. Returns the updated record, or nil if not found.
    @discardableResult
    public mutating func update(id: UUID, _ change: (inout ReminderRecord) -> Void) -> ReminderRecord? {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
        change(&records[index])
        return records[index]
    }

    /// Moves a non-final record to a final status. Returns false if the record is missing or already final.
    @discardableResult
    public mutating func resolve(id: UUID, as status: ReminderStatus, at date: Date) -> Bool {
        precondition(status.isFinal, "resolve(id:as:at:) requires a final status")
        guard let current = record(id: id), !current.status.isFinal else { return false }
        update(id: id) { record in
            record.status = status
            record.respondBy = nil
            record.resolvedAt = date
        }
        return true
    }

    /// The earliest response deadline among records awaiting an answer.
    public var nextResponseDeadline: Date? {
        records.lazy
            .filter { $0.status == .awaiting }
            .compactMap(\.respondBy)
            .min()
    }

    /// Marks every awaiting record whose response window has closed as missed (F8) and returns them.
    public mutating func expireOverdue(now: Date) -> [ReminderRecord] {
        var expired: [ReminderRecord] = []
        for index in records.indices where records[index].status == .awaiting {
            // A record without a deadline cannot otherwise ever be resolved, so treat it as overdue.
            guard records[index].respondBy.map({ $0 <= now }) ?? true else { continue }
            records[index].status = .missed
            records[index].respondBy = nil
            records[index].resolvedAt = now
            expired.append(records[index])
        }
        return expired
    }

    /// Counts for the calendar day containing `day`, attributed by fire time.
    public func summary(for day: Date, calendar: Calendar = .current) -> DailySummary {
        var summary = DailySummary()
        for record in records where calendar.isDate(record.firedAt, inSameDayAs: day) {
            summary[record.kind].fired += 1
            if record.status == .done {
                summary[record.kind].done += 1
            }
        }
        return summary
    }

    /// Drops final records fired before `cutoff`. Unresolved records are always kept.
    public mutating func prune(firedBefore cutoff: Date) {
        records.removeAll { $0.firedAt < cutoff && $0.status.isFinal }
    }
}
