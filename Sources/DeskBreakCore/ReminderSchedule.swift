import Foundation

/// The countdown state for both reminder kinds, measured in seconds of *active* time.
///
/// This type knows nothing about clocks, idle detection or how reminders are shown. The caller decides
/// when time is "active" and feeds the elapsed amount to `advance(by:settings:)`, which keeps
/// the rules (restart on fire, snooze cancellation) pure and testable.
public struct ReminderSchedule: Codable, Equatable, Sendable {
    public struct Snooze: Codable, Equatable, Sendable {
        /// The log record the follow-up belongs to.
        public var recordID: UUID
        public var remaining: TimeInterval

        public init(recordID: UUID, remaining: TimeInterval) {
            self.recordID = recordID
            self.remaining = remaining
        }
    }

    public struct Slot: Codable, Equatable, Sendable {
        /// Active seconds until the next regular reminder.
        public var regularRemaining: TimeInterval
        /// A pending one-shot follow-up, independent of the regular timer.
        public var snooze: Snooze?

        public init(regularRemaining: TimeInterval, snooze: Snooze? = nil) {
            self.regularRemaining = regularRemaining
            self.snooze = snooze
        }

        /// Active seconds until this slot next needs attention.
        public var nextDue: TimeInterval {
            min(regularRemaining, snooze?.remaining ?? .infinity)
        }
    }

    public enum Event: Equatable, Sendable {
        case regularDue(ReminderKind)
        case snoozeDue(ReminderKind, recordID: UUID)
        /// A pending snooze was dropped because the next regular reminder of the same kind fired first.
        case snoozeCancelled(ReminderKind, recordID: UUID)
    }

    /// Timers within this many seconds of zero count as due, absorbing floating point drift.
    static let dueTolerance: TimeInterval = 0.5

    /// The least active time between a water and a walk reminder, so the two never arrive together.
    public static let minimumGap: TimeInterval = 15 * 60

    public private(set) var water: Slot
    public private(set) var walk: Slot

    public init(settings: ReminderSettings) {
        water = Slot(regularRemaining: settings.waterInterval)
        walk = Slot(regularRemaining: settings.walkInterval)
        separateRegularTimers()
    }

    public init(water: Slot, walk: Slot) {
        self.water = water
        self.walk = walk
    }

    public subscript(kind: ReminderKind) -> Slot {
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

    /// Active seconds until any timer is due.
    public var nextDue: TimeInterval {
        max(0, min(water.nextDue, walk.nextDue))
    }

    /// Counts down every timer by `elapsed` seconds of active time and returns what became due.
    ///
    /// A regular reminder restarts the moment it fires (F4) and fires at most once per call,
    /// so a long gap never produces a burst. If it fires while a snooze for the same kind is
    /// pending, the snooze is cancelled (F5). Cancellations are reported before the fire.
    public mutating func advance(by elapsed: TimeInterval, settings: ReminderSettings) -> [Event] {
        guard elapsed > 0, elapsed.isFinite else { return [] }

        var events: [Event] = []
        for kind in ReminderKind.allCases {
            var slot = self[kind]
            slot.regularRemaining -= elapsed

            if slot.regularRemaining <= Self.dueTolerance {
                let interval = settings.interval(for: kind)
                let overshoot = max(0, -slot.regularRemaining)
                slot.regularRemaining = overshoot < interval ? interval - overshoot : interval
                if let snooze = slot.snooze {
                    events.append(.snoozeCancelled(kind, recordID: snooze.recordID))
                    slot.snooze = nil
                }
                events.append(.regularDue(kind))
            } else if var snooze = slot.snooze {
                snooze.remaining -= elapsed
                if snooze.remaining <= Self.dueTolerance {
                    events.append(.snoozeDue(kind, recordID: snooze.recordID))
                    slot.snooze = nil
                } else {
                    slot.snooze = snooze
                }
            }

            self[kind] = slot
        }
        separateRegularTimers()
        return events
    }

    /// Starts a one-shot follow-up for `recordID`. Returns a cancellation event if it replaced
    /// a different pending snooze of the same kind.
    public mutating func snooze(
        _ kind: ReminderKind,
        recordID: UUID,
        length: TimeInterval
    ) -> Event? {
        let previous = self[kind].snooze
        self[kind].snooze = Snooze(recordID: recordID, remaining: length)
        guard let previous, previous.recordID != recordID else { return nil }
        return .snoozeCancelled(kind, recordID: previous.recordID)
    }

    /// Restarts the regular timer at its full interval. Used for the walk timer after an idle break.
    public mutating func resetRegular(_ kind: ReminderKind, settings: ReminderSettings) {
        self[kind].regularRemaining = settings.interval(for: kind)
        separateRegularTimers()
    }

    /// Called when the user is back at the desk. An absence of at least the idle threshold counts as
    /// a walk break and restarts the walk timer (F7); a shorter one, such as locking the screen for a
    /// few seconds, leaves it alone. Returns whether the absence counted.
    @discardableResult
    public mutating func recordAbsence(_ duration: TimeInterval, settings: ReminderSettings) -> Bool {
        guard duration >= settings.idleThreshold else { return false }
        resetRegular(.walk, settings: settings)
        return true
    }

    /// Removes a pending snooze and returns its record ID, if there was one.
    @discardableResult
    public mutating func cancelSnooze(_ kind: ReminderKind) -> UUID? {
        let recordID = self[kind].snooze?.recordID
        self[kind].snooze = nil
        return recordID
    }

    /// Keeps the countdowns consistent after a settings change: no timer may exceed its new length.
    public mutating func adapt(to settings: ReminderSettings) {
        for kind in ReminderKind.allCases {
            var slot = self[kind]
            slot.regularRemaining = min(slot.regularRemaining, settings.interval(for: kind))
            if var snooze = slot.snooze {
                snooze.remaining = min(snooze.remaining, settings.snoozeLength)
                slot.snooze = snooze
            }
            self[kind] = slot
        }
        separateRegularTimers()
    }

    /// Repairs state loaded from disk: non-finite or out-of-range values are reset.
    public func sanitized(for settings: ReminderSettings) -> ReminderSchedule {
        var copy = self
        for kind in ReminderKind.allCases {
            var slot = copy[kind]
            let interval = settings.interval(for: kind)
            // A timer may sit up to `minimumGap` past its interval after being moved apart from the other.
            if !slot.regularRemaining.isFinite || slot.regularRemaining <= 0
                || slot.regularRemaining > interval + Self.minimumGap {
                slot.regularRemaining = interval
            }
            if let snooze = slot.snooze,
               !snooze.remaining.isFinite || snooze.remaining <= 0 || snooze.remaining > settings.snoozeLength {
                slot.snooze?.remaining = settings.snoozeLength
            }
            copy[kind] = slot
        }
        copy.separateRegularTimers()
        return copy
    }

    /// Delays the later regular reminder until it is at least `minimumGap` after the earlier one.
    /// On a tie the water reminder moves, since it comes round more often than the walk reminder.
    mutating func separateRegularTimers() {
        let gap = abs(water.regularRemaining - walk.regularRemaining)
        guard gap < Self.minimumGap else { return }
        if water.regularRemaining >= walk.regularRemaining {
            water.regularRemaining = walk.regularRemaining + Self.minimumGap
        } else {
            walk.regularRemaining = water.regularRemaining + Self.minimumGap
        }
    }
}
