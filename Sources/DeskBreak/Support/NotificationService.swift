import AppKit
import DeskBreakCore
import UserNotifications

/// Posts reminder notifications and turns the user's answers into `ReminderResponse`s.
///
/// Notifications are posted immediately (no trigger) when the app's own active-time timer is due.
/// They are never scheduled in advance with the system, because those triggers run on wall-clock time.
@MainActor
final class NotificationService: NSObject {
    enum Status: Equatable {
        case unknown
        case notDetermined
        case denied
        /// Allowed, but banners disappear on their own; reminders should use the "Alerts" style.
        case banners
        case alerts
    }

    private enum ActionID {
        static let done = "deskbreak.action.done"
        static let skip = "deskbreak.action.skip"
        static let snooze = "deskbreak.action.snooze"
    }

    private static let categoryID = "deskbreak.reminder"
    nonisolated private static let recordIDKey = "recordID"

    var onResponse: ((UUID, ReminderResponse) -> Void)?

    /// Accessed lazily: `UNUserNotificationCenter.current()` traps when the process is not inside an app bundle.
    private var center: UNUserNotificationCenter { .current() }

    /// Must be called from `applicationDidFinishLaunching` so answers that relaunch the app are delivered.
    func activate(snoozeLength: TimeInterval) {
        center.delegate = self
        registerCategory(snoozeLength: snoozeLength)
    }

    func registerCategory(snoozeLength: TimeInterval) {
        let minutes = max(1, Int((snoozeLength / 60).rounded()))
        // No `.foreground` option: answering never activates the app or takes focus.
        let actions = [
            UNNotificationAction(identifier: ActionID.done, title: "I did", options: []),
            UNNotificationAction(identifier: ActionID.skip, title: "Not doing", options: []),
            UNNotificationAction(identifier: ActionID.snooze, title: "Remind me in \(minutes) min", options: []),
        ]
        // `.customDismissAction` reports closing with the X, so it can be recorded as missed.
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async {
        do {
            // Alerts only: no sound, no badge.
            let granted = try await center.requestAuthorization(options: [.alert])
            Log.notifications.info("Notification authorization granted: \(granted)")
        } catch {
            Log.notifications.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func currentStatus() async -> Status {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                let status: Status = switch settings.authorizationStatus {
                case .notDetermined: .notDetermined
                case .denied: .denied
                case .authorized, .provisional:
                    settings.alertStyle == .alert ? .alerts : .banners
                @unknown default: .unknown
                }
                continuation.resume(returning: status)
            }
        }
    }

    func post(_ record: ReminderRecord, isFollowUp: Bool) {
        let content = UNMutableNotificationContent()
        switch record.kind {
        case .water:
            content.title = "Drink some water"
            content.body = "Time for a glass of water."
        case .walk:
            content.title = "Time to walk"
            content.body = "Stand up and walk for a few minutes."
        }
        if isFollowUp {
            content.subtitle = "Snoozed reminder"
        }
        content.sound = nil
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = record.kind.rawValue
        content.userInfo = [Self.recordIDKey: record.id.uuidString]
        content.interruptionLevel = .active

        let request = UNNotificationRequest(identifier: record.id.uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                Log.notifications.error("Failed to post reminder: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func remove(recordID: UUID) {
        let identifiers = [recordID.uuidString]
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func openSystemSettings() {
        // Opens System Settings → Notifications. A local settings URL, not a network request.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    nonisolated private static func response(for actionIdentifier: String) -> ReminderResponse? {
        switch actionIdentifier {
        case ActionID.done: .done
        case ActionID.skip: .skipped
        case ActionID.snooze: .snoozed
        // Closing, or clicking the body without choosing a button, is not an answer.
        case UNNotificationDismissActionIdentifier, UNNotificationDefaultActionIdentifier: .dismissed
        default: nil
        }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let rawID = request.content.userInfo[Self.recordIDKey] as? String ?? request.identifier
        guard let recordID = UUID(uuidString: rawID),
              let answer = Self.response(for: response.actionIdentifier)
        else {
            Log.notifications.error("Ignoring unrecognised notification response")
            return
        }
        await MainActor.run {
            self.onResponse?(recordID, answer)
        }
    }

    /// Shows reminders even while the menu is open (the app counts as frontmost then). Silent by design.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
