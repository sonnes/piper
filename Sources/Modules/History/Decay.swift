import Foundation

/// The ranking formula of Hacker News: points that lose weight with age.
public enum Decay {

    /// A higher gravity makes old items lose weight faster.
    public static let gravity = 1.8

    /// Gives `points / (hours + 2) ^ gravity`. A negative age counts as 0.
    public static func score(points: Double, hours: Double) -> Double {
        points / pow(max(hours, 0) + 2, gravity)
    }

    /// The hours from `date` to `now`.
    public static func hours(from date: Date, to now: Date) -> Double {
        now.timeIntervalSince(date) / 3_600
    }
}
