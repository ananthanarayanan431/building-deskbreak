import AppKit
import CoreGraphics

/// Reports screen lock, session switches and sleep/wake, and reads the time since the last input.
///
/// Idle detection reads only the number of seconds since the last keyboard, mouse or tablet event.
/// It never sees keys or positions and needs no Accessibility or Input Monitoring permission.
@MainActor
final class ActivityMonitor {
    enum Event {
        case screenLocked
        case screenUnlocked
        case willSleep
        case didWake
    }

    var onEvent: ((Event) -> Void)?

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// `kCGAnyInputEventType` is `~0` in C and has no Swift constant.
    private static let anyInputEventType = CGEventType(rawValue: ~0)!

    static func secondsSinceLastInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }

    func start() {
        guard observers.isEmpty else { return }

        // Posted by loginwindow when the screen locks or unlocks.
        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), as: .screenLocked)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), as: .screenUnlocked)

        // Fast user switching away from this account counts as locked.
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, as: .screenLocked)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, as: .screenUnlocked)
        observe(workspace, NSWorkspace.willSleepNotification, as: .willSleep)
        observe(workspace, NSWorkspace.didWakeNotification, as: .didWake)
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, as event: Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onEvent?(event)
            }
        }
        observers.append((center, token))
    }
}
