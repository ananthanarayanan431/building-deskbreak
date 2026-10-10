import AppKit
import DeskBreakCore
import Foundation

/// Owns all app state and the single wake-up timer.
///
/// Active time is measured with `SuspendingClock`, which stops while the Mac sleeps (F6).
/// Instead of ticking every second, the controller sleeps until the next thing that can change
/// state: a reminder becoming due, a response window closing, the pause ending, or the idle
/// threshold possibly being reached.
@MainActor
final class AppController: ObservableObject {
    enum Activity: Equatable {
        case active
        /// No input for at least the idle threshold.
        case away
        /// Screen locked or another user's session is in front.
        case locked
    }

    // MARK: Published state

    @Published private(set) var settings: ReminderSettings
    @Published private(set) var schedule: ReminderSchedule
    @Published private(set) var log: ReminderLog
    @Published private(set) var pauseUntil: Date?
    @Published private(set) var activity: Activity = .active
    @Published private(set) var notificationStatus: NotificationService.Status = .unknown
    @Published private(set) var loginItemState: LoginItem.State = .disabled
    @Published private(set) var lastError: String?

    var isPaused: Bool { pauseUntil != nil }

    // MARK: Tuning

    static let manualPauseLength: TimeInterval = 60 * 60
    private static let logRetention: TimeInterval = 60 * 24 * 60 * 60
    /// How often to check for the user's return while away. Only used while away, not while locked.
    private static let awayPollInterval: TimeInterval = 5
    private static let minimumWake: TimeInterval = 1
    /// Upper bound on any sleep, as a safety net against a missed system notification.
    private static let maximumWake: TimeInterval = 60 * 60

    // MARK: Dependencies and internals

    private let stateStore: StateStore
    private let logStore: LogFileStore?
    private let notifications = NotificationService()
    private let monitor = ActivityMonitor()
    private let clock = SuspendingClock()

    /// Set while active time is being counted; the last instant already credited to the timers.
    private var lastTick: SuspendingClock.Instant?
    private var screenLocked = false
    private var wakeTask: Task<Void, Never>?
    private var started = false

    private var isCounting: Bool { activity == .active && pauseUntil == nil }

