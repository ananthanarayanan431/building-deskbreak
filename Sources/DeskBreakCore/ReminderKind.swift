import Foundation

/// The two kinds of reminder the app tracks. Each has its own independent timer.
public enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case water
    case walk
}

/// The state of one fired reminder in the log.
///
/// `awaiting` and `snoozed` are transient; `done`, `skipped` and `missed` are final.
public enum ReminderStatus: String, Codable, Sendable {
    /// The notification is on screen and the response window is open.
    case awaiting
    /// The user chose "Remind me later"; the follow-up has not fired yet.
    case snoozed
    case done
    case skipped
    case missed

    public var isFinal: Bool {
        switch self {
        case .awaiting, .snoozed: false
        case .done, .skipped, .missed: true
        }
    }
}

/// How the user answered a reminder notification.
public enum ReminderResponse: Sendable, Equatable {
    case done
    case skipped
    case snoozed
    /// Closed with the X, or clicked without choosing a button.
    case dismissed
}
