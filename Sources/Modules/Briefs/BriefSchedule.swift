import Foundation

/// Decides when the morning build runs: one try each day, between 5:00 and noon.
public enum BriefSchedule {

    public static func isDue(now: Date, lastTry: Date?, enabled: Bool, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        guard (5..<12).contains(calendar.component(.hour, from: now)) else { return false }
        return lastTry.map { !calendar.isDate($0, inSameDayAs: now) } ?? true
    }
}
