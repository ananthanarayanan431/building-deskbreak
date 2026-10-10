import DeskBreakCore
import Foundation

/// Settings and timer state, kept in the app's own preferences (`~/Library/Preferences/<bundle id>.plist`).
@MainActor
final class StateStore {
    private enum Key {
        static let settings = "settings.v1"
        static let schedule = "schedule.v1"
        static let pauseUntil = "pauseUntil.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> ReminderSettings {
        decode(ReminderSettings.self, forKey: Key.settings)?.validated() ?? .default
    }

    func save(_ settings: ReminderSettings) {
        encode(settings, forKey: Key.settings)
    }

    func loadSchedule(settings: ReminderSettings) -> ReminderSchedule {
        decode(ReminderSchedule.self, forKey: Key.schedule)?.sanitized(for: settings)
            ?? ReminderSchedule(settings: settings)
    }

    func save(_ schedule: ReminderSchedule) {
        encode(schedule, forKey: Key.schedule)
    }

    var pauseUntil: Date? {
        get { defaults.object(forKey: Key.pauseUntil) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.pauseUntil)
            } else {
                defaults.removeObject(forKey: Key.pauseUntil)
            }
        }
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        do {
            defaults.set(try encoder.encode(value), forKey: key)
        } catch {
            Log.storage.error("Failed to encode \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Log.storage.error("Discarding unreadable \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