    init(stateStore: StateStore = StateStore()) {
        self.stateStore = stateStore
        let settings = stateStore.loadSettings()
        self.settings = settings
        self.schedule = stateStore.loadSchedule(settings: settings)
        self.pauseUntil = stateStore.pauseUntil

        do {
            let store = try LogFileStore.standard()
            self.log = try store.load()
            self.logStore = store
            self.lastError = nil
        } catch {
            // Keep running without touching the file; reminders still work, only history is affected.
            self.log = ReminderLog()
            self.logStore = nil
            self.lastError = "Could not open the reminder log: \(error.localizedDescription)"
            Log.storage.error("Log unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        notifications.onResponse = { [weak self] recordID, response in
            self?.handle(response, for: recordID)
        }
        notifications.activate(snoozeLength: settings.snoozeLength)

        monitor.onEvent = { [weak self] event in
            self?.handle(event)
        }
        monitor.start()

        reconcileLogWithSchedule()
        log.prune(firedBefore: Date().addingTimeInterval(-Self.logRetention))
        saveLog()

        refreshLoginItemState()
        Task {
            await notifications.requestAuthorization()
            await refreshNotificationStatus()
        }

        Log.app.info("Started")
        refresh()
    }

    /// Credits active time up to now and saves everything. Called on quit.
    func shutdown() {
        accrueActiveTime()
        wakeTask?.cancel()
        wakeTask = nil
        monitor.stop()
        persistState()
        saveLog()
        Log.app.info("Stopped")
    }

    // MARK: User actions

    func pause(for length: TimeInterval = AppController.manualPauseLength) {
        pauseUntil = Date().addingTimeInterval(length)
        Log.scheduler.info("Paused for \(Int(length)) s")
        refresh()
    }

    func resume() {
        pauseUntil = nil
        Log.scheduler.info("Resumed")
        refresh()
    }

    func updateSettings(_ proposed: ReminderSettings) {
        let newSettings = proposed.validated()
        guard newSettings != settings else { return }

        // Credit time already elapsed under the old settings before changing anything.
        accrueActiveTime()
        let snoozeLengthChanged = newSettings.snoozeLength != settings.snoozeLength
        settings = newSettings
        schedule.adapt(to: newSettings)
        stateStore.save(newSettings)
        if snoozeLengthChanged {
            notifications.registerCategory(snoozeLength: newSettings.snoozeLength)
        }
        refresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = "Could not change launch at login: \(error.localizedDescription)"
            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshLoginItemState()
    }

    func refreshLoginItemState() {
        loginItemState = LoginItem.state
    }

    func refreshNotificationStatus() async {
        notificationStatus = await notifications.currentStatus()
    }

    func openNotificationSettings() {
        notifications.openSystemSettings()
    }

    func openLoginItemSettings() {
        LoginItem.openSystemSettings()
    }

    // MARK: Read-only views for the UI

    /// Remaining active seconds for a kind, including time elapsed since the last tick.
    func remaining(for kind: ReminderKind) -> (regular: TimeInterval, snooze: TimeInterval?) {
        let uncredited = lastTick.map { DurationText.seconds($0.duration(to: clock.now)) } ?? 0
        let slot = schedule[kind]
        return (
            max(0, slot.regularRemaining - uncredited),
            slot.snooze.map { max(0, $0.remaining - uncredited) }
        )
    }

    func todaySummary(now: Date = Date()) -> DailySummary {
        log.summary(for: now)
    }

    // MARK: The state pump

    /// Brings every piece of state up to date with the present, then schedules the next wake-up.
    /// Safe to call at any time; every external change ends with a call to this.
    private func refresh() {
        accrueActiveTime()

        if let pauseUntil, pauseUntil <= Date() {
            self.pauseUntil = nil
            Log.scheduler.info("Pause ended")
        }

        updateActivity()

        // Start or stop counting according to the new state.
        if isCounting {
            if lastTick == nil { lastTick = clock.now }
        } else {
            lastTick = nil
        }

        expireOverdueResponses()
        persistState()
        scheduleWake()
    }

    /// Credits active time since the last tick to the timers and handles anything that became due.
    private func accrueActiveTime() {
        guard let last = lastTick else { return }
        let now = clock.now
        lastTick = now
        let elapsed = DurationText.seconds(last.duration(to: now))
        let events = schedule.advance(by: elapsed, settings: settings)
        handle(events)
    }

    private func updateActivity() {
        let newActivity: Activity
        if screenLocked {
            newActivity = .locked
        } else if ActivityMonitor.secondsSinceLastInput() >= settings.idleThreshold {
            newActivity = .away
        } else {
            newActivity = .active
        }
        guard newActivity != activity else { return }

        let leavingDesk = activity == .active
        activity = newActivity
        Log.scheduler.info("Activity changed to \(String(describing: newActivity), privacy: .public)")

        // F7: being away already counts as a walk break, so the walk timer starts over.
        if leavingDesk {
            schedule.resetRegular(.walk, settings: settings)
        }
    }

    private func scheduleWake() {
        var candidates: [TimeInterval] = []

        if isCounting {
            candidates.append(schedule.nextDue)
        }
        if let pauseUntil {
            candidates.append(pauseUntil.timeIntervalSinceNow)
        }
        if let deadline = log.nextResponseDeadline {
            candidates.append(deadline.timeIntervalSinceNow)
        }
        switch activity {
        case .active:
            // The earliest moment the idle threshold could be reached, assuming no further input.
            candidates.append(settings.idleThreshold - ActivityMonitor.secondsSinceLastInput())
        case .away:
            candidates.append(Self.awayPollInterval)
        case .locked:
            // Unlock arrives as a notification; nothing to poll.
            break
        }

        let delay = min(max(candidates.min() ?? Self.maximumWake, Self.minimumWake), Self.maximumWake)

        wakeTask?.cancel()
        wakeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay), tolerance: .seconds(1), clock: .suspending)
            } catch {
                return // Cancelled by a newer schedule.
            }
            self?.refresh()
        }
    }

    // MARK: Events

    private func handle(_ events: [ReminderSchedule.Event]) {
        for event in events {
            switch event {
            case .regularDue(let kind):
                fireRegular(kind)
            case .snoozeDue(_, let recordID):
                fireFollowUp(recordID)
            case .snoozeCancelled(_, let recordID):
                resolve(recordID, as: .missed)
            }
        }
    }

    private func handle(_ event: ActivityMonitor.Event) {
        switch event {
        case .screenLocked:
            screenLocked = true
        case .screenUnlocked:
            screenLocked = false
        case .willSleep, .didWake:
            break
        }
        refresh()
    }

    private func handle(_ response: ReminderResponse, for recordID: UUID) {
        accrueActiveTime()

        guard let record = log.record(id: recordID), record.status == .awaiting else {
            Log.notifications.info("Ignoring answer for a reminder that is no longer awaiting one")
            refresh()
            return
        }

        switch response {
        case .done:
            resolve(recordID, as: .done)
        case .skipped:
            resolve(recordID, as: .skipped)
        case .dismissed:
            resolve(recordID, as: .missed)
        case .snoozed:
            log.update(id: recordID) { record in
                record.status = .snoozed
                record.respondBy = nil
                record.snoozeCount += 1
            }
            if let cancelled = schedule.snooze(record.kind, recordID: recordID, length: settings.snoozeLength) {
                handle([cancelled])
            }
            saveLog()
        }
        refresh()
    }

    private func fireRegular(_ kind: ReminderKind) {
        let now = Date()
        // A previous reminder of the same kind still on screen can no longer be answered meaningfully.
        for stale in log.records(kind: kind, status: .awaiting) {
            resolve(stale.id, as: .missed)
        }

        let record = ReminderRecord(
            kind: kind,
            firedAt: now,
            respondBy: now.addingTimeInterval(settings.responseWindow)
        )
        log.append(record)
        saveLog()
        notifications.post(record, isFollowUp: false)
        Log.scheduler.info("Fired \(kind.rawValue, privacy: .public) reminder")
    }

    private func fireFollowUp(_ recordID: UUID) {
        guard let record = log.record(id: recordID), record.status == .snoozed else { return }
        let now = Date()
        guard let updated = log.update(id: recordID, { record in
            record.status = .awaiting
            record.respondBy = now.addingTimeInterval(settings.responseWindow)
        }) else { return }
        saveLog()
        notifications.post(updated, isFollowUp: true)
        Log.scheduler.info("Fired snoozed \(record.kind.rawValue, privacy: .public) reminder")
    }

    private func resolve(_ recordID: UUID, as status: ReminderStatus) {
        guard log.resolve(id: recordID, as: status, at: Date()) else { return }
        notifications.remove(recordID: recordID)
        saveLog()
    }

    private func expireOverdueResponses() {
        let expired = log.expireOverdue(now: Date())
        guard !expired.isEmpty else { return }
        for record in expired {
            notifications.remove(recordID: record.id)
        }
        saveLog()
        Log.scheduler.info("Marked \(expired.count) reminder(s) as missed")
    }

    /// After a restart, a snoozed record must still have its follow-up timer; otherwise it can never resolve.
    private func reconcileLogWithSchedule() {
        let pendingSnoozes = Set(ReminderKind.allCases.compactMap { schedule[$0].snooze?.recordID })
        for kind in ReminderKind.allCases {
            for record in log.records(kind: kind, status: .snoozed) where !pendingSnoozes.contains(record.id) {
                resolve(record.id, as: .missed)
            }
            if let snoozed = schedule[kind].snooze,
               log.record(id: snoozed.recordID)?.status != .snoozed {
                schedule.cancelSnooze(kind)
            }
        }
    }

    // MARK: Persistence

    private func persistState() {
        stateStore.save(schedule)
        stateStore.pauseUntil = pauseUntil
    }

    private func saveLog() {
        guard let logStore else { return }
        do {
            try logStore.save(log)
        } catch {
            lastError = "Could not save the reminder log: \(error.localizedDescription)"
            Log.storage.error("Log save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
