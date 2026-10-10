import Foundation
import os

/// Unified logging categories. Visible in Console.app; nothing is written to disk by the app itself.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.ananthanarayanan431.deskbreak"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
