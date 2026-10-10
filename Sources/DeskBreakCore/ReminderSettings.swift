import Foundation

/// User-adjustable timings. All values are in seconds.
public struct ReminderSettings: Codable, Equatable, Sendable {
    public var waterInterval: TimeInterval
    public var walkInterval: TimeInterval
    public var snoozeLength: TimeInterval
    public var responseWindow: TimeInterval
    public var idleThreshold: TimeInterval

    public static let `default` = ReminderSettings(
        waterInterval: 60 * 60,
        walkInterval: 2 * 60 * 60,
        snoozeLength: 15 * 60,
        responseWindow: 15,
        idleThreshold: 15 * 60
    )

    public static let intervalRange: ClosedRange<TimeInterval> = (15 * 60)...(8 * 60 * 60)
    public static let snoozeRange: ClosedRange<TimeInterval> = (1 * 60)...(60 * 60)
    public static let responseWindowRange: ClosedRange<TimeInterval> = 15...(30 * 60)
    /// The values offered for the response window; short windows need finer steps than minutes.
    public static let responseWindowChoices: [TimeInterval] = [15, 30, 60, 2 * 60, 5 * 60, 10 * 60, 15 * 60, 30 * 60]
    public static let idleThresholdRange: ClosedRange<TimeInterval> = (1 * 60)...(60 * 60)

    public init(
        waterInterval: TimeInterval,
        walkInterval: TimeInterval,
        snoozeLength: TimeInterval,
        responseWindow: TimeInterval,
        idleThreshold: TimeInterval
    ) {
        self.waterInterval = waterInterval
        self.walkInterval = walkInterval
        self.snoozeLength = snoozeLength
        self.responseWindow = responseWindow
        self.idleThreshold = idleThreshold
    }

    public func interval(for kind: ReminderKind) -> TimeInterval {
        switch kind {
        case .water: waterInterval
        case .walk: walkInterval
        }
    }

    /// Returns a copy with every value clamped to its allowed range. Non-finite values fall back to defaults.
    public func validated() -> ReminderSettings {
        let fallback = ReminderSettings.default
        return ReminderSettings(
            waterInterval: Self.clamp(waterInterval, to: Self.intervalRange, fallback: fallback.waterInterval),
            walkInterval: Self.clamp(walkInterval, to: Self.intervalRange, fallback: fallback.walkInterval),
            snoozeLength: Self.clamp(snoozeLength, to: Self.snoozeRange, fallback: fallback.snoozeLength),
            responseWindow: Self.clamp(responseWindow, to: Self.responseWindowRange, fallback: fallback.responseWindow),
            idleThreshold: Self.clamp(idleThreshold, to: Self.idleThresholdRange, fallback: fallback.idleThreshold)
        )
    }

    private static func clamp(
        _ value: TimeInterval,
        to range: ClosedRange<TimeInterval>,
        fallback: TimeInterval
    ) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case waterInterval, walkInterval, snoozeLength, responseWindow, idleThreshold
    }

    /// Missing keys fall back to defaults, so settings saved by an older version still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = ReminderSettings.default
        self.init(
            waterInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .waterInterval) ?? fallback.waterInterval,
            walkInterval: try container.decodeIfPresent(TimeInterval.self, forKey: .walkInterval) ?? fallback.walkInterval,
            snoozeLength: try container.decodeIfPresent(TimeInterval.self, forKey: .snoozeLength) ?? fallback.snoozeLength,
            responseWindow: try container.decodeIfPresent(TimeInterval.self, forKey: .responseWindow) ?? fallback.responseWindow,
            idleThreshold: try container.decodeIfPresent(TimeInterval.self, forKey: .idleThreshold) ?? fallback.idleThreshold
        )
    }
}
